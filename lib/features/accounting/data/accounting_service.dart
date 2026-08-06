import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_providers.dart';
import '../application/accounting_models.dart';

final accountingServiceProvider = Provider<AccountingService>((ref) {
  return AccountingService(ref.watch(supabaseServiceProvider).client);
});

final class AccountingService {
  const AccountingService(this._client);

  final SupabaseClient _client;

  Future<List<Map<String, dynamic>>> fetchChartOfAccounts({
    required String companyId,
  }) async {
    final rows = await _client
        .from('chart_of_accounts')
        .select('*')
        .eq('company_id', companyId)
        .order('code');

    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> fetchJournalEntries({
    required String companyId,
  }) async {
    final rows = await _client
        .from('journal_entries')
        .select('''
          *,
          journal_lines(*)
        ''')
        .eq('company_id', companyId)
        .order('entry_date', ascending: false);

    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> fetchAccountingPeriods({
    required String companyId,
  }) async {
    final rows = await _client
        .from('accounting_periods')
        .select('*')
        .eq('company_id', companyId)
        .order('start_date', ascending: false);

    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> postManualJournal({
    required String companyId,
    required DateTime entryDate,
    required String narration,
    required List<ManualJournalLineInput> lines,
  }) async {
    final response = await _client.rpc(
      'post_manual_journal',
      params: {
        'p_company_id': companyId,
        'p_entry_date': entryDate.toIso8601String().split('T').first,
        'p_narration': narration,
        'p_lines': lines.map((l) => l.toJson()).toList(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> reverseJournalEntry({
    required String companyId,
    required String journalId,
    DateTime? reversalDate,
    String? reason,
  }) async {
    final response = await _client.rpc(
      'reverse_journal_entry',
      params: {
        'p_company_id': companyId,
        'p_journal_id': journalId,
        'p_reversal_date': (reversalDate ?? DateTime.now())
            .toIso8601String()
            .split('T')
            .first,
        'p_reason': reason,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<List<Map<String, dynamic>>> fetchTrialBalance({
    required String companyId,
    DateTime? asOfDate,
  }) async {
    final response = await _client.rpc(
      'get_trial_balance',
      params: {
        'p_company_id': companyId,
        'p_as_of_date': (asOfDate ?? DateTime.now())
            .toIso8601String()
            .split('T')
            .first,
      },
    );
    return List<Map<String, dynamic>>.from(response as List);
  }

  Future<List<Map<String, dynamic>>> fetchProfitAndLoss({
    required String companyId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final response = await _client.rpc(
      'get_profit_and_loss',
      params: {
        'p_company_id': companyId,
        'p_start_date': startDate.toIso8601String().split('T').first,
        'p_end_date': endDate.toIso8601String().split('T').first,
      },
    );
    return List<Map<String, dynamic>>.from(response as List);
  }

  Future<List<Map<String, dynamic>>> fetchBalanceSheet({
    required String companyId,
    DateTime? asOfDate,
  }) async {
    final response = await _client.rpc(
      'get_balance_sheet',
      params: {
        'p_company_id': companyId,
        'p_as_of_date': (asOfDate ?? DateTime.now())
            .toIso8601String()
            .split('T')
            .first,
      },
    );
    return List<Map<String, dynamic>>.from(response as List);
  }
}
