import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_os/features/accounting/application/accounting_state.dart';
import 'package:jentra_os/features/accounting/data/supabase_accounting_repository.dart';
import 'package:jentra_os/features/company/application/company_state.dart';

import '../fake_accounting_repository.dart';

void main() {
  group('AccountingState & Double-Entry Ledger Verification', () {
    test('missing company ID returns empty accounts and journal entries', () async {
      final fakeRepo = FakeAccountingRepository();
      final container = ProviderContainer(
        overrides: [
          accountingRepositoryProvider.overrideWithValue(fakeRepo),
          selectedCompanyIdProvider.overrideWith((ref) => null),
        ],
      );
      addTearDown(container.dispose);

      final accounts = await container.read(chartOfAccountsProvider.future);
      expect(accounts, isEmpty);

      final journals = await container.read(journalListControllerProvider.future);
      expect(journals, isEmpty);
    });

    test('lists chart of accounts and verifies balanced journal entry debits and credits', () async {
      final fakeRepo = FakeAccountingRepository();
      final container = ProviderContainer(
        overrides: [
          accountingRepositoryProvider.overrideWithValue(fakeRepo),
          selectedCompanyIdProvider.overrideWith((ref) => 'comp-1'),
        ],
      );
      addTearDown(container.dispose);

      final accounts = await container.read(chartOfAccountsProvider.future);
      expect(accounts, hasLength(2));
      expect(accounts.first.code, equals('1010'));

      final journals = await container.read(journalListControllerProvider.future);
      expect(journals, hasLength(1));

      final entry = journals.first;
      expect(entry.entryNumber, equals('JRN-1001'));
      expect(entry.totalDebit, equals(100.00));
      expect(entry.totalCredit, equals(100.00));
      expect(entry.isBalanced, isTrue);
    });
  });
}
