import 'dart:convert';

import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_control_reconciliation_gateway.dart';

abstract interface class OperationalGateway {
  Future<Map<String, Object?>> currentPage(
    TenantContext scope,
    String kind, {
    Map<String, Object?> filters = const {},
    String? after,
  });
  Future<Map<String, Object?>> evidence(
    TenantContext scope,
    String kind,
    String id, {
    String? after,
  });
  Future<Map<String, Object?>> dashboard(TenantContext scope);
  Future<Map<String, Object?>> generate(
    CommandEnvelope<Map<String, Object?>> command,
  );
  Future<Map<String, Object?>> rejectAttachment(
    CommandEnvelope<Map<String, Object?>> command,
  );
  Future<Map<String, Object?>> reportPage(
    TenantContext scope,
    String id,
    String section, {
    int after = 0,
  });
  Future<String> signedAttachmentUrl(
    TenantContext scope,
    String kind,
    String sourceId,
    Map<String, Object?> attachment,
  );
}

final class SupabaseOperationalGateway implements OperationalGateway {
  SupabaseOperationalGateway(SupabaseClient client)
    : _client = client,
      _transport = SupabaseControlReconciliationGateway(client);
  final SupabaseClient _client;
  final SupabaseControlReconciliationGateway _transport;

  static const kinds = <String>{
    'lead',
    'opportunity',
    'quotation',
    'sales_order',
    'delivery',
    'sales_invoice',
    'customer_receipt',
    'sales_return',
    'purchase_requisition',
    'rfq',
    'purchase_order',
    'goods_receipt',
    'supplier_bill',
    'payment_proposal',
    'supplier_payment',
    'purchase_return',
    'inventory_transfer',
    'stock_count',
    'inventory_value_adjustment',
    'landed_extension',
    'inventory_disposition',
    'manual_journal',
    'budget',
    'bank_statement',
    'bank_match',
  };
  static const _destinations = <String>{
    '/crm',
    '/sales',
    '/procurement',
    '/inventory/transfers',
    '/inventory/counts',
    '/finance/journals',
    '/finance/budgets',
    '/finance/bank',
  };
  static const dashboardMetrics = <String, (String, String)>{
    'pipeline': ('dated_pipeline', '/crm'),
    'ar_aging': ('dated_open_items', '/receivables'),
    'ap_aging': ('dated_open_items', '/procurement/payments'),
    'cash_bank': ('dated_posted_controls', '/finance/bank'),
    'periods': ('current_period_state', '/finance/periods'),
    'bill_exceptions': ('current_match_exceptions', '/procurement/bills'),
    'budgets': ('current_state_and_saved_review', '/finance/budgets'),
    'close_review': ('latest_saved_review', '/finance/close-review'),
  };
  static final _exactField = RegExp(
    r'(?:^|_)(?:amount|total|debit|credit|price|rate|value|quantity|percent)$',
  );
  static final _exactValue = RegExp(r'^-?\d+(?:\.\d+)?$');

  void _scope(Map value, TenantContext scope) {
    if (value['tenant_id'] != scope.tenantId ||
        value['legal_entity_id'] != scope.legalEntityId ||
        value['branch_id'] != scope.branchId) {
      throw const FormatException('Operational scope mismatch.');
    }
  }

  void _exact(Object? value, [String? key]) {
    if (value is Map) {
      for (final entry in value.entries) {
        _exact(entry.value, entry.key.toString());
      }
    } else if (value is List) {
      for (final item in value) {
        _exact(item);
      }
    } else if (key != null &&
        _exactField.hasMatch(key) &&
        value != null &&
        (value is! String || !_exactValue.hasMatch(value))) {
      throw const FormatException(
        'Financial values require exact decimal strings.',
      );
    }
  }

  List _items(Map response, String key) {
    final values = response[key];
    if (values is! List || values.length > 50 || values.any((v) => v is! Map)) {
      throw const FormatException('Invalid bounded operational page.');
    }
    return values;
  }

  void _cursor(Map response) {
    final next = response['next_cursor'];
    if (next != null && (next is! String || next.isEmpty)) {
      throw const FormatException('Invalid operational cursor.');
    }
  }

