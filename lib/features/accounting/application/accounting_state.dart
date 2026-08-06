import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../company/application/company_state.dart';
import '../data/supabase_accounting_repository.dart';
import 'accounting_models.dart';

final chartOfAccountsProvider = FutureProvider.autoDispose<List<Account>>((
  ref,
) async {
  final companyId = ref.watch(selectedCompanyIdProvider);
  if (companyId == null || companyId.trim().isEmpty) return const [];

  return ref
      .watch(accountingRepositoryProvider)
      .getChartOfAccounts(companyId: companyId);
}, retry: (_, _) => null);

final journalListControllerProvider = FutureProvider.autoDispose<List<JournalEntry>>((
  ref,
) async {
  final companyId = ref.watch(selectedCompanyIdProvider);
  if (companyId == null || companyId.trim().isEmpty) return const [];

  return ref
      .watch(accountingRepositoryProvider)
      .listJournalEntries(companyId: companyId);
}, retry: (_, _) => null);
