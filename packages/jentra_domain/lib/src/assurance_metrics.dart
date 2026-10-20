// Corporate Audit & Assurance A11: process metrics (api.assurance_metrics,
// candidate API; blueprint 68 §9). A metric with no samples is "not
// measured" (null), never zero; parsing rejects any other combination.
import 'assurance.dart';

typedef Measured = ({double? value, int samples});
typedef Spread = ({double? p50, double? p90, int samples});

extension MeasuredState on Measured {
  bool get measured => samples > 0;
}

extension SpreadState on Spread {
  bool get measured => samples > 0;
}

final class AssuranceMetrics {
  AssuranceMetrics.fromJson(Map<String, Object?> j)
    : from = _date(j['from']),
      to = _date(j['to']),
      engagements = _count(j['engagements']),
      stages = {
        for (final s in const ['planning', 'fieldwork', 'reporting'])
          s: _spread(_metrics(j)['stage_${s}_days']),
      },
      evidenceWaiting = _spread(_metrics(j)['evidence_waiting_days']),
      evidenceReview = _spread(_metrics(j)['evidence_review_days']),
      reportIssuance = _spread(_metrics(j)['report_issuance_days']),
      firstTimeRight = _rate(_metrics(j)['evidence_first_time_right']),
      testCompletion = _rate(_metrics(j)['test_completion']),
      controlCoverage = _rate(_metrics(j)['control_coverage']),
      retestPassRate = _rate(_metrics(j)['retest_pass_rate']),
      recurrence = _rate(_metrics(j)['recurrence'], max: double.infinity),
      requestAgeing = _ageing(_metrics(j)['request_ageing']),
      findingAgeing = {
        for (final s in AssuranceSeverity.values)
          s: _rate(
            _map(_metrics(j)['finding_ageing_days'])[s.name],
            max: double.infinity,
          ),
      },
      overdueRemediation = _count(
        _map(_metrics(j)['overdue_remediation'])['value'],
      ),
      openHighRisk = _count(
        _map(_metrics(j)['open_high_risk_findings'])['value'],
      ),
      workload = [
        for (final w in _list(_metrics(j)['workload']))
          (
            label: _label(_map(w)['label']),
            openRequests: _count(_map(w)['open_requests']),
            openFindings: _count(_map(w)['open_findings']),
          ),
      ] {
    if (to.isBefore(from)) throw const FormatException('Range is reversed.');
    if (workload.length > 10) {
      throw const FormatException('Workload is limited to ten people.');
    }
  }

  final DateTime from;
  final DateTime to;
  final int engagements;
  final Map<String, Spread> stages;
  final Spread evidenceWaiting;
  final Spread evidenceReview;
  final Spread reportIssuance;
  final Measured firstTimeRight;
  final Measured testCompletion;
  final Measured controlCoverage;
  final Measured retestPassRate;
  final Measured recurrence;
  final ({int d0to7, int d8to30, int d31plus, int samples}) requestAgeing;
  final Map<AssuranceSeverity, Measured> findingAgeing;
  final int overdueRemediation;
  final int openHighRisk;
  final List<({String label, int openRequests, int openFindings})> workload;

  static Map<String, Object?> _metrics(Map<String, Object?> j) =>
      _map(j['metrics']);

  static Spread _spread(Object? v) {
    final m = _map(v);
    final n = _count(m['samples']);
    final p50 = _number(m['p50']), p90 = _number(m['p90']);
    if ((n == 0) != (p50 == null) || (n == 0) != (p90 == null)) {
      throw const FormatException('A duration needs samples to be measured.');
    }
    if (p50 != null && (p50 < 0 || p90! < p50)) {
      throw const FormatException('Percentiles are out of order.');
    }
    return (p50: p50, p90: p90, samples: n);
  }

  static Measured _rate(Object? v, {double max = 1}) {
    final m = _map(v);
    final n = _count(m['samples']);
    final value = _number(m['value']);
    if ((n == 0) != (value == null)) {
      throw const FormatException('A rate needs samples to be measured.');
    }
    if (value != null && (value < 0 || value > max)) {
      throw const FormatException('Rate out of range.');
    }
    return (value: value, samples: n);
  }

  static ({int d0to7, int d8to30, int d31plus, int samples}) _ageing(
    Object? v,
  ) {
    final m = _map(v);
    final a = _count(m['d0_7']), b = _count(m['d8_30']);
    final c = _count(m['d31_plus']), n = _count(m['samples']);
    if (a + b + c != n) throw const FormatException('Ageing does not add up.');
    return (d0to7: a, d8to30: b, d31plus: c, samples: n);
  }

  static String _label(Object? v) {
    final s = assuranceText(v, 1, 160);
    if (s.contains('@')) {
      throw const FormatException('Workload labels must not be e-mails.');
    }
    return s;
  }
}

Map<String, Object?> _map(Object? v) {
  if (v is Map<String, Object?>) return v;
  if (v is Map) return v.cast<String, Object?>();
  throw const FormatException('Object expected.');
}

List<Object?> _list(Object? v) =>
    v is List ? v : throw const FormatException('List expected.');

int _count(Object? v) => v is int && v >= 0
    ? v
    : throw const FormatException('A non-negative count is required.');

double? _number(Object? v) => switch (v) {
  null => null,
  final num n => n.toDouble(),
  _ => throw const FormatException('Number expected.'),
};

DateTime _date(Object? v) {
  final s = assuranceDate(v);
  return DateTime.utc(
    int.parse(s.substring(0, 4)),
    int.parse(s.substring(5, 7)),
    int.parse(s.substring(8, 10)),
  );
}
