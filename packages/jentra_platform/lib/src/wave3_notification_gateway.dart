import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_control_reconciliation_gateway.dart';

const wave3NoticeClasses = {
  'submission',
  'decision',
  'posting',
  'exception',
  'due',
  'allocation',
  'reconciliation',
  'close',
  'reversal',
};

abstract interface class Wave3NotificationGateway {
  Future<Map<String, Object?>> page(
    TenantContext scope,
    String resource, {
    String? after,
  });
  Future<Map<String, Object?>> execute(
    String operation,
    CommandEnvelope<Map<String, Object?>> command,
  );
}

abstract interface class Wave3DiagnosticGateway {
  Future<Map<String, Object?>> diagnostics(TenantContext scope);
}

final class SupabaseWave3NotificationGateway
    implements Wave3NotificationGateway, Wave3DiagnosticGateway {
  SupabaseWave3NotificationGateway(SupabaseClient client)
    : transport = SupabaseControlReconciliationGateway(client);
  final SupabaseControlReconciliationGateway transport;
  static final uuid = RegExp(
    r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
  );
  void identity(Object? value) {
    if (value is! String || !uuid.hasMatch(value)) {
      throw const FormatException('Notification identity is invalid.');
    }
  }

  void scope(Map<String, Object?> row, TenantContext context) {
    if (row['tenant_id'] != context.tenantId ||
        row['legal_entity_id'] != context.legalEntityId ||
        row['branch_id'] != context.branchId) {
      throw const FormatException('Notification scope could not be verified.');
    }
  }

  @override
  Future<Map<String, Object?>> diagnostics(TenantContext context) async {
    final result = await transport.call(
      'wave3_observability_status',
      context,
      {},
    );
    scope(result, context);
    final count = result['dead_letter_depth'], observed = result['observed_at'];
    if (result.length != 5 ||
        count is! String ||
        !RegExp(r'^[0-9]{1,5}$').hasMatch(count) ||
        int.parse(count) > 10000 ||
        observed is! String ||
        DateTime.tryParse(observed) == null) {
      throw const FormatException(
        'Notification queue status could not be verified.',
      );
    }
    return Map.unmodifiable(result);
  }

  @override
  Future<Map<String, Object?>> page(
    TenantContext context,
    String resource, {
    String? after,
  }) async {
    if (!const {'members', 'subscriptions'}.contains(resource)) {
      throw const FormatException('Unsupported notification page.');
    }
    if (after != null) {
      identity(after);
    }
    final result = await transport.call(
      'wave3_notification_admin_page',
      context,
      {'p_resource': resource, 'p_after': after},
    );
    scope(result, context);
    final items = result['items'];
    if (result['resource'] != resource || items is! List || items.length > 50) {
      throw const FormatException('Notification page is invalid.');
    }
    final ids = <String>{};
    for (final raw in items) {
      if (raw is! Map) {
        throw const FormatException('Notification row is invalid.');
      }
      identity(raw['id']);
      if (!ids.add(raw['id'] as String)) {
        throw const FormatException('Duplicate notification identity.');
      }
      if (resource == 'subscriptions') {
        identity(raw['recipient_id']);
        if (!wave3NoticeClasses.contains(raw['event_class']) ||
            raw['enabled'] is! bool ||
            raw['version'] is! int ||
            (raw['version'] as int) < 1) {
          throw const FormatException('Subscription version is invalid.');
        }
      } else if (raw['status'] != 'active') {
        throw const FormatException('Recipient is unavailable.');
      }
    }
    if (result['next_cursor'] != null) {
      identity(result['next_cursor']);
      if (items.isEmpty || (items.last as Map)['id'] != result['next_cursor']) {
        throw const FormatException('Invalid notification cursor.');
      }
    }
    return result;
  }

  @override
  Future<Map<String, Object?>> execute(
    String operation,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    if (!const {'configure', 'scan'}.contains(operation)) {
      throw const FormatException('Unsupported notification action.');
    }
    final p = command.payload;
    if (operation == 'configure') {
      identity(p['id']);
      identity(p['recipient_id']);
      if (!wave3NoticeClasses.contains(p['event_class']) ||
          p['enabled'] is! bool ||
          command.expectedEntityVersion == null) {
        throw const FormatException(
          'Choose a recipient, event and subscription version.',
        );
      }
    } else if (!const {'AR', 'AP'}.contains(p['kind']) ||
        p['as_of'] is! String ||
        DateTime.tryParse(
              p['as_of'] as String,
            )?.toIso8601String().substring(0, 10) !=
            p['as_of'] ||
        command.expectedEntityVersion != null) {
      throw const FormatException('Enter an explicit dated AR/AP scan.');
    }
    final response = await transport.call(
      operation == 'configure'
          ? 'configure_wave3_notification_subscription'
          : 'scan_wave3_due_notifications',
      command.context,
      {
        'p_command_id': command.commandId,
        'p_idempotency_key': command.idempotencyKey,
        'p_client_timestamp': command.clientTimestamp.toIso8601String(),
        'p_expected_entity_version': command.expectedEntityVersion,
        'p_payload': p,
      },
    );
    try {
      identity(response['request_id']);
      if (response['command_id'] != command.commandId ||
          response['entity'] is! Map) {
        throw const FormatException('Unverified receipt.');
      }
      final result = (response['entity'] as Map).cast<String, Object?>();
      scope(result, command.context);
      if (operation == 'configure') {
        if (result['id'] != p['id'] ||
            result['recipient_id'] != p['recipient_id'] ||
            result['event_class'] != p['event_class'] ||
            result['enabled'] != p['enabled'] ||
            result['version'] != command.expectedEntityVersion! + 1) {
          throw const FormatException('Subscription result changed.');
        }
      } else {
        if (result['id'] != command.commandId ||
            result['kind'] != p['kind'] ||
            result['as_of'] != p['as_of'] ||
            result['examined'] is! int ||
            (result['examined'] as int) < 0 ||
            (result['examined'] as int) > 100 ||
            result['emitted'] is! int ||
            (result['emitted'] as int) < 0 ||
            (result['emitted'] as int) > 10000 ||
            result['has_more'] is! bool ||
            (result['has_more'] == false && result['next_after'] != null)) {
          throw const FormatException('Scan completion is invalid.');
        }
        if (result['has_more'] == true) {
          identity(result['next_after']);
        }
      }
      return result;
    } on FormatException {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'Notification action could not be confirmed. Retry the saved request.',
      );
    }
  }
}
