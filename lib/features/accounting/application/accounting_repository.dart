import '../application/accounting_models.dart';

abstract class AccountingRepository {
  Future<List<Account>> getChartOfAccounts({required String companyId});

  Future<List<JournalEntry>> listJournalEntries({required String companyId});
}
