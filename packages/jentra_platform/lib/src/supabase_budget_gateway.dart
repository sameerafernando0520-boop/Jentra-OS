import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_control_reconciliation_gateway.dart';
import 'supabase_financial_dimension_gateway.dart';

abstract interface class BudgetGateway {
  Future<Map<String, Object?>> accounts(
    TenantContext scope, {
    String? after,
    String search,
  });
  Future<Map<String, Object?>> periods(TenantContext scope, {String? after});
  Future<Map<String, Object?>> budgets(TenantContext scope, {String? after});
  Future<Map<String, Object?>> reports(TenantContext scope, {String? after});
  Future<Map<String, Object?>> page(
    TenantContext scope,
    String reportId,
    String section, {
    int offset,
    String? budgetLineId,
  });
  Future<Map<String, Object?>> command(
    CommandEnvelope<Map<String, Object?>> command,
  );
  Future<Map<String, Object?>> generate(
    CommandEnvelope<Map<String, Object?>> command,
  );
}

final class SupabaseBudgetGateway implements BudgetGateway {
  SupabaseBudgetGateway(SupabaseClient client)
    : transport = SupabaseControlReconciliationGateway(client);
  final SupabaseControlReconciliationGateway transport;

  void _scope(Map value, TenantContext scope) {
    if (value['tenant_id'] != scope.tenantId ||
        value['legal_entity_id'] != scope.legalEntityId ||
        value['branch_id'] != scope.branchId) {
      throw const FormatException('Budget scope mismatch.');
    }
  }

  ExactDecimal _exact(Object? value) => transport.decimal(value);

  void _lines(List lines, TenantContext? scope, {bool entityOnly = false}) {
    if (lines.isEmpty || lines.length > 500) {
      throw const FormatException('Invalid budget lines.');
    }
    final ids = <String>{};
    final prior = <Map>[];
    for (final raw in lines) {
      if (raw is! Map ||
          raw['id'] is! String ||
          raw['account_id'] is! String ||
          !ids.add(raw['id'] as String)) {
        throw const FormatException('Invalid budget account or dimension.');
      }
      FinancialDimensionEvidence.validate(raw, scope, entityOnly: entityOnly);
      for (final earlier in prior) {
        if (earlier['account_id'] == raw['account_id'] &&
            ['cost_centre_id', 'project_id'].every(
              (k) =>
                  earlier[k] == null || raw[k] == null || earlier[k] == raw[k],
            )) {
          throw const FormatException('Budget dimensions overlap.');
        }
      }
      prior.add(raw);
      final amount = _exact(raw['amount']);
      if (amount.isNegative) {
        throw const FormatException('Budget amount must be nonnegative.');
      }
    }
  }

  void _budget(Map value, {TenantContext? scope, bool receipt = false}) {
    if (scope != null && receipt) _scope(value, scope);
    if (value['id'] is! String ||
        value['root_id'] is! String ||
        value['revision'] is! int ||
        (value['revision'] as int) < 1 ||
        value['budget_year'] is! int ||
        value['period_id'] != null && value['period_id'] is! String ||
        value['budget_branch_id'] != null &&
            value['budget_branch_id'] is! String ||
        value['currency_code'] is! String ||
        value['version'] is! int ||
        (value['version'] as int) < 1 ||
        value['reason'] is! String ||
        !const [
          'draft',
          'submitted',
          'approved',
          'rejected',
        ].contains(value['status']) ||
        value['lines'] is! List) {
      throw const FormatException('Invalid budget version.');
    }
    _lines(
      value['lines'] as List,
      scope,
      entityOnly: value['budget_branch_id'] == null,
    );
    if (receipt && value['line_count'] != (value['lines'] as List).length) {
      throw const FormatException('Budget line count mismatch.');
    }
  }

