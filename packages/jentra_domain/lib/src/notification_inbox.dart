// In-app notices for the signed-in user (api.my_notifications). Parsing fails
// closed: a malformed notice is rejected, never partially shown.

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

final class InboxNotice {
  InboxNotice.fromJson(Map<String, Object?> j)
    : id = _id(j['id']),
      type = _text(j['notification_type'], 80),
      title = _text(j['title'], 160),
      body = _text(j['body'], 4000),
      aggregateType = j['aggregate_type'] == null
          ? null
          : _text(j['aggregate_type'], 80),
      aggregateId = j['aggregate_id'] == null ? null : _id(j['aggregate_id']),
      unread = switch (j['status']) {
        'unread' => true,
        'read' => false,
        _ => throw const FormatException('Unknown notice status.'),
      },
      version = j['version'] is int && (j['version'] as int) > 0
          ? j['version'] as int
          : throw const FormatException('Notice version required.'),
      createdAt = _time(j['created_at']) {
    if ((aggregateType == null) != (aggregateId == null)) {
      throw const FormatException('Notice link is incomplete.');
    }
  }

  final String id;
  final String type;
  final String title;
  final String body;
  final String? aggregateType;
  final String? aggregateId;
  final bool unread;
  final int version;
  final DateTime createdAt;

  /// The engagement an audit reminder points at, if any.
  String? get engagementId =>
      aggregateType == 'assurance_engagement' ? aggregateId : null;

  static String _id(Object? v) => v is String && _uuid.hasMatch(v)
      ? v
      : throw const FormatException('A lowercase UUID is required.');

  static String _text(Object? v, int max) =>
      v is String && v.trim().isNotEmpty && v.length <= max
      ? v
      : throw const FormatException('Notice text is required.');

  static DateTime _time(Object? v) {
    final t = v is String ? DateTime.tryParse(v) : null;
    if (t == null) throw const FormatException('Notice time is required.');
    return t.toUtc();
  }
}
