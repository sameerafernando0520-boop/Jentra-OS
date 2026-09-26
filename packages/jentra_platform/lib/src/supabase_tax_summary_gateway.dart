import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_control_reconciliation_gateway.dart';

abstract interface class TaxSummaryGateway {
  Future<Map<String, Object?>> periods(TenantContext scope, {String? after});
  Future<Map<String, Object?>> reports(TenantContext scope, {String? after});
  Future<Map<String, Object?>> page(
    TenantContext scope,
    String reportId, {
    int offset,
    String? sourceLineId,
  });
  Future<Map<String, Object?>> controls(
    TenantContext scope,
    String reportId,
    String section, {
    int offset,
    String? accountId,
    String? evidenceKey,
  });
  Future<Map<String, Object?>> generate(
    CommandEnvelope<Map<String, Object?>> command,
  );
}

final class SupabaseTaxSummaryGateway implements TaxSummaryGateway {
  SupabaseTaxSummaryGateway(SupabaseClient client)
    : transport = SupabaseControlReconciliationGateway(client);
  final SupabaseControlReconciliationGateway transport;

  void _scope(Map row, TenantContext scope) {
    if (row['tenant_id'] != scope.tenantId ||
        row['legal_entity_id'] != scope.legalEntityId ||
        row['branch_id'] != scope.branchId) {
      throw const FormatException('Tax report scope mismatch.');
    }
  }

  void _summary(Map row, TenantContext scope) {
    _scope(row, scope);
    for (final field in [
      'id',
      'period_id',
      'period_start',
      'period_end',
      'as_of',
      'generated_at',
      'base_currency_code',
    ]) {
      if (row[field] is! String) {
        throw const FormatException('Missing tax report identity.');
      }
    }
    if (row['branch_filter_id'] != null &&
        row['branch_filter_id'] != scope.branchId) {
      throw const FormatException('Tax report branch filter mismatch.');
    }
    if (!const [1, 2].contains(row['version']) ||
        !const ['generated', 'blocked'].contains(row['status']) ||
        row['notice'] != 'NON-CERTIFIED • STATUTORY REVIEW REQUIRED' ||
        row['line_count'] is! int ||
        row['blocked_count'] is! int ||
        row['line_count'] < 0 ||
        row['line_count'] > 10000 ||
        row['blocked_count'] < 0 ||
        row['blocked_count'] > row['line_count'] ||
        (row['status'] == 'blocked') !=
            (row['blocked_count'] > 0 || row['control_status'] == 'blocked') ||
        row['blockers'] is! List ||
        (row['blockers'] as List).length > 100 ||
        (row['blockers'] as List).length > row['blocked_count']) {
      throw const FormatException('Invalid tax review state.');
    }
    for (final field in [
      'output_tax_base',
      'input_tax_base',
      'withholding_tax_base',
      'zero_taxable_base',
      'exempt_taxable_base',
      'unverified_tax_base',
    ]) {
      transport.decimal(row[field]);
    }
    for (final blocker in row['blockers'] as List) {
      if (blocker is! Map ||
          blocker['source_id'] is! String ||
          blocker['source_line_id'] is! String ||
          blocker['code'] is! String) {
        throw const FormatException('Invalid tax review blocker.');
      }
    }
    if (row['version'] == 2) {
      for (final field in [
        'control_source_count',
        'control_journal_count',
        'control_difference_count',
        'control_review_count',
        'control_unassigned_source_count',
        'unattributed_journal_count',
      ]) {
        if (row[field] is! int || row[field] < 0 || row[field] > 10000) {
          throw const FormatException('Invalid tax-control count.');
        }
      }
      if (!const ['reconciled', 'blocked'].contains(row['control_status']) ||
          (row['control_status'] == 'blocked') !=
              (row['control_difference_count'] > 0 ||
                  row['control_review_count'] > 0) ||
          row['control_unassigned_source_count'] >
              row['control_source_count'] ||
          row['control_review_count'] > row['control_source_count'] ||
          row['unattributed_journal_count'] > row['control_journal_count'] ||
          row['controls'] is! List ||
          (row['controls'] as List).length > 50) {
        throw const FormatException('Invalid tax-control state.');
      }
      var source = transport.decimal('0'), gl = source;
      final ids = <String>{};
      for (final account in row['controls'] as List) {
        if (account is! Map || !ids.add(account['id'] as String? ?? '')) {
          throw const FormatException('Invalid tax-control account basis.');
        }
        _account(account);
        source += transport.decimal(account['source_closing_base']);
        gl += transport.decimal(account['gl_closing_base']);
      }
      if (source != transport.decimal(row['control_source_base']) ||
          gl != transport.decimal(row['control_gl_base']) ||
          source - gl != transport.decimal(row['control_difference'])) {
        throw const FormatException('Tax-control summary arithmetic mismatch.');
      }
    }
  }