  void _summary(Map value, TenantContext scope) {
    _scope(value, scope);
    if (value['id'] is! String ||
        value['budget_id'] is! String ||
        value['as_of'] is! String ||
        value['period_start'] is! String ||
        value['period_end'] is! String ||
        value['generated_at'] is! String ||
        value['currency_code'] is! String ||
        value['base_currency_code'] is! String ||
        !const [
          'base_all_posted',
          'matching_transaction_only',
        ].contains(value['currency_basis']) ||
        value['status'] != 'generated' ||
        value['version'] != 1 ||
        value['line_count'] is! int ||
        (value['line_count'] as int) < 1 ||
        (value['line_count'] as int) > 500 ||
        value['journal_count'] is! int ||
        (value['journal_count'] as int) < 0 ||
        (value['journal_count'] as int) > 10000 ||
        value['budget_revision'] is! int ||
        value['budget_branch_id'] != null &&
            value['budget_branch_id'] is! String) {
      throw const FormatException('Invalid budget variance summary.');
    }
    final budget = _exact(value['budget_total']);
    final actual = _exact(value['actual_total']);
    final variance = _exact(value['variance_total']);
    if (actual - budget != variance) {
      throw const FormatException('Budget variance does not reconcile.');
    }
    if (value['variance_percent'] != null) _exact(value['variance_percent']);
  }

