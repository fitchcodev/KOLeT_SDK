class NfcManager {
  static final NfcManager _instance = NfcManager._internal();
  factory NfcManager() => _instance;
  NfcManager._internal();

  bool _isSessionActive = false;

  Future<void> startSession() async {
    if (_isSessionActive) return;
    _isSessionActive = true;
    // Logic to bridge with native NFC
    print('NFC Session Started');
  }

  Future<void> stopSession() async {
    _isSessionActive = false;
    print('NFC Session Stopped');
  }

  Future<String> sendApdu(String apdu) async {
    // Logic to send APDU command to the card
    return '9000'; // Success status word
  }
}
