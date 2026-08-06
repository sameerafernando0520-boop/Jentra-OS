import 'package:flutter_test/flutter_test.dart';
import 'package:i_book/features/auth/application/auth_validators.dart';

void main() {
  group('AuthValidators.email', () {
    test('accepts a normal email address', () {
      expect(AuthValidators.email('owner@example.com'), isNull);
    });

    test('rejects malformed email addresses', () {
      expect(AuthValidators.email('owner@'), isNotNull);
      expect(AuthValidators.email(''), isNotNull);
    });
  });

  group('AuthValidators.registrationPassword', () {
    test('accepts a strong password', () {
      expect(AuthValidators.registrationPassword('Secure123'), isNull);
    });

    test('rejects weak passwords', () {
      expect(AuthValidators.registrationPassword('short'), isNotNull);
      expect(AuthValidators.registrationPassword('alllowercase1'), isNotNull);
    });
  });

  test('password confirmation must match', () {
    expect(
      AuthValidators.passwordConfirmation('Secure123', 'Secure123'),
      isNull,
    );
    expect(
      AuthValidators.passwordConfirmation('Different123', 'Secure123'),
      isNotNull,
    );
  });
}
