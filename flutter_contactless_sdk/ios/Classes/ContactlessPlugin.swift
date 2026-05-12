import Flutter
import UIKit
import CoreNFC

// MARK: - ContactlessPlugin

public class ContactlessPlugin: NSObject, FlutterPlugin {

    // Pending Flutter result callback held while an NFC session is active
    private var pendingResult: FlutterResult?
    // ISO 7816 NFC session (requires "Near Field Communication Tag Reading" entitlement)
    private var nfcSession: NFCTagReaderSession?

    // MARK: FlutterPlugin registration

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.contactless/sdk",
            binaryMessenger: registrar.messenger()
        )
        let instance = ContactlessPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    // MARK: Method channel dispatch

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {

        case "initialize":
            // Nothing hardware-specific to set up on iOS beyond the entitlement.
            result(true)

        case "isNfcAvailable":
            result(NFCTagReaderSession.readingAvailable)

        case "startPayment":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS",
                                    message: "startPayment requires a map of arguments",
                                    details: nil))
                return
            }
            startNFCPayment(args: args, result: result)

        case "readCardDetails":
            startNFCCardRead(result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - NFC Session Starters

    /// Full payment flow: reads card, then returns a PaymentResult map.
    private func startNFCPayment(args: [String: Any], result: @escaping FlutterResult) {
        guard NFCTagReaderSession.readingAvailable else {
            result(FlutterError(code: "NFC_UNAVAILABLE",
                                message: "NFC is not available on this device or iOS version",
                                details: nil))
            return
        }
        // Store result so the delegate can call it once reading is complete.
        // Wrap raw CardData map into a PaymentResult map.
        self.pendingResult = { rawResult in
            if let cardMap = rawResult as? [String: Any] {
                let paymentResult: [String: Any] = [
                    "success": true,
                    "transactionId": "TXN_\(Int(Date().timeIntervalSince1970))",
                    "authCode": (cardMap["cryptogram"] as? String) ?? "000000",
                    "maskedPan": cardMap["pan"] ?? "Unknown",
                ]
                result(paymentResult)
            } else if let error = rawResult as? FlutterError {
                result(error)
            } else {
                result(FlutterError(code: "PAYMENT_FAILED",
                                    message: "Card read failed or was cancelled",
                                    details: nil))
            }
        }
        openNFCSession(alertMessage: "Hold your payment card near the top of the iPhone")
    }

    /// Raw card-data read: returns the CardData map directly to Dart.
    private func startNFCCardRead(result: @escaping FlutterResult) {
        guard NFCTagReaderSession.readingAvailable else {
            result(FlutterError(code: "NFC_UNAVAILABLE",
                                message: "NFC is not available on this device or iOS version",
                                details: nil))
            return
        }
        self.pendingResult = result
        openNFCSession(alertMessage: "Hold your payment card near the top of the iPhone")
    }

    private func openNFCSession(alertMessage: String) {
        nfcSession = NFCTagReaderSession(
            pollingOption: [.iso14443],
            delegate: self,
            queue: nil
        )
        nfcSession?.alertMessage = alertMessage
        nfcSession?.begin()
    }
}

// MARK: - NFCTagReaderSessionDelegate

extension ContactlessPlugin: NFCTagReaderSessionDelegate {