  bool _same(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((key) => b.containsKey(key) && _same(a[key], b[key]));
    }
    return a == b;
  }

  @override
  Future<Map<String, Object?>> currentPage(
    TenantContext scope,
    String kind, {
    Map<String, Object?> filters = const {},
    String? after,
  }) async {
    if (!kinds.contains(kind) ||
        filters.keys.any(
          (k) =>
              !const {'search', 'status', 'from_date', 'to_date'}.contains(k),
        )) {
      throw const FormatException('Unsupported document list.');
    }
    final r = await _transport.call('wave3_document_page', scope, {
      'p_kind': kind,
      'p_filters': filters,
      'p_after': after,
    });
    _scope(r, scope);
    if (r['kind'] != kind ||
        r['basis'] != 'current' ||
        !_same(r['filters'], filters)) {
      throw const FormatException('Invalid operational list identity.');
    }
    final rows = _items(r, 'items');
    if (rows.any(
      (row) =>
          row['id'] is! String ||
          row['tenant_id'] != scope.tenantId ||
          row['legal_entity_id'] != scope.legalEntityId ||
          (row['branch_id'] != null && row['branch_id'] != scope.branchId),
    )) {
      throw const FormatException('Missing source document identity.');
    }
    _cursor(r);
    if (r['next_cursor'] != null &&
        (rows.length != 50 || r['next_cursor'] != rows.last['id'])) {
      throw const FormatException(
        'Incomplete operational page or unrelated cursor.',
      );
    }
    _exact(rows);
    return r;
  }

  @override
  Future<Map<String, Object?>> evidence(
    TenantContext scope,
    String kind,
    String id, {
    String? after,
  }) async {
    if (!kinds.contains(kind) || id.isEmpty) {
      throw const FormatException('Unsupported source destination.');
    }
    final r = await _transport.call('wave3_document_evidence', scope, {
      'p_kind': kind,
      'p_id': id,
      'p_after': after,
    });
    _scope(r, scope);
    if (r['kind'] != kind ||
        r['id'] != id ||
        r['header'] is! Map ||
        (r['header'] as Map)['id'] != id ||
        (r['header'] as Map)['tenant_id'] != scope.tenantId ||
        (r['header'] as Map)['legal_entity_id'] != scope.legalEntityId) {
      throw const FormatException('Source evidence identity mismatch.');
    }
    _items(r, 'items');
    _items(r, 'commands');
    _items(r, 'attachments');
    _cursor(r);
    _exact(r['header']);
    _exact(r['items']);
    return r;
  }

  @override
  Future<Map<String, Object?>> dashboard(TenantContext scope) async {
    final r = await _transport.call('wave3_dashboard', scope, {});
    _scope(r, scope);
    final cards = r['cards'];
    if (cards is! List || cards.length > kinds.length) {
      throw const FormatException('Invalid dashboard response.');
    }
    final seen = <String>{};
    for (final value in cards) {
      if (value is! Map ||
          !kinds.contains(value['kind']) ||
          !seen.add(value['kind'] as String) ||
          value['basis'] != 'current_actionable' ||
          value['count'] is! String ||
          !RegExp(r'^\d+$').hasMatch(value['count'] as String) ||
          !_destinations.contains(value['destination'])) {
        throw const FormatException('Invalid dashboard card.');
      }
      _scope(value, scope);
    }
    final metrics = r['metrics'] ?? const [];
    if (metrics is! List ||
        metrics.length > dashboardMetrics.length ||
        utf8.encode(jsonEncode(r)).length > 1048576) {
      throw const FormatException('Invalid bounded dashboard metrics.');
    }
    final metricKinds = <String>{};
    for (final value in metrics) {
      if (value is! Map || value['kind'] is! String) {
        throw const FormatException('Invalid dashboard metric.');
      }
      final expected = dashboardMetrics[value['kind']];
      if (expected == null ||
          !metricKinds.add(value['kind'] as String) ||
          value['basis'] != expected.$1 ||
          value['destination'] != expected.$2 ||
          value['generated_at'] is! String ||
          DateTime.tryParse(value['generated_at'] as String) == null ||
          value['as_of'] is! String ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value['as_of'] as String) ||
          !value.containsKey('data')) {
        throw const FormatException('Invalid dashboard metric identity.');
      }
      _scope(value, scope);
      _exact(value['data']);
    }
    return r;
  }

  @override
  Future<Map<String, Object?>> generate(
    CommandEnvelope<Map<String, Object?>> command,
  ) => _transport.command('generate_operational_report', command, (entity) {
    _scope(entity, command.context);
    if (entity['id'] != command.payload['id'] ||
        entity['kind'] != command.payload['kind'] ||
        entity['status'] != 'generated' ||
        entity['version'] != 1) {
      throw const FormatException('Invalid operational report receipt.');
    }
  });

  @override
  Future<Map<String, Object?>> rejectAttachment(
    CommandEnvelope<Map<String, Object?>> command,
  ) => _transport.command('reject_wave3_attachment', command, (entity) {
    if (entity['id'] != command.payload['id'] ||
        entity['aggregate_type'] != command.payload['aggregate_type'] ||
        entity['aggregate_id'] != command.payload['aggregate_id'] ||
        entity['status'] != 'rejected' ||
        entity['version'] is! int) {
      throw const FormatException('Invalid attachment rejection receipt.');
    }
  });

  @override
  Future<Map<String, Object?>> reportPage(
    TenantContext scope,
    String id,
    String section, {
    int after = 0,
  }) async {
    if (id.isEmpty ||
        !const {'rows', 'aging', 'sources'}.contains(section) ||
        after < 0 ||
        after > 10000) {
      throw const FormatException('Invalid operational report page.');
    }
    final r = await _transport.call('operational_report_page', scope, {
      'p_id': id,
      'p_section': section,
      'p_after': after,
    });
    final summary = r['summary'];
    if (summary is! Map || summary['id'] != id || r['section'] != section) {
      throw const FormatException('Frozen report identity mismatch.');
    }
    _scope(summary, scope);
    _items(r, 'items');
    _cursor(r);
    _exact(r['items']);
    return r;
  }

  @override
  Future<String> signedAttachmentUrl(
    TenantContext scope,
    String kind,
    String sourceId,
    Map<String, Object?> attachment,
  ) async {
    if (!scope.hasOperationalScope ||
        _client.auth.currentUser?.id != scope.actorId ||
        !kinds.contains(kind) ||
        attachment['upload_status'] != 'ready' ||
        attachment['id'] is! String ||
        attachment['object_path'] !=
            '${scope.tenantId}/$kind/$sourceId/${attachment['id']}/${attachment['id']}${_extension(attachment['file_name'])}') {
      throw const FormatException('Invalid private attachment identity.');
    }
    try {
      return await _client.storage
          .from('jentra-attachments')
          .createSignedUrl(attachment['object_path'] as String, 15 * 60);
    } on StorageException catch (failure) {
      final code = switch (failure.statusCode) {
        '401' => 'AUTHENTICATION_REQUIRED',
        '403' => 'PERMISSION_DENIED',
        '400' || '404' => 'READ_REJECTED',
        _ => 'READ_UNAVAILABLE',
      };
      throw DomainError(
        code: code,
        message: switch (code) {
          'AUTHENTICATION_REQUIRED' =>
            'Restore your authenticated session before opening this attachment.',
          'PERMISSION_DENIED' =>
            'Current source and attachment access is required.',
          'READ_REJECTED' =>
            'This attachment could not be opened. Refresh its source evidence.',
          _ =>
            'Attachment access is temporarily unavailable. Retry after checking the connection.',
        },
      );
    } on TypeError {
      throw const DomainError(
        code: 'READ_INVALID',
        message:
            'Attachment access returned an invalid link. Refresh its source evidence.',
      );
    } catch (_) {
      throw const DomainError(
        code: 'READ_UNAVAILABLE',
        message:
            'Attachment access is temporarily unavailable. Retry after checking the connection.',
      );
    }
  }

  String _extension(Object? name) {
    if (name is! String) return '';
    final match = RegExp(r'(\.[a-z0-9]{1,10})$').firstMatch(name.toLowerCase());
    return match?.group(1) ?? '';
  }
}
