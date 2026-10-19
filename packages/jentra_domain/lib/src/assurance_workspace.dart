// Corporate Audit & Assurance A5: workspace read models.
//
// Mirrors api.assurance_overview and api.assurance_engagements in
// supabase/candidates/20261018210000_assurance_workspace.sql. Parsing fails
// closed: a response that does not match the contract is rejected, never
// partially shown.
import 'assurance.dart';

/// Finding owners respond within this many days of issue (server default).
const assuranceResponseSlaDays = 14;

enum ReminderLevel {
  onTrack('on_track'),
  dueSoon('due_soon'),
  overdue('overdue'),
  escalated('escalated');

  const ReminderLevel(this.wire);
  final String wire;

  static ReminderLevel parse(Object? v) => values.firstWhere(
    (l) => l.wire == v,
    orElse: () => throw const FormatException('Unknown reminder level.'),
  );

  bool get late => this == overdue || this == escalated;
}

/// Same bands as `assurance.reminder_level`: more than [escalateAfterDays]
/// late is escalated, at least a day late overdue, due within [dueSoonDays]
/// (or today) due soon. The defaults are the server defaults.
ReminderLevel assuranceReminderLevel(
  DateTime? due,
  DateTime today, {
  int dueSoonDays = 3,
  int escalateAfterDays = 7,
}) {
  if (due == null) return ReminderLevel.onTrack;
  final d = DateTime.utc(due.year, due.month, due.day);
  final t = DateTime.utc(today.year, today.month, today.day);
  final late = t.difference(d).inDays;
  if (late > escalateAfterDays) return ReminderLevel.escalated;
  if (late >= 1) return ReminderLevel.overdue;
  if (-late <= dueSoonDays) return ReminderLevel.dueSoon;
  return ReminderLevel.onTrack;
}

DateTime _date(Object? v) {
  final s = assuranceDate(v);
  return DateTime.utc(
    int.parse(s.substring(0, 4)),
    int.parse(s.substring(5, 7)),
    int.parse(s.substring(8, 10)),
  );
}

int _count(Object? v) => v is int && v >= 0
    ? v
    : throw const FormatException('A non-negative count is required.');

final class AssuranceWorkItem {
  AssuranceWorkItem.fromJson(
    Map<String, Object?> j,
    DateTime today, {
    int dueSoonDays = 3,
    int escalateAfterDays = 7,
  }) : engagementId = assuranceId(j['engagement_id']),
       engagementName = assuranceText(j['engagement_name'], 3, 160),
       engagementVersion =
           j['engagement_version'] is int &&
               (j['engagement_version'] as int) > 0
           ? j['engagement_version'] as int
           : throw const FormatException('Engagement version required.'),
       kind = switch (j['kind']) {
         'evidence_request' || 'finding' => j['kind'] as String,
         _ => throw const FormatException('Unknown work item kind.'),
       },
       itemId = assuranceId(j['item_id']),
       title = assuranceText(j['title'], 1, 160),
       ownerId = assuranceId(j['owner_id']),
       status = j['status'] is String
           ? j['status'] as String
           : throw const FormatException('Work item status required.'),
       dueDate = j['due_date'] == null ? null : _date(j['due_date']),
       level = ReminderLevel.parse(j['level']) {
    final allowed = kind == 'finding'
        ? const {'issued', 'remediating'}
        : const {'open'};
    if (!allowed.contains(status)) {
      throw const FormatException('Work item status is not open.');
    }
    if (assuranceReminderLevel(
          dueDate,
          today,
          dueSoonDays: dueSoonDays,
          escalateAfterDays: escalateAfterDays,
        ) !=
        level) {
      throw const FormatException('Reminder level does not match due date.');
    }
  }

  final String engagementId;
  final String engagementName;
  final int engagementVersion;
  final String kind;
  final String itemId;
  final String title;
  final String ownerId;
  final String status;
  final DateTime? dueDate;
  final ReminderLevel level;

  /// Only an issued finding owned by the caller can take a response.
  bool canRespond(String actorId) =>
      kind == 'finding' && status == 'issued' && ownerId == actorId;

  /// Only the owner of an open evidence request can upload its evidence.
  bool canSubmitEvidence(String actorId) =>
      kind == 'evidence_request' && status == 'open' && ownerId == actorId;
}