  void _account(Map row) {
    if (row['id'] is! String ||
        row['id'] != row['account_id'] ||
        row['code'] is! String ||
        row['name'] is! String ||
        !const ['asset', 'liability'].contains(row['account_type'])) {
      throw const FormatException('Invalid tax-control account identity.');
    }
    final source =
        transport.decimal(row['source_opening_base']) +
        transport.decimal(row['source_period_base']);
    final gl =
        transport.decimal(row['gl_opening_base']) +
        transport.decimal(row['gl_period_base']);
    if (source != transport.decimal(row['source_closing_base']) ||
        gl != transport.decimal(row['gl_closing_base']) ||
        source - gl != transport.decimal(row['difference'])) {
      throw const FormatException('Tax-control account arithmetic mismatch.');
    }
  }

  @override
  Future<Map<String, Object?>> periods(
    TenantContext scope, {
    String? after,
  }) async {
    final result = await transport.call('period_governance_options', scope, {
      'p_resource': 'periods',
      'p_period_id': null,
      'p_after': after,
    });
    _scope(result, scope);
    if (result['resource'] != 'periods') {
      throw const FormatException('Tax period page mismatch.');
    }
    transport.rows(result);
    return result;
  }

  @override
  Future<Map<String, Object?>> reports(
    TenantContext scope, {
    String? after,
  }) async {
    final result = await transport.call('tax_summary_reports', scope, {
      'p_after': after,
    });
    _scope(result, scope);
    transport.rows(result);
    for (final row in result['items'] as List) {
      _summary(row as Map, scope);
    }
    return result;
  }

  @override
  Future<Map<String, Object?>> page(
    TenantContext scope,
    String reportId, {
    int offset = 0,
    String? sourceLineId,
  }) async {
    if (offset < 0 || offset > 10000) {
      throw const FormatException('Invalid tax report offset.');
    }
    final result = await transport.call('tax_summary_page', scope, {
      'p_report_id': reportId,
      'p_offset': offset,
      'p_source_line_id': sourceLineId,
    });
    if (result['summary'] is! Map) {
      throw const FormatException('Missing frozen tax report summary.');
    }
    final summary = result['summary'] as Map;
    _summary(summary, scope);
    if (summary['id'] != reportId ||
        result['next_offset'] != null && result['next_offset'] != offset + 50) {
      throw const FormatException('Tax report page mismatch.');
    }
    if (result['items'] is! List || (result['items'] as List).length > 50) {
      throw const FormatException('Invalid bounded tax evidence page.');
    }
    for (final value in result['items'] as List) {
      final row = value as Map;
      if (row['source_id'] is! String ||
          row['source_line_id'] is! String ||
          row['branch_id'] is! String ||
          row['posting_date'] is! String ||
          row['currency_code'] is! String ||
          row['base_currency_code'] != summary['base_currency_code'] ||
          (sourceLineId != null && row['source_line_id'] != sourceLineId) ||
          (summary['branch_filter_id'] != null &&
              row['branch_id'] != summary['branch_filter_id']) ||
          !const [
            'sales_invoice',
            'sales_return',
            'supplier_bill',
            'purchase_return',
            'manual_journal',
          ].contains(row['source_type']) ||
          row['journal_lines'] is! List ||
          row['review_code'] != null && row['review_code'] is! String) {
        throw const FormatException('Invalid tax source line.');
      }
      for (final field in [
        'taxable_amount',
        'tax_amount',
        'taxable_base',
        'tax_base',
        'expected_tax_base',
      ]) {
        transport.decimal(row[field]);
      }
      for (final journal in row['journal_lines'] as List) {
        if (journal is! Map ||
            journal['id'] is! String ||
            journal['journal_entry_id'] != row['journal_entry_id'] ||
            journal['account_id'] is! String) {
          throw const FormatException('Invalid posted tax journal line.');
        }
        for (final field in [
          'transaction_debit',
          'transaction_credit',
          'base_debit',
          'base_credit',
        ]) {
          transport.decimal(journal[field]);
        }
      }
    }
    return result;
  }

