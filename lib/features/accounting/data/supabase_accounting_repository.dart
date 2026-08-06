import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/accounting_models.dart';
import '../application/accounting_repository.dart';
import 'accounting_service.dart';

final accountingRepositoryProvider = Provider<AccountingRepository>((ref) {
  return SupabaseAccountingRepository(ref.watch(accountingServiceProvider));
});

final class SupabaseAccountingRepository implements AccountingRepository {
  const SupabaseAccountingRepository(this._service);

  final AccountingService _service;

  @override
  Future<List<Account>> getChartOfAccounts({required String companyId}) async {
    final rows = await _service.fetchChartOfAccounts(companyId: companyId);
    return rows.map((r) => _mapAccount(r)).toList();
  }

  @override
  Future<List<JournalEntry>> listJournalEntries({
    required String companyId,
  }) async {
    final rows = await _service.fetchJournalEntries(companyId: companyId);
    return rows.map((r) => _mapJournalEntry(r, companyId)).toList();
  }

  Account _mapAccount(Map<String, dynamic> row) {
    return Account(
      id: row['id'] as String,
      companyId: row['company_id'] as String,
      code: row['code'] as String,
      name: row['name'] as String,
      type: row['type'] as String,
      isActive: row['is_active'] as bool? ?? true,
    );
  }

  JournalEntry _mapJournalEntry(Map<String, dynamic> row, String companyId) {
    final linesRaw = row['journal_lines'] as List? ?? [];
    final lines = linesRaw
        .whereType<Map>()
        .map((r) => _mapJournalLine(Map<String, dynamic>.from(r), companyId))
        .toList();

    return JournalEntry(
      id: row['id'] as String,
      companyId: row['company_id'] as String? ?? companyId,
      entryNumber: row['entry_number'] as String,
      entryDate: DateTime.parse(row['entry_date'] as String),
      sourceType: row['source_type'] as String? ?? 'payment',
      sourceId: row['source_id'] as String?,
      narration: row['narration'] as String?,
      status: row['status'] as String? ?? 'posted',
      lines: lines,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  JournalLine _mapJournalLine(Map<String, dynamic> row, String companyId) {
    return JournalLine(
      id: row['id'] as String? ?? '',
      companyId: row['company_id'] as String? ?? companyId,
      journalId: row['journal_id'] as String? ?? '',
      accountId: row['account_id'] as String?,
      accountCode: row['account_code'] as String? ?? '',
      accountName: row['account_name'] as String? ?? '',
      debit: (row['debit'] as num?)?.toDouble() ?? 0.0,
      credit: (row['credit'] as num?)?.toDouble() ?? 0.0,
      description: row['description'] as String?,
    );
  }
}
