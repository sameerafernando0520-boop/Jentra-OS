import 'package:jentra_domain/jentra_domain.dart';
import 'package:test/test.dart';

void main() {
  group('Money — FR-15 / AC-8', () {
    test('keeps six-decimal precision without binary floating point', () {
      final value = Money.parse('123.456789', 'lkr');
      expect(value.toDecimalString(), '123.456789');
      expect(value.currencyCode, 'LKR');
    });

    test('rounds excess precision half away from zero', () {
      expect(Money.parse('1.0000005', 'LKR').toDecimalString(), '1.000001');
      expect(Money.parse('-1.0000005', 'LKR').toDecimalString(), '-1.000001');
    });

    test('rejects cross-currency arithmetic', () {
      expect(
        () => Money.parse('1', 'LKR') + Money.parse('1', 'USD'),
        throwsStateError,
      );
    });

    test('uses exact rational multiplication for tax', () {
      final value = Money.parse('199.99', 'LKR').multiplyRatio(18, 100);
      expect(value.toDecimalString(), '35.998200');
    });
  });

  group('DocumentLifecycle — FR-14 / AC-8 / EC-8', () {
    test('prevents direct posted mutation and deletion', () {
      expect(DocumentLifecycle.canEdit(DocumentStatus.posted), isFalse);
      expect(DocumentLifecycle.canDelete(DocumentStatus.posted), isFalse);
      expect(
        DocumentLifecycle.canTransition(
          DocumentStatus.posted,
          DocumentStatus.draft,
        ),
        isFalse,
      );
    });

    test('permits the canonical approval path', () {
      expect(
        DocumentLifecycle.canTransition(
          DocumentStatus.draft,
          DocumentStatus.submitted,
        ),
        isTrue,
      );
      expect(
        DocumentLifecycle.canTransition(
          DocumentStatus.approved,
          DocumentStatus.posted,
        ),
        isTrue,
      );
      expect(
        DocumentLifecycle.canTransition(
          DocumentStatus.posted,
          DocumentStatus.reversed,
        ),
        isTrue,
      );
      expect(
        DocumentLifecycle.requiresOnlineConfirmation(DocumentStatus.reversed),
        isTrue,
      );
    });
  });

  test('TenantContext exposes accounting and operational scope — FR-2', () {
    const tenantOnly = TenantContext(tenantId: 't', actorId: 'u');
    final branch = tenantOnly.copyWith(legalEntityId: 'l', branchId: 'b');
    expect(tenantOnly.hasAccountingScope, isFalse);
    expect(branch.hasOperationalScope, isTrue);
  });

  test('authoritative commands are blocked offline — FR-12 / AC-5', () {
    expect(
      OfflinePolicy.canRunAuthoritativeCommand(
        connectivity: ConnectivityState.offline,
        serverConfirmed: true,
      ),
      isFalse,
    );
  });
}