  @override
  Future<Map<String, Object?>> controls(
    TenantContext scope,
    String reportId,
    String section, {
    int offset = 0,
    String? accountId,
    String? evidenceKey,
  }) async {
    if (!const [
          'controls',
          'control_sources',
          'control_journals',
          'control_differences',
        ].contains(section) ||
        offset < 0 ||
        offset > 10000 ||
        evidenceKey != null && evidenceKey.length > 220) {
      throw const FormatException('Invalid tax-control page request.');
    }
    final result = await transport.call('tax_control_page', scope, {
      'p_report_id': reportId,
      'p_section': section,
      'p_offset': offset,
      'p_account_id': accountId,
      'p_evidence_key': evidenceKey,
    });
    if (result['summary'] is! Map ||
        result['section'] != section ||
        result['account_filter_id'] != accountId ||
        result['evidence_key'] != evidenceKey ||
        result['items'] is! List ||
        (result['items'] as List).length > 50 ||
        result['next_offset'] != null && result['next_offset'] != offset + 50) {
      throw const FormatException('Invalid bounded tax-control evidence.');
    }
    final summary = result['summary'] as Map;
    _summary(summary, scope);
    if (summary['id'] != reportId || summary['version'] != 2) {
      throw const FormatException('Tax-control report identity mismatch.');
    }
    for (final value in result['items'] as List) {
      if (value is! Map ||
          value['id'] is! String ||
          (accountId != null && value['account_id'] != accountId) ||
          (evidenceKey != null && value['evidence_key'] != evidenceKey)) {
        throw const FormatException('Tax-control filter mismatch.');
      }
      final row = value;
      if (section == 'controls') {
        _account(row);
      } else {
        if (row['evidence_key'] is! String ||
            row['account_id'] != null && row['account_id'] is! String) {
          throw const FormatException('Missing tax-control lineage.');
        }
        if (section == 'control_differences') {
          final difference =
              transport.decimal(row['expected_base']) -
              transport.decimal(row['posted_base']);
          if (difference != transport.decimal(row['difference']) ||
              difference == transport.decimal('0')) {
            throw const FormatException('Invalid tax-control difference.');
          }
        } else {
          if (row['source_id'] is! String ||
              row['source_type'] is! String ||
              row['branch_id'] is! String ||
              row['posting_date'] is! String ||
              row['currency_code'] is! String ||
              row['base_currency_code'] != summary['base_currency_code'] ||
              !const ['opening', 'period'].contains(row['phase']) ||
              summary['branch_filter_id'] != null &&
                  row['branch_id'] != summary['branch_filter_id']) {
            throw const FormatException('Invalid tax-control source scope.');
          }
          transport.decimal(row['posted_base']);
          if (section == 'control_sources') {
            transport.decimal(row['expected_base']);
            if (row['source_line_id'] is! String ||
                row['review_code'] != null && row['review_code'] is! String) {
              throw const FormatException('Invalid tax-control source.');
            }
          } else {
            if (row['journal_entry_id'] is! String ||
                row['command_id'] is! String ||
                transport.decimal(row['base_debit']) -
                        transport.decimal(row['base_credit']) !=
                    transport.decimal(row['posted_base'])) {
              throw const FormatException('Invalid tax-control journal.');
            }
            transport.decimal(row['transaction_debit']);
            transport.decimal(row['transaction_credit']);
          }
        }
      }
    }
    return result;
  }

  @override
  Future<Map<String, Object?>> generate(
    CommandEnvelope<Map<String, Object?>> command,
  ) => transport.command('generate_tax_summary', command, (result) {
    _summary(result, command.context);
    for (final field in ['id', 'period_id', 'as_of', 'branch_filter_id']) {
      if (result[field] != command.payload[field]) {
        throw const FormatException('Tax report request mismatch.');
      }
    }
  });
}