final class AssuranceOverview {
  factory AssuranceOverview.fromJson(Map<String, Object?> j, String actorId) {
    final asOf = _date(j['as_of']);
    final sla = j['response_sla_days'];
    if (sla is! int || sla < 1 || sla > 90) {
      throw const FormatException('Unexpected response SLA.');
    }
    // A9 tenant settings; absent before that candidate is installed.
    final bands = j['reminder_bands'];
    var dueSoon = 3, escalate = 7;
    if (bands != null) {
      if (bands is! Map) throw const FormatException('Invalid reminder bands.');
      final s = bands['due_soon_days'], e = bands['escalate_after_days'];
      if (s is! int || s < 1 || s > 30 || e is! int || e < 1 || e > 90) {
        throw const FormatException('Invalid reminder bands.');
      }
      dueSoon = s;
      escalate = e;
    }
    List<AssuranceWorkItem> list(Object? v) {
      if (v is! List || v.length > 100) {
        throw const FormatException('Invalid work item list.');
      }
      final ids = <String>{};
      return [
        for (final x in v)
          if (x is Map)
            AssuranceWorkItem.fromJson(
              x.cast<String, Object?>(),
              asOf,
              dueSoonDays: dueSoon,
              escalateAfterDays: escalate,
            )
          else
            throw const FormatException('Invalid work item.'),
      ]..forEach((i) {
        if (!ids.add(i.itemId)) {
          throw const FormatException('Duplicate work item.');
        }
      });
    }

    final mine = list(j['mine']), team = list(j['team']);
    if (mine.any((i) => i.ownerId != actorId) ||
        team.any((i) => i.ownerId == actorId || !i.level.late)) {
      throw const FormatException('Work queue does not match the caller.');
    }
    final counts = j['counts'];
    if (counts is! Map) throw const FormatException('Counts required.');
    final all = [...mine, ...team];
    for (final level in [
      ReminderLevel.dueSoon,
      ReminderLevel.overdue,
      ReminderLevel.escalated,
    ]) {
      if (_count(counts[level.wire]) !=
          all.where((i) => i.level == level).length) {
        throw const FormatException('Counts do not match the work items.');
      }
    }
    return AssuranceOverview._(asOf, mine, team, sla, dueSoon, escalate);
  }

  AssuranceOverview._(
    this.asOf,
    this.mine,
    this.team,
    this.responseSlaDays,
    this.dueSoonDays,
    this.escalateAfterDays,
  );

  final DateTime asOf;

  /// The effective tenant settings the levels were computed with.
  final int responseSlaDays;
  final int dueSoonDays;
  final int escalateAfterDays;
  final List<AssuranceWorkItem> mine;
  final List<AssuranceWorkItem> team;

  int count(ReminderLevel level) =>
      [...mine, ...team].where((i) => i.level == level).length;
}

final class AssuranceEngagementSummary {
  AssuranceEngagementSummary.fromJson(Map<String, Object?> j)
    : id = assuranceId(j['id']),
      name = assuranceText(j['name'], 3, 160),
      status = EngagementStatus.parse(j['status']),
      version = j['version'] is int && (j['version'] as int) > 0
          ? j['version'] as int
          : throw const FormatException('Engagement version required.'),
      periodStart = _date(j['period_start']),
      periodEnd = _date(j['period_end']),
      evidenceFrozen = j['evidence_frozen'] is bool
          ? j['evidence_frozen'] as bool
          : throw const FormatException('Freeze state required.'),
      openRequests = _count(j['open_requests']),
      overdueRequests = _count(j['overdue_requests']),
      openFindings = _count(j['open_findings']),
      overdueFindings = _count(j['overdue_findings']),
      candidateExceptions = _count(j['candidate_exceptions']) {
    if (periodEnd.isBefore(periodStart) ||
        overdueRequests > openRequests ||
        overdueFindings > openFindings) {
      throw const FormatException('Inconsistent engagement summary.');
    }
  }

  final String id;
  final String name;
  final EngagementStatus status;
  final int version;
  final DateTime periodStart;
  final DateTime periodEnd;
  final bool evidenceFrozen;
  final int openRequests;
  final int overdueRequests;
  final int openFindings;
  final int overdueFindings;
  final int candidateExceptions;
}

/// A page of the engagement register; the cursor is the last id of a full page.
final class AssuranceEngagementPage {
  factory AssuranceEngagementPage.fromJson(Map<String, Object?> j) {
    final items = j['items'];
    if (items is! List || items.length > 50) {
      throw const FormatException('Invalid engagement page.');
    }
    final parsed = [
      for (final x in items)
        if (x is Map)
          AssuranceEngagementSummary.fromJson(x.cast<String, Object?>())
        else
          throw const FormatException('Invalid engagement.'),
    ];
    for (var i = 1; i < parsed.length; i++) {
      if (parsed[i - 1].id.compareTo(parsed[i].id) >= 0) {
        throw const FormatException('Engagement page is not ordered.');
      }
    }
    final cursor = j['next_cursor'];
    if (cursor != null && (parsed.length != 50 || cursor != parsed.last.id)) {
      throw const FormatException('Invalid engagement cursor.');
    }
    return AssuranceEngagementPage._(parsed, cursor as String?);
  }

  AssuranceEngagementPage._(this.items, this.nextCursor);

  final List<AssuranceEngagementSummary> items;
  final String? nextCursor;
}
