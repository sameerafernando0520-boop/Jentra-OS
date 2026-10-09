import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_employee/src/employee_configuration.dart';

String legacyKey(String role) =>
    '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.${base64Url.encode(utf8.encode(jsonEncode({'role': role})))}.signature';

void main() {
  test('public client configuration accepts HTTPS and publishable or legacy anon keys', () {
    expect(
      const EmployeeConfiguration(
        url: 'https://company.supabase.co',
        publishableKey: 'sb_publishable_development_key',
      ).isValid,
      isTrue,
    );
    expect(
      EmployeeConfiguration(
        url: 'https://company.supabase.co/',
        publishableKey: legacyKey('anon'),
      ).isValid,
      isTrue,
    );
  });
  test('server keys cannot enter the employee client', () {
    for (final key in [
      'sb_secret_server_key',
      legacyKey('service_role'),
      legacyKey('authenticated'),
      'malformed',
    ]) {
      expect(
        EmployeeConfiguration(
          url: 'https://company.supabase.co',
          publishableKey: key,
        ).isValid,
        isFalse,
      );
    }
  });
  test('credentials and tokens cannot be hidden in a configuration URL', () {
    for (final url in [
      'http://company.supabase.co',
      'https://user:password@company.supabase.co',
      'https://company.supabase.co?token=private',
      'https://company.supabase.co#private',
      'https://company.supabase.co/path',
      '',
    ]) {
      expect(
        EmployeeConfiguration(
          url: url,
          publishableKey: 'sb_publishable_development_key',
        ).isValid,
        isFalse,
      );
    }
  });
}
