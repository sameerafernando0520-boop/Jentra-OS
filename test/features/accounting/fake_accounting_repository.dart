import 'package:jentra_os/features/accounting/application/accounting_models.dart';
import 'package:jentra_os/features/accounting/application/accounting_repository.dart';

final class FakeAccountingRepository implements AccountingRepository {
  FakeAccountingRepository({
    List<Account>? accounts,
    List<JournalEntry>? journals,
  })  : accounts = accounts ??
            const [
              Account(
                id: 'acc-1',
                companyId: 'comp-1',
                code: '1010',
                name: 'Cash Account',
                type: 'asset',
              ),
              Account(
                id: 'acc-2',
                companyId: 'comp-1',
                code: '1100',
                name: 'Accounts Receivable',
                type: 'asset',
              ),
            ],
        journals = journals ??
            [
              JournalEntry(
                id: 'jrn-1',
                companyId: 'comp-1',
                entryNumber: 'JRN-1001',
                entryDate: DateTime.now(),
                sourceType: 'payment',
                sourceId: 'pmt-1',
                narration: 'Customer payment recorded against invoice INV-1001',
                status: 'posted',
                lines: const [
                  JournalLine(
                    id: 'line-1',
                    companyId: 'comp-1',
                    journalId: 'jrn-1',
                    accountCode: '1010',
                    accountName: 'Cash Account',
                    debit: 100.00,
                    credit: 0.00,
                  ),
                  JournalLine(
                    id: 'line-2',
                    companyId: 'comp-1',
                    journalId: 'jrn-1',
                    accountCode: '1100',
                    accountName: 'Accounts Receivable',
                    debit: 0.00,
                    credit: 100.00,
                  ),
                ],
                createdAt: DateTime.now(),
              ),
            ];

  final List<Account> accounts;
  final List<JournalEntry> journals;

  @override
  Future<List<Account>> getChartOfAccounts({required String companyId}) async {
    return accounts.where((acc) => acc.companyId == companyId).toList();
  }

  @override
  Future<List<JournalEntry>> listJournalEntries({
    required String companyId,
  }) async {
    return journals.where((jrn) => jrn.companyId == companyId).toList();
  }
}
