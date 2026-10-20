import 'package:jentra_domain/jentra_assurance.dart';
import 'package:test/test.dart';

Map<String, Object?> spread(double? p50, double? p90, int n) => {
  'p50': p50,
  'p90': p90,
  'samples': n,
};
Map<String, Object?> rate(double? v, int n) => {'value': v, 'samples': n};

Map<String, Object?> metrics({Map<String, Object?> change = const {}}) => {
  'from': '2026-01-01',
  'to': '2026-03-31',
  'engagements': 2,
  'metrics': {
    'stage_planning_days': spread(2, 4, 2),
    'stage_fieldwork_days': spread(10, 10, 1),
    'stage_reporting_days': spread(2.5, 2.5, 1),
    'report_issuance_days': spread(2.5, 2.5, 1),
    'evidence_waiting_days': spread(2, 4, 2),
    'evidence_review_days': spread(1, 2, 2),
    'evidence_first_time_right': rate(0.5, 2),
    'request_ageing': {'d0_7': 1, 'd8_30': 0, 'd31_plus': 1, 'samples': 2},
    'test_completion': rate(0.5, 2),
    'control_coverage': rate(0.5, 2),
    'retest_pass_rate': rate(0.5, 2),
    'recurrence': rate(0.3333, 3),
    'finding_ageing_days': {
      'low': rate(null, 0),
      'medium': rate(null, 0),
      'high': rate(10, 1),
      'critical': rate(6, 1),
    },
    'overdue_remediation': {'value': 1},
    'open_high_risk_findings': {'value': 2},
    'workload': [
      {'label': 'Nadeesha Perera', 'open_requests': 2, 'open_findings': 1},
      {
        'label': 'Unlinked member ····0042',
        'open_requests': 0,
        'open_findings': 1,
      },
    ],
    ...change,
  },
};

void main() {
  test('every metric is parsed with its sample count', () {
    final m = AssuranceMetrics.fromJson(metrics());
    expect(m.from, DateTime.utc(2026, 1, 1));
    expect(m.engagements, 2);
    expect(m.stages['planning']!.p50, 2);
    expect(m.stages['planning']!.p90, 4);
    expect(m.stages['fieldwork']!.samples, 1);
    expect(m.evidenceReview.p90, 2);
    expect(m.firstTimeRight.value, 0.5);
    expect(m.recurrence.samples, 3);
    expect(m.requestAgeing.d31plus, 1);
    expect(m.findingAgeing[AssuranceSeverity.low]!.value, isNull);
    expect(m.findingAgeing[AssuranceSeverity.high]!.value, 10);
    expect(m.overdueRemediation, 1);
    expect(m.openHighRisk, 2);
    expect(m.workload.first.label, 'Nadeesha Perera');
    expect(m.workload.first.openRequests, 2);
  });

  test('a value without samples or samples without a value fail closed', () {
    for (final bad in [
      {'evidence_first_time_right': rate(0, 0)},
      {'evidence_first_time_right': rate(null, 3)},
      {'stage_planning_days': spread(2, null, 2)},
      {'stage_planning_days': spread(5, 4, 2)},
      {'test_completion': rate(1.5, 2)},
      {
        'workload': [
          {
            'label': 'someone@example.com',
            'open_requests': 1,
            'open_findings': 0,
          },
        ],
      },
      {
        'request_ageing': {'d0_7': 1, 'd8_30': 0, 'd31_plus': 0, 'samples': 2},
      },
    ]) {
      expect(
        () => AssuranceMetrics.fromJson(metrics(change: bad)),
        throwsFormatException,
        reason: '$bad',
      );
    }
  });

  test('an empty period is measured as nothing, not zero', () {
    final m = AssuranceMetrics.fromJson(
      metrics(
        change: {
          'stage_planning_days': spread(null, null, 0),
          'evidence_first_time_right': rate(null, 0),
          'workload': <Object?>[],
        },
      ),
    );
    expect(m.stages['planning']!.p50, isNull);
    expect(m.stages['planning']!.measured, isFalse);
    expect(m.firstTimeRight.measured, isFalse);
    expect(m.workload, isEmpty);
  });

  test('the nearest-rank reference agrees with the server', () {
    expect(
      assurancePercentile([
        const Duration(days: 4),
        const Duration(days: 2),
      ], 50),
      const Duration(days: 2),
    );
    expect(
      assurancePercentile([
        const Duration(days: 4),
        const Duration(days: 2),
      ], 90),
      const Duration(days: 4),
    );
  });
}
