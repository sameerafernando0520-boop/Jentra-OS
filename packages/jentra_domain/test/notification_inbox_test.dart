import 'package:jentra_domain/jentra_assurance.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:test/test.dart';

String uid(int n) => '85000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';

Map<String, Object?> notice({
  String type = 'assurance.reminder',
  String? aggregateType = 'assurance_engagement',
  String? aggregateId,
  String status = 'unread',
  Object? version = 1,
}) => {
  'id': uid(1),
  'tenant_id': uid(2),
  'notification_type': type,
  'title': 'Evidence request overdue',
  'body': 'Treasury review: an evidence request is overdue.',
  'aggregate_type': aggregateType,
  'aggregate_id': aggregateType == null ? null : (aggregateId ?? uid(3)),
  'status': status,
  'read_at': status == 'read' ? '2026-10-20T08:00:00Z' : null,
  'version': version,
  'created_at': '2026-10-20T07:30:00Z',
};

void main() {
  test('a reminder notice links to its engagement', () {
    final n = InboxNotice.fromJson(notice());
    expect(n.unread, isTrue);
    expect(n.title, 'Evidence request overdue');
    expect(n.engagementId, uid(3));
    expect(n.createdAt, DateTime.utc(2026, 10, 20, 7, 30));
  });

  test('other notices carry no engagement link', () {
    final n = InboxNotice.fromJson(
      notice(type: 'wave3.due', aggregateType: 'sales_invoice', status: 'read'),
    );
    expect(n.unread, isFalse);
    expect(n.engagementId, isNull);
    expect(
      InboxNotice.fromJson(notice(aggregateType: null)).engagementId,
      isNull,
    );
  });

  test('malformed notices fail closed', () {
    for (final bad in [
      notice(status: 'archived'),
      notice(version: 0),
      {...notice(), 'id': 'x'},
      {...notice(), 'title': ''},
      {...notice(), 'created_at': 'yesterday'},
    ]) {
      expect(() => InboxNotice.fromJson(bad), throwsFormatException);
    }
  });

  test('a reminder scan receipt is parsed and bounded', () {
    final r = assuranceReminderScanFromJson({
      'examined': 100,
      'emitted': 7,
      'has_more': true,
      'next_after': uid(9),
    });
    expect(r.examined, 100);
    expect(r.emitted, 7);
    expect(r.hasMore, isTrue);
    expect(r.nextAfter, uid(9));
    final last = assuranceReminderScanFromJson({
      'examined': 1,
      'emitted': 0,
      'has_more': false,
      'next_after': null,
    });
    expect(last.nextAfter, isNull);
    for (final bad in [
      {'examined': 101, 'emitted': 0, 'has_more': false, 'next_after': null},
      {'examined': 5, 'emitted': -1, 'has_more': false, 'next_after': null},
      {'examined': 5, 'emitted': 0, 'has_more': true, 'next_after': null},
    ]) {
      expect(() => assuranceReminderScanFromJson(bad), throwsFormatException);
    }
  });
}
