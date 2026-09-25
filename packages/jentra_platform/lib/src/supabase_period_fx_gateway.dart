import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_control_reconciliation_gateway.dart';

abstract interface class PeriodFxGateway {
  Future<Map<String, Object?>> periodOptions(
    TenantContext scope,
    String resource, {
    String? periodId,
    String? after,
  });
  Future<Map<String, Object?>> fxOptions(
    TenantContext scope,
    String resource, {
    String? after,
  });
  Future<Map<String, Object?>> fxDetail(
    TenantContext scope,
    String runId, {
    int offset,
  });
  Future<Map<String, Object?>> govern(
    CommandEnvelope<Map<String, Object?>> command,
  );
  Future<Map<String, Object?>> revalue(
    CommandEnvelope<Map<String, Object?>> command,
  );
}

final class SupabasePeriodFxGateway implements PeriodFxGateway {
  SupabasePeriodFxGateway(SupabaseClient client)
    : transport = SupabaseControlReconciliationGateway(client);
  final SupabaseControlReconciliationGateway transport;

  void _scope(Map row, TenantContext scope) {
    if (row['tenant_id'] != scope.tenantId ||
        row['legal_entity_id'] != scope.legalEntityId ||
        row['branch_id'] != scope.branchId) {
      throw const FormatException('Period or FX response scope mismatch.');
    }
  }

  void _decimal(Map row, String field, {int scale = 6}) {
    if (!row.containsKey(field)) return;
    final value = row[field];
    if (value is! String ||
        !RegExp('^-?\\d+(\\.\\d{1,$scale})?\$').hasMatch(value)) {
      throw const FormatException('FX values must be exact decimal strings.');
    }
    ExactDecimal.parse(value, scale: scale);
  }

  void _page(Map row, TenantContext scope, String resource) {
    _scope(row, scope);
    if (row['resource'] != resource) {
      throw const FormatException('Page context mismatch.');
    }
    transport.rows(row);
    final ids = <String>{};
    for (final value in row['items'] as List) {
      final item = value as Map;
      if (!ids.add(item['id'] as String)) {
        throw const FormatException('Duplicate page row.');
      }
    }
  }

  @override
  Future<Map<String, Object?>> periodOptions(
    TenantContext scope,
    String resource, {
    String? periodId,
    String? after,
  }) async {
    if (!const ['periods', 'events', 'reopen_requests'].contains(resource)) {
      throw const FormatException('Unknown period resource.');
    }
    final row = await transport.call('period_governance_options', scope, {
      'p_resource': resource,
      'p_period_id': periodId,
      'p_after': after,
    });
    _page(row, scope, resource);
    if (row['period_id'] != periodId) {
      throw const FormatException('Period page context mismatch.');
    }
    return row;
  }

  @override
  Future<Map<String, Object?>> fxOptions(
    TenantContext scope,
    String resource, {
    String? after,
  }) async {
    if (!const ['rates', 'runs'].contains(resource)) {
      throw const FormatException('Unknown FX resource.');
    }
    final row = await transport.call('exchange_revaluation_options', scope, {
      'p_resource': resource,
      'p_after': after,
    });
    _page(row, scope, resource);
    for (final value in row['items'] as List) {
      final item = value as Map;
      _decimal(item, resource == 'rates' ? 'rate' : 'exchange_rate', scale: 10);
      _decimal(item, 'control_delta_base');
      if (resource == 'runs' &&
          (item['item_count'] is! int ||
              (item['item_count'] as int) < 0 ||
              (item['item_count'] as int) > 1000)) {
        throw const FormatException('Invalid FX snapshot size.');
      }
    }
    return row;
  }

  @override
  Future<Map<String, Object?>> fxDetail(
    TenantContext scope,
    String runId, {
    int offset = 0,
  }) async {
    if (offset < 0 || offset > 1000) {
      throw const FormatException('Invalid FX detail offset.');
    }
    final row = await transport.call('exchange_revaluation_detail', scope, {
      'p_run_id': runId,
      'p_offset': offset,
    });
    _scope(row, scope);
    if (row['id'] != runId ||
        row['offset'] != offset ||
        row['item_count'] is! int ||
        (row['item_count'] as int) < 0 ||
        (row['item_count'] as int) > 1000 ||
        row['snapshot_hash'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(row['snapshot_hash'] as String) ||
        row['items'] is! List ||
        (row['items'] as List).length > 50 ||
        (row['next_offset'] != null && row['next_offset'] is! int)) {
      throw const FormatException('Invalid bounded FX detail.');
    }
    for (final value in row['items'] as List) {
      if (value is! Map || value['id'] is! String) {
        throw const FormatException('Invalid FX source item.');
      }
      _decimal(value, 'open_amount');
      _decimal(value, 'open_base_amount');
    }
    return row;
  }

  @override
  Future<Map<String, Object?>> govern(
    CommandEnvelope<Map<String, Object?>> command,
  ) => transport.command('period_governance_command', command, (row) {
    _scope(row, command.context);
    final action = command.payload['action'];
    if (row['id'] != command.payload['id'] ||
        row['action'] != action ||
        row['period_id'] != command.payload['period_id'] ||
        row['version'] != 1 ||
        row['period_version'] is! int ||
        row['exceptions'] is! List ||
        (action == 'hard_lock'
            ? !const ['hard_locked', 'blocked'].contains(row['status'])
            : row['status'] !=
                  switch (action) {
                    'soft_lock' => 'soft_locked',
                    'request_reopen' => 'pending_approval',
                    'approve_reopen' => 'open',
                    _ => '',
                  })) {
      throw const FormatException('Period command receipt mismatch.');
    }
  });

  @override
  Future<Map<String, Object?>> revalue(
    CommandEnvelope<Map<String, Object?>> command,
  ) => transport.command('post_exchange_revaluation', command, (row) {
    _scope(row, command.context);
    final action = command.payload['action'];
    if (row['id'] != command.payload['id'] ||
        row['period_id'] != command.payload['period_id'] ||
        row['version'] != 1 ||
        row['status'] != (action == 'reverse' ? 'reversed' : 'posted') ||
        (action == 'reverse' && row['run_id'] != command.payload['run_id']) ||
        (action == 'post' &&
            row['currency_code'] != command.payload['currency_code'])) {
      throw const FormatException('FX command receipt mismatch.');
    }
    _decimal(row, 'control_delta_base');
    _decimal(row, 'exchange_rate', scale: 10);
  });
}