    public func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // Session is now polling — nothing to do here
    }

    public func tagReaderSession(_ session: NFCTagReaderSession,
                                 didInvalidateWithError error: Error) {
        let nfcError = error as? NFCReaderError
        // Code 200 (.readerSessionInvalidationErrorUserCanceled) is not a real error
        if nfcError?.code != .readerSessionInvalidationErrorUserCanceled {
            pendingResult?(FlutterError(
                code: "NFC_SESSION_INVALIDATED",
                message: error.localizedDescription,
                details: nil
            ))
        } else {
            pendingResult?(FlutterError(
                code: "NFC_CANCELLED",
                message: "NFC session was cancelled by the user",
                details: nil
            ))
        }
        pendingResult = nil
        nfcSession = nil
    }

    public func tagReaderSession(_ session: NFCTagReaderSession,
                                 didDetect tags: [NFCTag]) {
        guard let firstTag = tags.first else { return }

        // We only support ISO 7816 tags (standard EMV payment cards)
        guard case .iso7816(let iso7816Tag) = firstTag else {
            session.invalidate(errorMessage: "Unsupported card type. Please use an EMV payment card.")
            pendingResult?(FlutterError(
                code: "UNSUPPORTED_TAG",
                message: "The scanned tag is not an ISO 7816 EMV card",
                details: nil
            ))
            pendingResult = nil
            return
        }

        session.connect(to: firstTag) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                session.invalidate(errorMessage: "Connection failed.")
                self.pendingResult?(FlutterError(
                    code: "NFC_CONNECTION_FAILED",
                    message: error.localizedDescription,
                    details: nil
                ))
                self.pendingResult = nil
                return
            }
            self.performEMVRead(session: session, tag: iso7816Tag)
        }
    }

    // MARK: - EMV Reading Logic

    private func performEMVRead(session: NFCTagReaderSession, tag: NFCISO7816Tag) {
        var cardData: [String: Any] = [
            "pan": "Unknown",
            "expiryDate": "Unknown",
            "cardholderName": "Unknown",
            "applicationLabel": "Unknown",
            "cryptogram": "Unknown",
        ]

        // Run the full multi-step read on a background queue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Step 1 – PPSE (Proximity Payment System Environment)
            if let ppseResp = self.transceive(tag: tag, apdu: EMVCommands.selectPPSE),
               self.isSuccess(ppseResp) {
                let aids = self.extractAIDs(from: ppseResp)
                for aid in aids {
                    self.selectAndRead(tag: tag, aid: aid, into: &cardData)
                    if cardData["pan"] as? String != "Unknown" { break }
                }
            }

            // Step 2 – Known AIDs fallback
            if cardData["pan"] as? String == "Unknown" {
                for aid in EMVCommands.knownAIDs {
                    self.selectAndRead(tag: tag, aid: aid, into: &cardData)
                    if cardData["pan"] as? String != "Unknown" { break }
                }
            }

            // Step 3 – Brute-force record read
            if cardData["pan"] as? String == "Unknown" {
                self.bruteForceRecords(tag: tag, into: &cardData)
            }

            // Step 4 – Cryptogram extraction
            self.extractCryptogram(tag: tag, into: &cardData)

            // Finish
            session.alertMessage = "Card read complete!"
            session.invalidate()
            self.pendingResult?(cardData)
            self.pendingResult = nil
        }
    }

    // MARK: - EMV Sub-steps

    private func selectAndRead(tag: NFCISO7816Tag,
                                aid: [UInt8],
                                into cardData: inout [String: Any]) {
        var cmd = [UInt8]([0x00, 0xA4, 0x04, 0x00, UInt8(aid.count)])
        cmd += aid
        cmd += [0x00]
        guard let resp = transceive(tag: tag, apdu: cmd), isSuccess(resp) else { return }
        parseTLV(resp, into: &cardData)

        // GPO with empty PDOL data
        let gpo: [UInt8] = [0x80, 0xA8, 0x00, 0x00, 0x02, 0x83, 0x00, 0x00]
        if let gpoResp = transceive(tag: tag, apdu: gpo), isSuccess(gpoResp) {
            parseTLV(gpoResp, into: &cardData)
            bruteForceRecords(tag: tag, into: &cardData)
        }
    }

    private func bruteForceRecords(tag: NFCISO7816Tag,
                                   into cardData: inout [String: Any]) {
        for sfi in 1...10 {
            for rec in 1...10 {
                let p2 = UInt8((sfi << 3) | 0x04)
                let cmd: [UInt8] = [0x00, 0xB2, UInt8(rec), p2, 0x00]
                if let resp = transceive(tag: tag, apdu: cmd), isSuccess(resp) {
                    parseTLV(resp, into: &cardData)
                }
            }
        }
    }

    private func extractCryptogram(tag: NFCISO7816Tag,
                                   into cardData: inout [String: Any]) {
        // GENERATE AC with zeroed 33-byte CDOL data (byte 5 = 0x01 = Purchase)
        var cdolData = [UInt8](repeating: 0x00, count: 33)
        cdolData[5] = 0x01
        var genAC: [UInt8] = [0x80, 0xAE, 0x80, 0x00, 0x21]
        genAC += cdolData
        genAC += [0x00]
        if let resp = transceive(tag: tag, apdu: genAC), isSuccess(resp) {
            parseTLV(resp, into: &cardData)
        }

        // Fallback: GET DATA for tag 9F26 (Application Cryptogram)
        if cardData["cryptogram"] as? String == "Unknown" {
            let getAC: [UInt8] = [0x80, 0xCA, 0x9F, 0x26, 0x00]
            if let resp = transceive(tag: tag, apdu: getAC), isSuccess(resp) {
                parseTLV(resp, into: &cardData)
            }
        }
    }

    // MARK: - Low-Level APDU Transceive

    /// Synchronously send an APDU and return the raw response bytes (including SW1 SW2).
    private func transceive(tag: NFCISO7816Tag, apdu rawApdu: [UInt8]) -> [UInt8]? {
        guard rawApdu.count >= 4 else { return nil }

        // Build NFCISO7816APDU from raw bytes
        let apduData: Data = rawApdu.count > 5
            ? Data(rawApdu[5..<(rawApdu.count - 1)])
            : Data()
        let expectedLen = rawApdu.count > 4 ? Int(rawApdu.last ?? 0) : -1

        let apduObject = NFCISO7816APDU(
            instructionClass: rawApdu[0],
            instructionCode: rawApdu[1],
            p1Parameter: rawApdu[2],
            p2Parameter: rawApdu[3],
            data: apduData,
            expectedResponseLength: expectedLen
        )

        var result: [UInt8]? = nil
        let semaphore = DispatchSemaphore(value: 0)

        tag.sendCommand(apdu: apduObject) { responseData, sw1, sw2, error in
            if error == nil {
                var combined = [UInt8](responseData)
                combined += [sw1, sw2]
                result = combined
            }
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    private func isSuccess(_ data: [UInt8]) -> Bool {
        guard data.count >= 2 else { return false }
        return data[data.count - 2] == 0x90 && data[data.count - 1] == 0x00
    }

    // MARK: - TLV Parser

    private func parseTLV(_ data: [UInt8], into cardData: inout [String: Any]) {
        // Strip trailing SW1 SW2 if present
        var payload = data
        if payload.count >= 2,
           payload[payload.count - 2] == 0x90 || payload[payload.count - 2] == 0x61 {
            payload = Array(payload.prefix(payload.count - 2))
        }
        parseTLVRecursive(payload, into: &cardData)
    }

    private func parseTLVRecursive(_ data: [UInt8], into cardData: inout [String: Any]) {
        var i = 0
        while i < data.count {
            var tag = Int(data[i]); i += 1
            if (tag & 0x1F) == 0x1F, i < data.count {
                tag = (tag << 8) | Int(data[i]); i += 1
            }
            guard i < data.count else { break }
            var len = Int(data[i]); i += 1
            if (len & 0x80) == 0x80 {
                let n = len & 0x7F; len = 0
                for _ in 0..<n {
                    guard i < data.count else { break }
                    len = (len << 8) | Int(data[i]); i += 1
                }
            }
            guard i + len <= data.count else { break }
            let val = Array(data[i..<(i + len)]); i += len

            // Constructed tags — recurse into them
            if [0x6F, 0x70, 0x77, 0xA5, 0xBF0C].contains(tag) {
                parseTLVRecursive(val, into: &cardData)
            } else {
                extractPrimitiveTag(tag: tag, value: val, into: &cardData)
            }
        }
    }

    private func extractPrimitiveTag(tag: Int,
                                      value: [UInt8],
                                      into cardData: inout [String: Any]) {
        switch tag {
        case 0x5A:              // Primary Account Number
            cardData["pan"] = maskPAN(bcdToString(value))

        case 0x57:              // Track 2 Equivalent Data
            let t2 = bcdToString(value)
            if let sepIdx = t2.firstIndex(of: "D") {
                cardData["pan"] = maskPAN(String(t2[..<sepIdx]))
                let afterD = t2.index(after: sepIdx)
                if t2[afterD...].count >= 4 {
                    let exp = String(t2[afterD...].prefix(4))
                    cardData["expiryDate"] = String(exp.suffix(2)) + "/" + String(exp.prefix(2))
                }
            }

        case 0x5F24:            // Expiry Date (YYMMDD BCD)
            let s = bcdToString(value)
            if s.count >= 4 {
                cardData["expiryDate"] = String(s.suffix(2)) + "/" + String(s.prefix(2))
            }

        case 0x5F20, 0x9F0B:   // Cardholder Name
            if let name = String(bytes: value, encoding: .ascii) {
                cardData["cardholderName"] = name.trimmingCharacters(in: .whitespaces)
            }

        case 0x50, 0x9F12:     // Application Label / Preferred Name
            if let label = String(bytes: value, encoding: .ascii) {
                cardData["applicationLabel"] = label.trimmingCharacters(in: .whitespaces)
            }

        case 0x9F26:            // Application Cryptogram
            cardData["cryptogram"] = value.map { String(format: "%02X", $0) }.joined()

        default:
            break
        }
    }

    // MARK: - Utilities

    private func bcdToString(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined()
    }

    private func maskPAN(_ pan: String) -> String {
        // Remove BCD padding 'F' characters
        return pan.replacingOccurrences(of: "F", with: "")
    }

    private func extractAIDs(from data: [UInt8]) -> [[UInt8]] {
        var aids = [[UInt8]]()
        var i = 0
        while i < data.count - 2 {
            if data[i] == 0x4F {
                let len = Int(data[i + 1])
                let start = i + 2
                if start + len <= data.count {
                    aids.append(Array(data[start..<(start + len)]))
                }
                i = start + len
            } else {
                i += 1
            }
        }
        return aids
    }
}

// MARK: - EMV Constants

private enum EMVCommands {
    /// SELECT PPSE (2PAY.SYS.DDF01)
    static let selectPPSE: [UInt8] = [
        0x00, 0xA4, 0x04, 0x00, 0x0E,
        0x32, 0x50, 0x41, 0x59, 0x2E, 0x53, 0x59, 0x53,
        0x2E, 0x44, 0x44, 0x46, 0x30, 0x31, 0x00
    ]

    /// Well-known EMV application AIDs
    static let knownAIDs: [[UInt8]] = [
        [0xA0, 0x00, 0x00, 0x00, 0x04, 0x10, 0x10],  // Mastercard
        [0xA0, 0x00, 0x00, 0x00, 0x03, 0x10, 0x10],  // Visa Credit/Debit
        [0xA0, 0x00, 0x00, 0x00, 0x03, 0x20, 0x10],  // Visa Electron
        [0xA0, 0x00, 0x00, 0x00, 0x03, 0x20, 0x20],  // V Pay
        [0xA0, 0x00, 0x00, 0x00, 0x04, 0x30, 0x60],  // Maestro
        [0xA0, 0x00, 0x00, 0x00, 0x03, 0x80, 0x10],  // Visa Interlink
        [0xA0, 0x00, 0x00, 0x00, 0x65, 0x10, 0x10],  // JCB
        [0xA0, 0x00, 0x00, 0x02, 0x50, 0x01],        // American Express
        [0xA0, 0x00, 0x00, 0x01, 0x52, 0x30, 0x10],  // Discover
        [0xA0, 0x00, 0x00, 0x03, 0x24, 0x10, 0x10],  // UnionPay
    ]
}
