import 'employee.dart';

const maxWorkSeconds = 36 * 60 * 60;
const maxExactWorkInteger = 9007199254740991;

DateTime parseWorkUtc(String input) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$').hasMatch(input)) {
    throw const FormatException('Work time requires whole UTC seconds.');
  }
  final date = CivilDate.parse(input.substring(0, 10));
  final hour = int.parse(input.substring(11, 13));
  final minute = int.parse(input.substring(14, 16));
  final second = int.parse(input.substring(17, 19));
  if (hour > 23 || minute > 59 || second > 59) {
    throw const FormatException('Work time requires whole UTC seconds.');
  }
  return date.utc.add(Duration(hours: hour, minutes: minute, seconds: second));
}

final class WorkSpan {
  WorkSpan(this.startUtc, this.endUtc) {
    if (!startUtc.isUtc ||
        !endUtc.isUtc ||
        startUtc.millisecond != 0 ||
        startUtc.microsecond != 0 ||
        endUtc.millisecond != 0 ||
        endUtc.microsecond != 0 ||
        !endUtc.isAfter(startUtc) ||
        endUtc.difference(startUtc).inSeconds > maxWorkSeconds) {
      throw const FormatException('Work interval is invalid.');
    }
  }

  final DateTime startUtc, endUtc;
  int get seconds => endUtc.difference(startUtc).inSeconds;

  bool overlaps(WorkSpan other) =>
      startUtc.isBefore(other.endUtc) && other.startUtc.isBefore(endUtc);

  bool contains(WorkSpan other) =>
      !other.startUtc.isBefore(startUtc) && !other.endUtc.isAfter(endUtc);
}

final class PayableWork {
  PayableWork(this.span, Iterable<WorkSpan> breaks)
    : breaks = List.unmodifiable(breaks) {
    if (this.breaks.length > 16) {
      throw const FormatException('Too many work breaks.');
    }
    var cursor = span.startUtc;
    var breakSeconds = 0;
    for (final pause in this.breaks) {
      if (!span.contains(pause) || pause.startUtc.isBefore(cursor)) {
        throw const FormatException('Work breaks overlap or are out of order.');
      }
      breakSeconds += pause.seconds;
      cursor = pause.endUtc;
    }
    if (breakSeconds >= span.seconds) {
      throw const FormatException('Work breaks consume the whole interval.');
    }
  }

  final WorkSpan span;
  final List<WorkSpan> breaks;
  int get breakSeconds => breaks.fold(0, (sum, item) => sum + item.seconds);
  int get payableSeconds => span.seconds - breakSeconds;

  List<WorkSpan> get segments {
    final result = <WorkSpan>[];
    var cursor = span.startUtc;
    for (final pause in breaks) {
      if (pause.startUtc.isAfter(cursor)) {
        result.add(WorkSpan(cursor, pause.startUtc));
      }
      cursor = pause.endUtc;
    }
    if (cursor.isBefore(span.endUtc)) {
      result.add(WorkSpan(cursor, span.endUtc));
    }
    return List.unmodifiable(result);
  }
}

void assertExclusiveWork(
  Iterable<WorkSpan> existing,
  Iterable<WorkSpan> proposed,
) {
  final accepted = <WorkSpan>[...existing];
  for (final segment in proposed) {
    if (accepted.any((item) => item.overlaps(segment))) {
      throw const FormatException(
        'A payable work interval already owns this time.',
      );
    }
    accepted.add(segment);
  }
}

/// A grant keeps its original expiry even when a cancellation restores its debit.
final class LeaveGrant {
  LeaveGrant(this.id, this.seconds, String effectiveDate, String expiryDate)
    : effective = CivilDate.parse(effectiveDate),
      expiry = CivilDate.parse(expiryDate) {
    if (id.isEmpty ||
        seconds <= 0 ||
        seconds > maxExactWorkInteger ||
        expiry.compareTo(effective) <= 0) {
      throw const FormatException('Leave grant is invalid.');
    }
  }

  final String id;
  final int seconds;
  final CivilDate effective, expiry;

  bool availableOn(CivilDate date) =>
      effective.compareTo(date) <= 0 && date.compareTo(expiry) < 0;
}

