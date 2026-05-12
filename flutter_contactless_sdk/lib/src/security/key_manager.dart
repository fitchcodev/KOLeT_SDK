import 'dart:convert';
import 'package:crypto/crypto.dart';

class KeyManager {
  static final KeyManager _instance = KeyManager._internal();
  factory KeyManager() => _instance;
  KeyManager._internal();

  String _vaultKey = '';

  void setVaultKey(String key) {
    _vaultKey = key;
  }

  String signData(String data) {
    if (_vaultKey.isEmpty) throw Exception('Vault key not initialized');
    
    final keyBytes = utf8.encode(_vaultKey);
    final dataBytes = utf8.encode(data);
    
    final hmacSha256 = Hmac(sha256, keyBytes);
    final digest = hmacSha256.convert(dataBytes);
    
    return digest.toString();
  }

  bool verifySignature(String data, String signature) {
    return signData(data) == signature;
  }
}
