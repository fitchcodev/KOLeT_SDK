import 'dart:async';
import 'dart:typed_data';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/platform_tags.dart';
import '../models/card_data.dart';

class EmvCardReader {
  /// Start scanning for an EMV card.
  /// [onStatusUpdate] will be called to provide progress messages.
  Future<CardData?> readCard({Function(String)? onStatusUpdate}) async {
    bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      onStatusUpdate?.call('NFC is not available');
      return null;
    }

    onStatusUpdate?.call('Hold your card near the back of the phone');

    final completer = Completer<CardData?>();

    NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443},
      onDiscovered: (NfcTag tag) async {
        try {
          final isoDep = IsoDep.from(tag);
          final iso7816 = Iso7816.from(tag);
          
          if (isoDep == null && iso7816 == null) {
            onStatusUpdate?.call('Not an EMV card');
            NfcManager.instance.stopSession();
            if (!completer.isCompleted) completer.complete(null);
            return;
          }

          onStatusUpdate?.call('Reading... KEEP CARD STILL!');

          Map<String, dynamic> cardDataMap = {
            'pan': 'Unknown',
            'expiryDate': 'Unknown',
            'cardholderName': 'Unknown',
            'applicationLabel': 'Unknown',
            'cryptogram': 'Unknown',
            'cdol1_bytes': <int>[],
          };

          try {
            print('\\n🔍 === READING CARD ===\\n');

            // Method 1: PPSE
            try {
              await _tryPPSEMethod(tag, cardDataMap);
            } catch (e) {
              if (_isTagLost(e)) rethrow;
              print('⚠️ PPSE failed: $e');
            }

            // Method 2: Known AIDs
            if (cardDataMap['pan'] == 'Unknown') {
              try {
                await _tryKnownAIDs(tag, cardDataMap);
              } catch (e) {
                if (_isTagLost(e)) rethrow;
              }
            }

            // Method 3: Brute Force
            if (cardDataMap['pan'] == 'Unknown') {
              try {
                await _bruteForceReadRecords(tag, cardDataMap);
              } catch (e) {
                if (_isTagLost(e)) rethrow;
              }
            }

            // Method 4: Cryptogram Extraction
            try {
              await _tryCryptogramExtraction(tag, cardDataMap);
            } catch (e) {
              if (_isTagLost(e)) rethrow;
              print('Cryptogram failed: $e');
            }

            onStatusUpdate?.call('Scan Complete');
            NfcManager.instance.stopSession();
            if (!completer.isCompleted) {
              completer.complete(CardData.fromMap(cardDataMap));
            }
          } catch (e) {
            if (_isTagLost(e)) {
              onStatusUpdate?.call('Connection Lost!\\nPlease hold card TIGHTLY against phone.');
            } else {
              onStatusUpdate?.call('Error: $e');
            }
            NfcManager.instance.stopSession();
            if (!completer.isCompleted) completer.complete(null);
          }
        } catch (e) {
          onStatusUpdate?.call('Session Error: $e');
          NfcManager.instance.stopSession();
          if (!completer.isCompleted) completer.complete(null);
        }
      },
    );

    return completer.future;
  }

  bool _isTagLost(dynamic e) {
    return e.toString().contains('TagLostException') || e.toString().contains('Tag connection lost');
  }

  Future<Uint8List> _transceive(NfcTag tag, Uint8List data) async {
    final isoDep = IsoDep.from(tag);
    if (isoDep != null) {
      return await isoDep.transceive(data: data);
    }
    
    final iso7816 = Iso7816.from(tag);
    if (iso7816 != null) {
      final response = await iso7816.sendCommandRaw(data);
      final result = BytesBuilder();
      result.add(response.payload);
      result.addByte(response.statusWord1);
      result.addByte(response.statusWord2);
      return result.toBytes();
    }
    
    throw Exception('Tag does not support IsoDep or Iso7816');
  }

  Future<void> _tryPPSEMethod(NfcTag tag, Map<String, dynamic> cardDataMap) async {
    Uint8List ppseCmd = Uint8List.fromList([
      0x00, 0xA4, 0x04, 0x00, 0x0E, 0x32, 0x50, 0x41, 0x59, 0x2E, 0x53, 0x59, 0x53, 0x2E, 0x44, 0x44, 0x46, 0x30, 0x31, 0x00,
    ]);
    Uint8List ppseResp = await _transceive(tag, ppseCmd);
    if (_isSuccess(ppseResp)) {
      List<String> aids = _extractAIDs(ppseResp);
      for (String aid in aids) {
        await _selectAndReadAID(tag, aid, cardDataMap);
        if (cardDataMap['pan'] != 'Unknown') break;
      }
    }
  }

  Future<void> _tryKnownAIDs(NfcTag tag, Map<String, dynamic> cardDataMap) async {
    List<String> knownAIDs = [
      'A0000000041010', 'A0000000031010', 'A0000000032010', 'A0000000032020',
      'A0000000043060', 'A0000000038010', 'A0000000651010', 'A00000002501',
      'A0000001523010', 'A0000003241010',
    ];
    for (String aid in knownAIDs) {
      if (cardDataMap['pan'] != 'Unknown') break;
      await _selectAndReadAID(tag, aid, cardDataMap);
    }
  }

  Future<void> _selectAndReadAID(NfcTag tag, String aidHex, Map<String, dynamic> cardDataMap) async {
    List<int> aid = _hexToBytes(aidHex);
    Uint8List selectCmd = Uint8List.fromList([0x00, 0xA4, 0x04, 0x00, aid.length, ...aid, 0x00]);
    Uint8List resp = await _transceive(tag, selectCmd);
    if (_isSuccess(resp)) {
      _parseEMVData(resp, cardDataMap);
      Uint8List gpoCmd = Uint8List.fromList([0x80, 0xA8, 0x00, 0x00, 0x02, 0x83, 0x00, 0x00]);
      Uint8List gpoResp = await _transceive(tag, gpoCmd);
      if (_isSuccess(gpoResp)) {
        _parseEMVData(gpoResp, cardDataMap);
        await _bruteForceReadRecords(tag, cardDataMap);
      }
    }
  }

  Future<void> _bruteForceReadRecords(NfcTag tag, Map<String, dynamic> cardDataMap) async {
    for (int sfi = 1; sfi <= 10; sfi++) {
      for (int rec = 1; rec <= 10; rec++) {
        try {
          Uint8List cmd = Uint8List.fromList([0x00, 0xB2, rec, (sfi << 3) | 0x04, 0x00]);
          Uint8List resp = await _transceive(tag, cmd);
          if (_isSuccess(resp)) _parseEMVData(resp, cardDataMap);
        } catch (_) {}
      }
    }
  }

  Future<void> _tryCryptogramExtraction(NfcTag tag, Map<String, dynamic> cardDataMap) async {
    await _generateAC(tag, cardDataMap);
    if (cardDataMap['cryptogram'] == 'Unknown') {
      await _getData(tag, 0x9F26, cardDataMap);
    }
  }

  Future<void> _generateAC(NfcTag tag, Map<String, dynamic> cardDataMap) async {
    int requiredLen = 33;
    List<int>? cdol1Raw = cardDataMap['cdol1_bytes'] as List<int>?;

    if (cdol1Raw != null && cdol1Raw.isNotEmpty) {
      requiredLen = _calculateCDOL1Length(cdol1Raw);
    }

    List<int> cdolData = List.filled(requiredLen, 0x00);
    if (requiredLen >= 6) cdolData[5] = 0x01;
    if (requiredLen == 33) {
      cdolData[20] = 0x05;
      cdolData[21] = 0x66;
      cdolData[22] = 0x25;
      cdolData[23] = 0x01;
      cdolData[24] = 0x01;
    }

    Uint8List genAcCmd = Uint8List.fromList([0x80, 0xAE, 0x80, 0x00, cdolData.length, ...cdolData, 0x00]);
    Uint8List resp = await _transceive(tag, genAcCmd);
    if (_isSuccess(resp)) _parseEMVData(resp, cardDataMap);
  }

  int _calculateCDOL1Length(List<int> cdol1) {
    int total = 0;
    int i = 0;
    while (i < cdol1.length) {
      int tag = cdol1[i++];
      if ((tag & 0x1F) == 0x1F) {
        if (i < cdol1.length) i++;
      }
      if (i >= cdol1.length) break;
      total += cdol1[i++];
    }
    return total;
  }

  Future<void> _getData(NfcTag tag, int tagCode, Map<String, dynamic> cardDataMap) async {
    int p1 = (tagCode >> 8) & 0xFF;
    int p2 = tagCode & 0xFF;
    Uint8List cmd = Uint8List.fromList([0x80, 0xCA, p1, p2, 0x00]);
    Uint8List resp = await _transceive(tag, cmd);
    if (_isSuccess(resp)) _parseEMVData(resp, cardDataMap);
  }

  void _parseEMVData(Uint8List data, Map<String, dynamic> cardDataMap) {
    if (data.length < 2) return;
    Uint8List payload = data;
    if (data.length >= 2 && (data[data.length - 2] == 0x90 || data[data.length - 2] == 0x61)) {
      payload = data.sublist(0, data.length - 2);
    }
    _parseTlvRecursive(payload, cardDataMap);
  }

  void _parseTlvRecursive(Uint8List data, Map<String, dynamic> cardDataMap) {
    int i = 0;
    while (i < data.length) {
      int tag = data[i++];
      if ((tag & 0x1F) == 0x1F) {
        if (i < data.length) tag = (tag << 8) | data[i++];
      }
      if (i >= data.length) break;
      int len = data[i++];
      if ((len & 0x80) == 0x80) {
        int n = len & 0x7F;
        len = 0;
        for (int k = 0; k < n && i < data.length; k++) len = (len << 8) | data[i++];
      }
      if (i + len > data.length) break;
      Uint8List val = data.sublist(i, i + len);
      i += len;
      if (tag == 0x6F || tag == 0x70 || tag == 0x77 || tag == 0xA5 || tag == 0xBF0C) {
        _parseTlvRecursive(val, cardDataMap);
      } else {
        _extractTag(tag, val, cardDataMap);
      }
    }
  }

  void _extractTag(int tag, Uint8List val, Map<String, dynamic> cardDataMap) {
    switch (tag) {
      case 0x5A:
        cardDataMap['pan'] = _maskPAN(_bcdToString(val));
        break;
      case 0x5F24:
        String s = _bcdToString(val);
        if (s.length >= 4) cardDataMap['expiryDate'] = s.substring(2, 4) + '/' + s.substring(0, 2);
        break;
      case 0x5F20:
      case 0x9F0B:
        cardDataMap['cardholderName'] = String.fromCharCodes(val).replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
        break;
      case 0x50:
      case 0x9F12:
        cardDataMap['applicationLabel'] = String.fromCharCodes(val).replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
        break;
      case 0x57:
        String t2 = _bcdToString(val);
        int sep = t2.indexOf('D');
        if (sep > 0) {
          cardDataMap['pan'] = _maskPAN(t2.substring(0, sep));
          if (sep + 5 <= t2.length) {
            String exp = t2.substring(sep + 1, sep + 5);
            cardDataMap['expiryDate'] = exp.substring(2, 4) + '/' + exp.substring(0, 2);
          }
        }
        break;
      case 0x9F26:
        cardDataMap['cryptogram'] = _toHex(val).replaceAll(' ', '');
        break;
      case 0x8C:
        cardDataMap['cdol1_bytes'] = val.toList();
        break;
    }
  }

  bool _isSuccess(Uint8List d) => d.length >= 2 && d[d.length - 2] == 0x90 && d[d.length - 1] == 0x00;
  String _toHex(Uint8List b) => b.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ').toUpperCase();
  List<int> _hexToBytes(String s) {
    s = s.replaceAll(' ', '');
    return List.generate(s.length ~/ 2, (i) => int.parse(s.substring(i * 2, i * 2 + 2), radix: 16));
  }

  String _bcdToString(Uint8List b) {
    StringBuffer sb = StringBuffer();
    for (int x in b) {
      sb.write(((x >> 4) & 0xF).toString());
      sb.write((x & 0xF).toString());
    }
    return sb.toString();
  }

  String _maskPAN(String p) => p.replaceAll('F', '');
  List<String> _extractAIDs(Uint8List d) {
    List<String> a = [];
    for (int i = 0; i < d.length - 2; i++) {
      if (d[i] == 0x4F) {
        int l = d[i + 1];
        if (i + 2 + l <= d.length) a.add(_toHex(d.sublist(i + 2, i + 2 + l)).replaceAll(' ', ''));
      }
    }
    return a;
  }
}
