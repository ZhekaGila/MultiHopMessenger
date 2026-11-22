import 'dart:convert';

import 'package:cryptography/cryptography.dart';

class EncryptionService {
  EncryptionService._();

  static final EncryptionService instance = EncryptionService._();

  final AesGcm algorithm = AesGcm.with256bits();

  final SecretKey demoKey = SecretKey(
    List<int>.generate(32, (index) => index + 1),
  );

  Future<Map<String, String>> encrypt(String plaintext, SecretKey key) async {
    final nonce = algorithm.newNonce();

    final secretBox = await algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );

    return {
      'ciphertext': base64Encode(secretBox.cipherText),
      'nonce': base64Encode(secretBox.nonce),
      'mac': base64Encode(secretBox.mac.bytes),
    };
  }

  Future<String> decrypt(Map<String, String> encrypted, SecretKey key) async {
    final secretBox = SecretBox(
      base64Decode(encrypted['ciphertext']!),
      nonce: base64Decode(encrypted['nonce']!),
      mac: Mac(base64Decode(encrypted['mac']!)),
    );

    final plaintext = await algorithm.decrypt(secretBox, secretKey: key);

    return utf8.decode(plaintext);
  }
}
