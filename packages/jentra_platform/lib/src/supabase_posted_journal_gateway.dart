import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_control_reconciliation_gateway.dart';

abstract interface class PostedJournalGateway {
  Future<Map<String, Object?>> page(
    TenantContext scope,
    String journalId, {
    int afterLine = 0,
  });
}

final class SupabasePostedJournalGateway implements PostedJournalGateway {
  SupabasePostedJournalGateway(SupabaseClient client)
    : transport = SupabaseControlReconciliationGateway(client);
  final SupabaseControlReconciliationGateway transport;

  void _scope(Map value, TenantContext scope, String branch) {
    if (value['tenant_id'] != scope.tenantId ||
        value['legal_entity_id'] != scope.legalEntityId ||
        value['branch_id'] != branch) {
      throw const FormatException('Journal scope mismatch.');
    }
  }

  void _identity(Map value, List<String> keys) {
    if (keys.any((k) => value[k] is! String || (value[k] as String).isEmpty)) {
      throw const FormatException('Missing posted journal identity.');
    }
  }

  void _dimension(Map row, String kind, TenantContext scope, String branch) {
    final id = row['${kind}_id'];
    final snapshot = row['dimension_snapshot'];
    final basis = snapshot is Map ? snapshot[kind] : null;
    if (id == null && basis == null) return;
    if (id is! String ||
        basis is! Map ||
        basis['id'] != id ||
        basis['kind'] != kind ||
        basis['tenant_id'] != scope.tenantId ||
        basis['legal_entity_id'] != scope.legalEntityId ||
        (basis['branch_id'] != null && basis['branch_id'] != branch) ||
        basis['version'] is! int ||
        (basis['version'] as int) < 1 ||
        basis['code'] is! String ||
        basis['name'] is! String) {
      throw const FormatException('Invalid frozen journal dimension.');
    }
  }

  @override
  Future<Map<String, Object?>> page(
    TenantContext scope,
    String journalId, {
    int afterLine = 0,
  }) async {
    if (journalId.isEmpty || afterLine < 0 || afterLine > 10000) {
      throw const FormatException('Invalid posted journal page.');
    }
    final r = await transport.call('posted_journal_evidence', scope, {
      'p_journal_id': journalId,
      'p_after_line': afterLine,
    });
    _scope(r, scope, scope.branchId!);
    if (r['journal_id'] != journalId ||
        r['after_line'] != afterLine ||
        r['journal'] is! Map ||
        r['items'] is! List ||
        (r['items'] as List).length > 50) {
      throw const FormatException('Invalid posted journal envelope.');
    }
    final j = r['journal'] as Map;
    _identity(j, [
      'id',
      'branch_id',
      'branch_name',
      'branch_status',
      'document_number',
      'posting_date',
      'fiscal_period_id',
      'currency_code',
      'base_currency_code',
      'source_type',
      'source_id',
      'command_id',
      'request_id',
      'correlation_id',
      'created_at',
      'created_by',
    ]);
    final branch = j['branch_id'] as String;
    _scope(j, scope, branch);
    if (j['id'] != journalId ||
        j['status'] != 'posted' ||
        j['label_basis'] != 'current_catalogue' ||
        j['stock_cost_access_required'] is! bool ||
        j['line_count'] is! int ||
        (j['line_count'] as int) < 2 ||
        (j['line_count'] as int) > 10000 ||
        j['rule_version'] is! int ||
        (j['rule_version'] as int) < 1 ||
        j['exchange_rate'] is! String ||
        !RegExp(r'^\d+(\.\d{1,10})?$').hasMatch(j['exchange_rate'] as String) ||
        ExactDecimal.parse(
              j['exchange_rate'] as String,
              scale: 10,
            ).compareTo(ExactDecimal.zero(scale: 10)) <=
            0) {
      throw const FormatException('Invalid immutable journal header.');
    }
    final debit = transport.decimal(j['base_debit']);
    final credit = transport.decimal(j['base_credit']);
    if (debit != credit ||
        debit.compareTo(ExactDecimal.zero(scale: 6)) <= 0 ||
        transport
                .decimal(j['transaction_debit'])
                .compareTo(ExactDecimal.zero(scale: 6)) <
            0 ||
        transport
                .decimal(j['transaction_credit'])
                .compareTo(ExactDecimal.zero(scale: 6)) <
            0) {
      throw const FormatException('Invalid whole-journal balance.');
    }
    var line = afterLine;
    var pageDebit = ExactDecimal.zero(scale: 6);
    var pageCredit = ExactDecimal.zero(scale: 6);
    final ids = <String>{};
    for (final value in r['items'] as List) {
      if (value is! Map) throw const FormatException('Invalid journal line.');
      _scope(value, scope, branch);
      _identity(value, [
        'id',
        'account_id',
        'account_code',
        'account_name',
        'account_status',
      ]);
      if (!ids.add(value['id'] as String) ||
          value['journal_entry_id'] != journalId ||
          value['line_number'] is! int ||
          (value['line_number'] as int) != line + 1 ||
          value['currency_code'] != j['currency_code'] ||
          value['posting_date'] != j['posting_date'] ||
          (value['party_id'] != null && value['party_id'] is! String) ||
          (value['source_line_id'] != null &&
              value['source_line_id'] is! String) ||
          (value['dimension_snapshot'] != null &&
              value['dimension_snapshot'] is! Map)) {
        throw const FormatException(
          'Journal line identity or ordering mismatch.',
        );
      }
      line = value['line_number'] as int;
      final bd = transport.decimal(value['base_debit']);
      final bc = transport.decimal(value['base_credit']);
      final td = transport.decimal(value['transaction_debit']);
      final tc = transport.decimal(value['transaction_credit']);
      if (bd.isNegative ||
          bc.isNegative ||
          td.isNegative ||
          tc.isNegative ||
          (bd.isPositive == bc.isPositive) ||
          (td.isPositive && tc.isPositive)) {
        throw const FormatException('Invalid exact journal line amount.');
      }
      pageDebit += bd;
      pageCredit += bc;
      _dimension(value, 'cost_centre', scope, branch);
      _dimension(value, 'project', scope, branch);
    }
    final count = j['line_count'] as int, next = r['next_cursor'];
    if (line > count ||
        pageDebit.compareTo(debit) > 0 ||
        pageCredit.compareTo(credit) > 0 ||
        (line < count && ((r['items'] as List).length != 50 || next != line)) ||
        (line == count && next != null) ||
        (next != null && next is! int) ||
        (afterLine == 0 &&
            line == count &&
            (pageDebit != debit || pageCredit != credit))) {
      throw const FormatException('Journal cursor or page totals mismatch.');
    }
    return r;
  }
}
