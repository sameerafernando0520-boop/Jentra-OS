import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_providers.dart';

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
}
