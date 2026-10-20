// Corporate Audit & Assurance A10: reminder scan receipt
// (api.assurance_scan_reminders, candidate API).
import 'assurance.dart';

typedef ReminderScan = ({
  int examined,
  int emitted,
  bool hasMore,
  String? nextAfter,
});

/// A scan examines at most 100 items; a further page needs a cursor.
ReminderScan assuranceReminderScanFromJson(Map<String, Object?> j) {
  final examined = j['examined'], emitted = j['emitted'], more = j['has_more'];
  if (examined is! int || examined < 0 || examined > 100) {
    throw const FormatException('Invalid examined count.');
  }
  if (emitted is! int || emitted < 0) {
    throw const FormatException('Invalid emitted count.');
  }
  if (more is! bool) throw const FormatException('Paging flag required.');
  final next = j['next_after'] == null ? null : assuranceId(j['next_after']);
  if (more != (next != null)) {
    throw const FormatException('Paging cursor does not match.');
  }
  return (examined: examined, emitted: emitted, hasMore: more, nextAfter: next);
}
