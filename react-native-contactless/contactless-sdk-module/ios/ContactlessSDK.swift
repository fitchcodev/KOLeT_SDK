import ExpoModulesCore
import CoreNFC

public class ContactlessSDK: Module {
  public func definition() -> ModuleDefinition {
    Name("ContactlessSDK")

    AsyncFunction("initialize") { (_ apiKey: String, _ environment: String) -> Bool in
      return true
    }

    AsyncFunction("isNfcAvailable") { () -> Bool in
      return NFCTagReaderSession.readingAvailable
    }

    AsyncFunction("startPayment") { (request: [String: Any]) -> [String: Any] in
      let transactionId = "TXN_\(Int(Date().timeIntervalSince1970))"
      return [
        "success": true,
        "transactionId": transactionId,
        "authCode": "123456",
        "maskedPan": "4111********1111"
      ]
    }
  }
}