final class LeaveEffect {
  LeaveEffect(
    this.id,
    this.grantId,
    this.seconds,
    this.sourceId, {
    this.reversalOf,
  }) {
    if (id.isEmpty ||
        grantId.isEmpty ||
        sourceId.isEmpty ||
        seconds == 0 ||
        seconds.abs() > maxExactWorkInteger ||
        (reversalOf != null && (reversalOf!.isEmpty || seconds < 0))) {
      throw const FormatException('Leave effect is invalid.');
    }
  }

  final String id, grantId, sourceId;
  final int seconds;
  final String? reversalOf;
}

final class LeaveDebit {
  const LeaveDebit(this.grantId, this.seconds);
  final String grantId;
  final int seconds;
}

final class LeaveLedger {
  LeaveLedger(Iterable<LeaveGrant> grants, Iterable<LeaveEffect> effects)
    : grants = List.unmodifiable(grants),
      effects = List.unmodifiable(effects) {
    if (this.grants.map((item) => item.id).toSet().length !=
            this.grants.length ||
        this.effects.map((item) => item.id).toSet().length !=
            this.effects.length) {
      throw const FormatException('Leave source identities must be unique.');
    }
    final byId = {for (final grant in this.grants) grant.id: grant};
    final effectById = {for (final item in this.effects) item.id: item};
    final reversed = <String>{};
    for (final item in this.effects) {
      if (!byId.containsKey(item.grantId)) {
        throw const FormatException(
          'Leave effect references an unknown grant.',
        );
      }
      if (item.reversalOf != null) {
        final original = effectById[item.reversalOf];
        if (original == null ||
            original.reversalOf != null ||
            original.seconds >= 0 ||
            original.grantId != item.grantId ||
            item.seconds != -original.seconds ||
            !reversed.add(item.reversalOf!)) {
          throw const FormatException(
            'Leave reversal must restore its original debit once.',
          );
        }
      }
    }
    for (final grant in this.grants) {
      final amount =
          BigInt.from(grant.seconds) +
          this.effects
              .where((item) => item.grantId == grant.id)
              .fold(
                BigInt.zero,
                (sum, item) => sum + BigInt.from(item.seconds),
              );
      if (amount < BigInt.zero || amount > BigInt.from(grant.seconds)) {
        throw const FormatException(
          'Leave grant effects exceed its entitlement.',
        );
      }
    }
  }

  final List<LeaveGrant> grants;
  final List<LeaveEffect> effects;

  int availableSeconds(String asOfDate) {
    final date = CivilDate.parse(asOfDate);
    final available = _available(date);
    final total = available.values.fold(
      BigInt.zero,
      (sum, value) => sum + value,
    );
    if (total > BigInt.from(maxExactWorkInteger)) {
      throw const FormatException('Leave balance exceeds exact integer range.');
    }
    return total.toInt();
  }

  List<LeaveDebit> allocate(String asOfDate, int seconds) {
    if (seconds <= 0 || seconds > maxExactWorkInteger) {
      throw const FormatException('Leave request amount is invalid.');
    }
    final date = CivilDate.parse(asOfDate);
    final available = _available(date);
    final ordered = grants.where((grant) => grant.availableOn(date)).toList()
      ..sort((left, right) {
        final expiry = left.expiry.compareTo(right.expiry);
        if (expiry != 0) return expiry;
        final effective = left.effective.compareTo(right.effective);
        return effective != 0 ? effective : left.id.compareTo(right.id);
      });
    var remaining = BigInt.from(seconds);
    final debits = <LeaveDebit>[];
    for (final grant in ordered) {
      final amount = available[grant.id] ?? BigInt.zero;
      if (amount <= BigInt.zero) continue;
      final take = amount < remaining ? amount : remaining;
      debits.add(LeaveDebit(grant.id, take.toInt()));
      remaining -= take;
      if (remaining == BigInt.zero) break;
    }
    if (remaining != BigInt.zero) {
      throw const FormatException('Leave balance is insufficient.');
    }
    return List.unmodifiable(debits);
  }

  Map<String, BigInt> _available(CivilDate date) {
    return {
      for (final grant in grants)
        if (grant.availableOn(date))
          grant.id:
              BigInt.from(grant.seconds) +
              effects
                  .where((item) => item.grantId == grant.id)
                  .fold(
                    BigInt.zero,
                    (sum, item) => sum + BigInt.from(item.seconds),
                  ),
    };
  }
}
