import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_os/features/subscription/domain/subscription_guard.dart';

void main() {
  group('SubscriptionGuard Fail-Closed Entitlement Tests', () {
    final referenceDate = DateTime(2026, 8, 1, 12, 0);

    test('evaluateEntitlement grants access for active subscriptions', () {
      final isEntitled = SubscriptionGuard.evaluateEntitlement(
        status: 'active',
        now: referenceDate,
      );

      expect(isEntitled, isTrue);
    });

    test('evaluateEntitlement grants access for trialing status before trial expiration', () {
      final trialEnd = DateTime(2026, 8, 10, 23, 59);
      final isEntitled = SubscriptionGuard.evaluateEntitlement(
        status: 'trialing',
        trialEndsAt: trialEnd,
        now: referenceDate,
      );

      expect(isEntitled, isTrue);
    });

    test('evaluateEntitlement denies access when trial period has expired', () {
      final expiredTrialEnd = DateTime(2026, 7, 25, 23, 59);
      final isEntitled = SubscriptionGuard.evaluateEntitlement(
        status: 'trialing',
        trialEndsAt: expiredTrialEnd,
        now: referenceDate,
      );

      expect(isEntitled, isFalse);
    });

    test('evaluateEntitlement fails closed for past_due, canceled, expired, or missing status', () {
      const invalidStatuses = ['past_due', 'canceled', 'expired', 'unknown', null];

      for (final status in invalidStatuses) {
        final isEntitled = SubscriptionGuard.evaluateEntitlement(
          status: status,
          now: referenceDate,
        );

        expect(isEntitled, isFalse, reason: 'Status "$status" must fail closed');
      }
    });
  });
}
