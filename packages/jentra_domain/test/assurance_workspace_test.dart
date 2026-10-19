import 'package:jentra_domain/jentra_assurance.dart';
import 'package:test/test.dart';

String uid(int n) => '70000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
final me = uid(1), other = uid(2);
const today = '2026-10-18';

Map<String, Object?> item(
  int n, {
  String kind = 'evidence_request',
  String? owner,
  String status = 'open',
  String? due = '2026-10-20',
  String level = 'due_soon',
}) => {
  'engagement_id': uid(100),
  'engagement_name': 'FY27 Treasury',
  'engagement_version': 9,
  'kind': kind,
  'item_id': uid(n),
  'title': 'Bank mandate evidence',
  'owner_id': owner ?? me,
  'status': status,
  'due_date': due,
  'level': level,
};

Map<String, Object?> overview({
  List<Map<String, Object?>>? mine,
  List<Map<String, Object?>>? team,
  Map<String, Object?>? counts,
}) => {
  'as_of': today,
  'response_sla_days': 14,
  'mine':
      mine ??
      [
        item(10, due: '2026-10-08', level: 'escalated'),
        item(
          11,
          kind: 'finding',
          status: 'issued',
          due: '2026-10-12',
          level: 'overdue',
        ),
        item(12),
      ],
  'team': team ?? [item(13, owner: other, due: '2026-10-15', level: 'overdue')],
  'counts': counts ?? {'due_soon': 1, 'overdue': 2, 'escalated': 1},
};

Map<String, Object?> engagement(int n, {String? id}) => {
  'id': id ?? uid(n),
  'name': 'FY27 Treasury',
  'status': 'fieldwork',
  'version': 4,
  'period_start': '2026-04-01',
  'period_end': '2027-03-31',
  'lead_auditor_id': other,
  'evidence_frozen': false,
  'open_requests': 3,
  'overdue_requests': 2,
  'open_findings': 1,
  'overdue_findings': 1,
  'candidate_exceptions': 0,
};

void main() {
  test('reminder bands mirror the server', () {
    final t = DateTime.utc(2026, 10, 18);
    expect(
      [
        for (final d in [5, 3, 0, -1, -7, -8])
          assuranceReminderLevel(t.add(Duration(days: d)), t).wire,
      ],
      ['on_track', 'due_soon', 'due_soon', 'overdue', 'overdue', 'escalated'],
    );
    expect(assuranceReminderLevel(null, t), ReminderLevel.onTrack);
  });

  test('overview parses work for the caller and only late team items', () {
    final o = AssuranceOverview.fromJson(overview(), me);
    expect(o.mine.map((i) => i.level), [
      ReminderLevel.escalated,
      ReminderLevel.overdue,
      ReminderLevel.dueSoon,
    ]);
    expect(o.count(ReminderLevel.overdue), 2);
    expect(o.mine[1].canRespond(me), isTrue);
    expect(o.mine[0].canRespond(me), isFalse);
    expect(o.team.single.canRespond(me), isFalse);
  });

  test('overview fails closed on inconsistent content', () {
    for (final bad in [
      overview(counts: {'due_soon': 0, 'overdue': 2, 'escalated': 1}),
      overview(
        mine: [item(10, level: 'overdue')],
        counts: {'due_soon': 0, 'overdue': 1, 'escalated': 0},
      ),
      overview(
        team: [item(13, owner: other)],
        counts: {'due_soon': 2, 'overdue': 1, 'escalated': 1},
      ),
      overview(
        mine: [item(10, owner: other)],
        team: [],
        counts: {'due_soon': 1, 'overdue': 0, 'escalated': 0},
      ),
      overview(
        mine: [item(10), item(10)],
        team: [],
        counts: {'due_soon': 2, 'overdue': 0, 'escalated': 0},
      ),
      overview(
        mine: [item(10, status: 'accepted')],
        team: [],
        counts: {'due_soon': 1, 'overdue': 0, 'escalated': 0},
      ),
      {...overview(), 'response_sla_days': 91},
    ]) {
      expect(
        () => AssuranceOverview.fromJson(bad, me),
        throwsFormatException,
        reason: '$bad',
      );
    }
  });

  test('engagement register pages are ordered and bounded', () {
    final page = AssuranceEngagementPage.fromJson({
      'items': [engagement(1), engagement(2)],
      'next_cursor': null,
    });
    expect(page.items.first.overdueRequests, 2);
    expect(page.nextCursor, isNull);
    for (final bad in <Map<String, Object?>>[
      {
        'items': [engagement(2), engagement(1)],
        'next_cursor': null,
      },
      {
        'items': [engagement(1)],
        'next_cursor': uid(1),
      },
      {
        'items': [
          {...engagement(1), 'overdue_requests': 5},
        ],
        'next_cursor': null,
      },
      {
        'items': [
          {...engagement(1), 'status': 'unknown'},
        ],
        'next_cursor': null,
      },
    ]) {
      expect(
        () => AssuranceEngagementPage.fromJson(bad),
        throwsFormatException,
        reason: '$bad',
      );
    }
  });
}
