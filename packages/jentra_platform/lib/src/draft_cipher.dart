import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SecretKeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

final class WindowsCredentialKeyStore implements SecretKeyStore {
  WindowsCredentialKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

/// AES-256-GCM envelope encryption for cached drafts and reference payloads.
final class DraftCipher {
  DraftCipher({required this.keyStore});

  static const _credentialName = 'jentra.local-draft-key.v1';
  final SecretKeyStore keyStore;
  final AesGcm _algorithm = AesGcm.with256bits();

  Future<SecretKey> _key() async {
    final saved = await keyStore.read(_credentialName);
    if (saved != null) return SecretKey(base64Decode(saved));
    final generated = SecretKeyData.random(length: 32).bytes;
    await keyStore.write(_credentialName, base64Encode(generated));
    return SecretKey(generated);
  }

  Future<List<int>> encrypt(String plaintext) async {
    final nonce = _algorithm.newNonce();
    final box = await _algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: await _key(),
      nonce: nonce,
    );
    return <int>[nonce.length, ...nonce, ...box.mac.bytes, ...box.cipherText];
  }

  Future<String> decrypt(List<int> envelope) async {
    if (envelope.isEmpty) throw const FormatException('Empty encrypted draft.');
    final nonceLength = envelope.first;
    const macLength = 16;
    if (envelope.length <= 1 + nonceLength + macLength) {
      throw const FormatException('Invalid encrypted draft envelope.');
    }
    final nonceEnd = 1 + nonceLength;
    final macEnd = nonceEnd + macLength;
    final box = SecretBox(
      envelope.sublist(macEnd),
      nonce: envelope.sublist(1, nonceEnd),
      mac: Mac(envelope.sublist(nonceEnd, macEnd)),
    );
    final cleartext = await _algorithm.decrypt(box, secretKey: await _key());
    return utf8.decode(cleartext);
  }
}
