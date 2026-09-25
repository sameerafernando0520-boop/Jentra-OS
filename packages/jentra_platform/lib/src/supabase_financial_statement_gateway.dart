import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_control_reconciliation_gateway.dart';

abstract interface class FinancialStatementGateway {
  Future<Map<String, Object?>> periods(TenantContext scope, {String? after});
  Future<Map<String, Object?>> reports(TenantContext scope, {String? after});
  Future<Map<String, Object?>> page(
    TenantContext scope,
    String reportId,
    String section, {
    int offset,
    String? accountId,
  });
  Future<Map<String, Object?>> generate(
    CommandEnvelope<Map<String, Object?>> command,
  );
}

final class SupabaseFinancialStatementGateway
    implements FinancialStatementGateway {
  SupabaseFinancialStatementGateway(SupabaseClient client)
    : transport = SupabaseControlReconciliationGateway(client);
  final SupabaseControlReconciliationGateway transport;

  void _scope(Map value, TenantContext scope, {bool branch = true}) {
    if (value['tenant_id'] != scope.tenantId ||
        value['legal_entity_id'] != scope.legalEntityId ||
        (branch && value['branch_id'] != scope.branchId)) {
      throw const FormatException('Financial report scope mismatch.');
    }
  }

  ExactDecimal _exact(Object? value) => transport.decimal(value);

  void _summary(Map value, TenantContext scope) {
    _scope(value, scope, branch: false);
    if (value['id'] is! String ||
        value['branch_id'] is! String ||
        value['period_id'] is! String ||
        value['period_start'] is! String ||
        value['period_end'] is! String ||
        value['as_of'] is! String ||
        value['base_currency_code'] is! String ||
        value['generated_at'] is! String ||
        !const ['generated', 'blocked'].contains(value['status']) ||
        value['version'] != 1 ||
        !const [
          'trial_balance',
          'profit_loss',
          'balance_sheet',
          'cash_flow',
        ].contains(value['kind']) ||
        (value['status'] == 'blocked' && value['kind'] != 'cash_flow') ||
        value['account_count'] is! int ||
        value['journal_count'] is! int ||
        (value['account_count'] as int) < 0 ||
        (value['account_count'] as int) > 5000 ||
        (value['journal_count'] as int) < 0 ||
        (value['journal_count'] as int) > 10000 ||
        (value['comparative'] != null && value['comparative'] is! Map)) {
      throw const FormatException('Invalid financial statement summary.');
    }
    final debit = _exact(value['period_debit']);
    final credit = _exact(value['period_credit']);
    final closingDebit = _exact(value['closing_debit']);
    final closingCredit = _exact(value['closing_credit']);
    if (debit != credit || closingDebit != closingCredit) {
      throw const FormatException('Unbalanced financial statement.');
    }
    final difference = _exact(value['difference']);
    if (value['kind'] == 'profit_loss') {
      if (_exact(value['revenue']) - _exact(value['expenses']) !=
          _exact(value['net_profit'])) {
        throw const FormatException('Inconsistent profit and loss.');
      }
      final comparison = value['comparative'];
      if (comparison is Map &&
          _exact(comparison['revenue']) - _exact(comparison['expenses']) !=
              _exact(comparison['net_profit'])) {
        throw const FormatException('Inconsistent comparative profit.');
      }
    } else if (value['kind'] == 'balance_sheet') {
      if (_exact(value['assets']) -
              _exact(value['liabilities']) -
              _exact(value['equity']) -
              _exact(value['current_earnings']) !=
          difference) {
        throw const FormatException('Inconsistent balance sheet.');
      }
      final comparison = value['comparative'];
      if (comparison is Map &&
          _exact(comparison['assets']) -
                  _exact(comparison['liabilities']) -
                  _exact(comparison['equity']) -
                  _exact(comparison['current_earnings']) !=
              _exact(comparison['difference'])) {
        throw const FormatException('Inconsistent comparative balance.');
      }
    } else if (value['kind'] == 'cash_flow') {
      final current = value['cash_flow'];
      final comparison = value['comparative'];
      if (current is! Map ||
          (comparison != null && comparison is! Map)) {
        throw const FormatException('Missing indirect cash-flow bridge.');
      }
      _cashFlow(current);
      if (comparison is Map) _cashFlow(comparison);
      final blocked = current['status'] == 'blocked' ||
          (comparison is Map && comparison['status'] == 'blocked');
      if ((blocked ? 'blocked' : 'generated') != value['status']) {
        throw const FormatException('Cash-flow blocker state mismatch.');
      }
    } else if (difference != closingDebit - closingCredit) {
      throw const FormatException('Inconsistent trial balance.');
    }
    if (difference != ExactDecimal.zero(scale: 6)) {
      throw const FormatException('Financial statement does not balance.');
    }
  }

  void _cashFlow(Map value) {
    if (value['mapped_cash_count'] is! int ||
        value['unmapped_count'] is! int ||
        value['no_mapped_cash'] is! bool ||
        value['unmapped_accounts'] is! List ||
        (value['unmapped_accounts'] as List).length > 50 ||
        !const ['generated', 'blocked'].contains(value['status'])) {
      throw const FormatException('Invalid indirect cash-flow evidence.');
    }
    for (final row in value['unmapped_accounts'] as List) {
      if (row is! Map ||
          row['id'] is! String ||
          row['code'] is! String ||
          row['name'] is! String) {
        throw const FormatException('Invalid unclassified account.');
      }
      _exact(row['unclassified_movement']);
    }
    final profit = _exact(value['period_profit']);
    final adjustments = _exact(value['noncash_adjustments']);
    final working = _exact(value['working_capital_change']);
    final operating = _exact(value['operating_cash']);
    final investing = _exact(value['investing_cash']);
    final financing = _exact(value['financing_cash']);
    final net = _exact(value['net_cash_change']);
    final opening = _exact(value['opening_cash']);
    final closing = _exact(value['closing_cash']);
    final cashDelta = _exact(value['cash_delta']);
    final difference = _exact(value['difference']);
    if (profit + adjustments + working != operating ||
        operating + investing + financing != net ||
        closing - opening != cashDelta ||
        net - cashDelta != difference ||
        (value['no_mapped_cash'] == ((value['mapped_cash_count'] as int) > 0)) ||
        (value['unmapped_count'] as int) <
            (value['unmapped_accounts'] as List).length) {
      throw const FormatException('Indirect cash flow does not reconcile.');
    }
    final blocked = (value['unmapped_count'] as int) > 0 ||
        value['no_mapped_cash'] == true ||
        difference != ExactDecimal.zero(scale: 6);
    if ((blocked ? 'blocked' : 'generated') != value['status']) {
      throw const FormatException('Unmapped cash-flow items were not blocked.');
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
      throw const FormatException('Period page context mismatch.');
    }
    transport.rows(result);
    return result;
  }

  @override
  Future<Map<String, Object?>> reports(
    TenantContext scope, {
    String? after,
  }) async {
    final result = await transport.call('financial_statement_reports', scope, {
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
    String reportId,
    String section, {
    int offset = 0,
    String? accountId,
  }) async {
    if (!const ['accounts', 'journals'].contains(section) ||
        offset < 0 ||
        offset > 10000) {
      throw const FormatException('Invalid financial report page.');
    }
    final result = await transport.call('financial_statement_page', scope, {
      'p_report_id': reportId,
      'p_section': section,
      'p_offset': offset,
      'p_account_id': accountId,
    });
    if (result['summary'] is! Map) {
      throw const FormatException('Missing frozen report summary.');
    }
    final summary = result['summary'] as Map;
    _summary(summary, scope);
    if (summary['id'] != reportId ||
        result['section'] != section ||
        result['account_id'] != accountId ||
        (result['next_offset'] != null &&
            result['next_offset'] != offset + 50)) {
      throw const FormatException('Financial report page mismatch.');
    }
    transport.rows({
      'items': result['items'],
      'next_cursor': result['next_offset']?.toString(),
    });
    for (final row in result['items'] as List) {
      final item = row as Map;
      if (item['account_id'] is! String ||
          (accountId != null && item['account_id'] != accountId)) {
        throw const FormatException('Financial source account mismatch.');
      }
      if (section == 'accounts' &&
              (item['code'] is! String ||
                  item['name'] is! String ||
                  !const [
                    'asset',
                    'liability',
                    'equity',
                    'revenue',
                    'expense',
                  ].contains(item['account_type'])) ||
          section == 'journals' &&
              (item['journal_entry_id'] is! String ||
                  item['posting_date'] is! String ||
                  item['source_type'] is! String)) {
        throw const FormatException('Invalid frozen financial source.');
      }
      for (final field
          in section == 'accounts'
              ? const [
                  'opening_balance',
                  'period_debit',
                  'period_credit',
                  'closing_balance',
                  'amount',
                ]
              : const [
                  'transaction_debit',
                  'transaction_credit',
                  'base_debit',
                  'base_credit',
                ]) {
        _exact(item[field]);
      }
      if (item['comparative_amount'] != null) {
        _exact(item['comparative_amount']);
      }
      if (section == 'accounts' && summary['kind'] == 'cash_flow' &&
          !const [
            'cash',
            'profit',
            'noncash_adjustment',
            'working_capital',
            'investing',
            'financing',
            'unmapped',
          ].contains(item['cash_flow_category'])) {
        throw const FormatException('Invalid cash-flow classification.');
      }
    }
    return result;
  }

  @override
  Future<Map<String, Object?>> generate(
    CommandEnvelope<Map<String, Object?>> command,
  ) => transport.command('generate_financial_statement', command, (result) {
    _summary(result, command.context);
    _scope(result, command.context);
    for (final field in [
      'id',
      'kind',
      'period_id',
      'as_of',
      'comparative_period_id',
    ]) {
      if (result[field] != command.payload[field]) {
        throw const FormatException('Financial report request mismatch.');
      }
    }
  });
}

abstract interface class CashFlowMappingGateway {
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String asOf, {
    String? after,
  });
  Future<Map<String, Object?>> configure(
    CommandEnvelope<Map<String, Object?>> command,
  );
}

final class SupabaseCashFlowMappingGateway implements CashFlowMappingGateway {
  SupabaseCashFlowMappingGateway(SupabaseClient client)
    : transport = SupabaseControlReconciliationGateway(client);
  final SupabaseControlReconciliationGateway transport;

  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String asOf, {
    String? after,
  }) async {
    final result = await transport.call('cash_flow_mapping_options', scope, {
      'p_as_of': asOf,
      'p_after': after,
    });
    if (result['tenant_id'] != scope.tenantId ||
        result['legal_entity_id'] != scope.legalEntityId ||
        result['branch_id'] != scope.branchId ||
        result['as_of'] != asOf) {
      throw const FormatException('Cash-flow mapping scope mismatch.');
    }
    transport.rows(result);
    for (final value in result['items'] as List) {
      final row = value as Map;
      if (row['account_id'] != row['id'] ||
          row['code'] is! String ||
          row['name'] is! String ||
          !const ['asset', 'liability', 'equity'].contains(
            row['account_type'],
          ) ||
          (row['category'] != null &&
              !const [
                'cash',
                'noncash_adjustment',
                'working_capital',
                'investing',
                'financing',
              ].contains(row['category'])) ||
          (row['category'] != null &&
              (row['mapping_id'] is! String ||
                  row['version'] is! int ||
                  row['effective_date'] is! String))) {
        throw const FormatException('Invalid cash-flow account mapping.');
      }
    }
    return result;
  }

  @override
  Future<Map<String, Object?>> configure(
    CommandEnvelope<Map<String, Object?>> command,
  ) => transport.command('configure_cash_flow_mapping', command, (result) {
    if (result['tenant_id'] != command.context.tenantId ||
        result['legal_entity_id'] != command.context.legalEntityId ||
        result['branch_id'] != command.context.branchId ||
        result['status'] != 'configured' ||
        result['version'] != (command.expectedEntityVersion ?? -1) + 1) {
      throw const FormatException('Cash-flow mapping receipt mismatch.');
    }
    for (final field in [
      'id',
      'account_id',
      'category',
      'effective_date',
      'reason',
    ]) {
      if (result[field] != command.payload[field]) {
        throw const FormatException('Cash-flow mapping request mismatch.');
      }
    }
  });
}