  @override
  Future<Map<String, Object?>> accounts(
    TenantContext scope, {
    String? after,
    String search = '',
  }) async {
    final result = await transport.call('manual_journal_options', scope, {
      'p_resource': 'accounts',
      'p_after': after,
      'p_search': search,
    });
    transport.rows(result);
    if (result['base_currency_code'] is! String) {
      throw const FormatException('Missing base currency.');
    }
    for (final raw in result['items'] as List) {
      final row = raw as Map;
      if (row['code'] is! String ||
          row['name'] is! String ||
          row['account_type'] is! String) {
        throw const FormatException('Invalid budget account picker.');
      }
    }
    return result;
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
      throw const FormatException('Budget period picker mismatch.');
    }
    transport.rows(result);
    for (final raw in result['items'] as List) {
      final row = raw as Map;
      if (row['name'] is! String ||
          row['start_date'] is! String ||
          row['end_date'] is! String) {
        throw const FormatException('Invalid budget period.');
      }
    }
    return result;
  }

  @override
  Future<Map<String, Object?>> budgets(
    TenantContext scope, {
    String? after,
  }) async {
    final result = await transport.call('budget_options', scope, {
      'p_after': after,
    });
    _scope(result, scope);
    transport.rows(result);
    for (final raw in result['items'] as List) {
      _budget(raw as Map, scope: scope);
      if (raw['budget_branch_id'] != null &&
          raw['budget_branch_id'] != scope.branchId) {
        throw const FormatException('Budget branch mismatch.');
      }
    }
    return result;
  }

  @override
  Future<Map<String, Object?>> reports(
    TenantContext scope, {
    String? after,
  }) async {
    final result = await transport.call('budget_variance_reports', scope, {
      'p_after': after,
    });
    _scope(result, scope);
    transport.rows(result);
    for (final raw in result['items'] as List) {
      _summary(raw as Map, scope);
    }
    return result;
  }

  @override
  Future<Map<String, Object?>> page(
    TenantContext scope,
    String reportId,
    String section, {
    int offset = 0,
    String? budgetLineId,
  }) async {
    if (!const ['lines', 'journals'].contains(section) ||
        offset < 0 ||
        offset > 10000) {
      throw const FormatException('Invalid budget evidence page.');
    }
    final result = await transport.call('budget_variance_page', scope, {
      'p_report_id': reportId,
      'p_section': section,
      'p_offset': offset,
      'p_budget_line_id': budgetLineId,
    });
    final rawSummary = result['summary'];
    if (rawSummary is! Map) {
      throw const FormatException('Missing variance summary.');
    }
    _summary(rawSummary, scope);
    if (rawSummary['id'] != reportId ||
        result['section'] != section ||
        result['budget_line_id'] != budgetLineId ||
        result['next_offset'] != null && result['next_offset'] != offset + 50) {
      throw const FormatException('Budget evidence page mismatch.');
    }
    transport.rows({
      'items': result['items'],
      'next_cursor': result['next_offset']?.toString(),
    });
    for (final raw in result['items'] as List) {
      final row = raw as Map;
      FinancialDimensionEvidence.validate(
        row,
        section == 'journals'
            ? scope.copyWith(branchId: row['branch_id'] as String? ?? scope.branchId)
            : scope,
        entityOnly: section == 'lines' && rawSummary['budget_branch_id'] == null,
      );
      if (section == 'lines') {
        if (row['account_id'] is! String ||
            row['code'] is! String ||
            row['name'] is! String ||
            row['source_count'] is! int ||
            budgetLineId != null && row['id'] != budgetLineId) {
          throw const FormatException('Invalid budget variance line.');
        }
        final budget = _exact(row['budget_amount']);
        final actual = _exact(row['actual_amount']);
        if (actual - budget != _exact(row['variance'])) {
          throw const FormatException('Budget account variance mismatch.');
        }
        if (row['variance_percent'] != null) _exact(row['variance_percent']);
      } else {
        if (row['budget_line_id'] is! String ||
            budgetLineId != null && row['budget_line_id'] != budgetLineId ||
            row['journal_entry_id'] is! String ||
            row['posting_date'] is! String ||
            row['source_type'] is! String) {
          throw const FormatException('Invalid budget journal source.');
        }
        for (final key in const [
          'base_debit',
          'base_credit',
          'transaction_debit',
          'transaction_credit',
        ]) {
          _exact(row[key]);
        }
      }
    }
    return result;
  }

  @override
  Future<Map<String, Object?>> command(
    CommandEnvelope<Map<String, Object?>> command,
  ) => transport.command('budget_command', command, (result) {
    _budget(result, scope: command.context, receipt: true);
    if (result['id'] != command.payload['id'] ||
        result['budget_branch_id'] != null &&
            result['budget_branch_id'] != command.context.branchId) {
      throw const FormatException('Budget command identity mismatch.');
    }
    final action = command.payload['action'];
    final expected = command.expectedEntityVersion ?? 0;
    if (action == 'create' || action == 'revise') {
      if (result['status'] != 'draft' || result['version'] != 1) {
        throw const FormatException('Budget draft receipt mismatch.');
      }
    } else if (result['version'] != expected + 1 ||
        result['status'] !=
            switch (action) {
              'submit' => 'submitted',
              'approve' => 'approved',
              'reject' => 'rejected',
              _ => 'draft',
            }) {
      throw const FormatException('Budget transition receipt mismatch.');
    }
    if (action == 'create' || action == 'save') {
      final requestLines = command.payload['lines'];
      final confirmed = result['lines'] as List;
      if (requestLines is! List || requestLines.length != confirmed.length) {
        throw const FormatException('Budget lines receipt mismatch.');
      }
      for (var i = 0; i < requestLines.length; i++) {
        final wanted = requestLines[i] as Map;
        final actual = confirmed[i] as Map;
        if (wanted['id'] != actual['id'] ||
            wanted['account_id'] != actual['account_id'] ||
            wanted['cost_centre_id'] != actual['cost_centre_id'] ||
            wanted['project_id'] != actual['project_id'] ||
            _exact(wanted['amount']) != _exact(actual['amount'])) {
          throw const FormatException('Budget amount receipt mismatch.');
        }
      }
    }
  });

  @override
  Future<Map<String, Object?>> generate(
    CommandEnvelope<Map<String, Object?>> command,
  ) => transport.command('generate_budget_variance', command, (result) {
    _summary(result, command.context);
    for (final key in const ['id', 'budget_id', 'as_of']) {
      if (result[key] != command.payload[key]) {
        throw const FormatException('Budget variance request mismatch.');
      }
    }
  });
}
