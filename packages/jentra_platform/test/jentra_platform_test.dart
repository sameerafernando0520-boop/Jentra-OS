import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_platform/jentra_platform.dart';

final class _MemoryKeyStore implements SecretKeyStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  test('runtime config is safe when backend is absent — AC-1', () {
    const config = RuntimeConfig(
      environment: 'development',
      supabaseUrl: '',
      supabasePublishableKey: '',
    );
    expect(config.isSupabaseConfigured, isFalse);
  });

  test(
    'draft payloads are authenticated and encrypted — FR-12 / AC-5',
    () async {
      final cipher = DraftCipher(keyStore: _MemoryKeyStore());
      const source = '{"supplier":"Ceylon Parts","amount":"2500.00"}';

      final encrypted = await cipher.encrypt(source);

      expect(
        utf8.decode(encrypted, allowMalformed: true),
        isNot(contains(source)),
      );
      expect(await cipher.decrypt(encrypted), source);
    },
  );

  test('tampered draft payload is rejected — NFR-4', () async {
    final cipher = DraftCipher(keyStore: _MemoryKeyStore());
    final encrypted = await cipher.encrypt('{"draft":true}');
    encrypted[encrypted.length - 1] ^= 1;

    expect(
      () => cipher.decrypt(encrypted),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });
}
