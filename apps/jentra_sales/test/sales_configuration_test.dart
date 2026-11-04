import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_sales/src/sales_configuration.dart';

String key(String role, String ref) =>
    '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.${base64Url.encode(utf8.encode(jsonEncode({'role': role, 'ref': ref})))}.signature';
void main() {
  test(
    'Sales accepts the same project-bound public connection as Jentra OS',
    () {
      expect(
        SalesConfiguration(
          url: SalesConfiguration.defaultUrl,
          publishableKey: key('anon', 'xpdoufauvrbdmxgngetv'),
        ).isValid,
        isTrue,
      );
      expect(
        const SalesConfiguration(
          url: SalesConfiguration.defaultUrl,
          publishableKey: 'sb_publishable_synthetic_public_key',
        ).isValid,
        isTrue,
      );
    },
  );
  test('Sales refuses server credentials and keys from another project', () {
    for (final secret in [
      'sb_secret_synthetic_server_key',
      key('service_role', 'xpdoufauvrbdmxgngetv'),
      key('anon', 'anotherproject'),
      'malformed',
      '',
    ]) {
      expect(
        SalesConfiguration(
          url: SalesConfiguration.defaultUrl,
          publishableKey: secret,
        ).isValid,
        isFalse,
      );
    }
  });
  test(
    'bad deployment URLs fail closed before SDK or protected storage setup',
    () {
      for (final url in [
        'http://xpdoufauvrbdmxgngetv.supabase.co',
        'https://user:password@company.supabase.co',
        'https://company.supabase.co/path',
        'https://company.supabase.co?token=private',
        'https://company.supabase.co#private',
        'bad url',
      ]) {
        final config = SalesConfiguration(
          url: url,
          publishableKey: 'sb_publishable_synthetic_public_key',
        );
        expect(config.isValid, isFalse);
        expect(config.storageProjectUrl, SalesConfiguration.defaultUrl);
      }
    },
  );
}
