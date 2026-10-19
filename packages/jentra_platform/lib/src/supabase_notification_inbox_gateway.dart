import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// The signed-in user's in-app notices (`api.my_notifications`, row-level
/// security limits them to the recipient).
abstract interface class NotificationInboxGateway {
  Future<List<InboxNotice>> latest(String tenantId, {int limit = 20});

  /// Unread notices, counted up to 100 (shown as "99+" beyond that).
  Future<int> unreadCount(String tenantId);
  Future<void> markRead(String tenantId, InboxNotice notice);
}

final class SupabaseNotificationInboxGateway
    implements NotificationInboxGateway {
  SupabaseNotificationInboxGateway(this.client);
  final SupabaseClient client;
  static const _uuid = Uuid();

  @override
  Future<List<InboxNotice>> latest(String tenantId, {int limit = 20}) async {
    final rows = await client
        .schema('api')
        .from('my_notifications')
        .select()
        .eq('tenant_id', tenantId)
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit);
    return [for (final r in rows) InboxNotice.fromJson(r)];
  }

  @override
  Future<int> unreadCount(String tenantId) async {
    final rows = await client
        .schema('api')
        .from('my_notifications')
        .select('id')
        .eq('tenant_id', tenantId)
        .eq('status', 'unread')
        .limit(100);
    return rows.length;
  }

  @override
  Future<void> markRead(String tenantId, InboxNotice notice) async {
    try {
      await client
          .schema('api')
          .rpc(
            'mark_notification_read',
            params: {
              'p_tenant_id': tenantId,
              'p_notification_id': notice.id,
              'p_expected_version': notice.version,
              'p_idempotency_key': _uuid.v4(),
            },
          );
    } on PostgrestException catch (e) {
      throw DomainError(
        code: switch (e.code) {
          '40001' => 'VERSION_CONFLICT',
          '42501' => 'PERMISSION_DENIED',
          _ => 'UNCERTAIN_RESULT',
        },
        message: switch (e.code) {
          '40001' => 'This notice changed. The list has been refreshed.',
          '42501' => 'Notices are not available for this account here.',
          _ => 'The notice could not be updated. Try again.',
        },
      );
    }
  }
}
