import 'package:jentra_domain/jentra_assurance.dart';
import 'package:test/test.dart';

String uid(int n) => '83000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';

Map<String, Object?> monitoring([Map<String, Object?> overrides = const {}]) =>
    {
      for (final c in assuranceMonitoringRuleCodes)
        c: {'enabled': true, 'min_count': 1},
      ...overrides,
    };

Map<String, Object?> effective({
  String source = 'tenant',
  int due = 5,
  int esc = 10,
  int resp = 21,
  Map<String, Object?> bands = const {'critical': 20, 'high': 12, 'medium': 6},
  Map<String, Object?>? mon,
}) => {
  'source': source,
  'due_soon_days': due,
  'escalate_after_days': esc,
  'finding_response_days': resp,
  'rating_bands': bands,
  'monitoring': mon ?? monitoring(),
};

Map<String, Object?> payload([Map<String, Object?> change = const {}]) => {
  'level': 'tenant',
  'due_soon_days': 5,
  'escalate_after_days': 10,
  'finding_response_days': 21,
  'rating_bands': {'critical': 20, 'high': 12, 'medium': 6},
  'monitoring': monitoring(),
  ...change,
};

void main() {
  final today = DateTime.utc(2026, 10, 20);
  DateTime day(int d) => today.add(Duration(days: d));

  test('defaults reproduce the installed behaviour', () {
    final d = AssuranceSettings.defaults;
    expect(d.source, 'default');
    expect(
      [d.dueSoonDays, d.escalateAfterDays, d.findingResponseDays],
      [3, 7, 14],
    );
    for (var s = 1; s <= 25; s++) {
      final l = s <= 5 ? s : 5, i = (s / l).ceil();
      if (l * i != s) continue;
      expect(d.bands.rate(s), assuranceRiskRating(l, i));
    }
    for (final x in [7, 4, 3, 0, -1, -7, -8]) {
      expect(d.level(day(x), today), assuranceReminderLevel(day(x), today));
    }
    expect(d.monitoring.keys, assuranceMonitoringRuleCodes);
  });

  test('custom bands and reminder days change ratings and levels', () {
    final s = AssuranceSettings.fromJson(effective());
    expect(s.bands.rate(10), AssuranceSeverity.medium);
    expect(s.bands.rate(12), AssuranceSeverity.high);
    expect(assuranceRiskRating(2, 5, bands: s.bands), AssuranceSeverity.medium);
    expect(
      [
        for (final x in [6, 5, 0, -1, -10, -11]) s.level(day(x), today).wire,
      ],
      ['on_track', 'due_soon', 'due_soon', 'overdue', 'overdue', 'escalated'],
    );
  });

  test('escalation shorter than the due-soon window still orders levels', () {
    final s = AssuranceSettings.fromJson(effective(due: 10, esc: 2));
    expect(s.level(day(9), today), ReminderLevel.dueSoon);
    expect(s.level(day(-2), today), ReminderLevel.overdue);
    expect(s.level(day(-3), today), ReminderLevel.escalated);
  });

  test('the settings page parses both row versions and the rules', () {
    final p = AssuranceSettingsPage.fromJson({
      'effective': effective(source: 'entity'),
      'tenant': {'version': 2, 'updated_at': '2026-10-20T00:00:00Z'},
      'entity': null,
      'rules': [
        for (final c in assuranceMonitoringRuleCodes)
          {'code': c, 'description': 'Rule $c'},
      ],
    });
    expect(p.effective.source, 'entity');
    expect(p.tenantVersion, 2);
    expect(p.entityVersion, isNull);
    expect(p.rules.map((r) => r.code), assuranceMonitoringRuleCodes);
  });

  test('malformed settings fail closed', () {
    for (final bad in [
      effective(due: 0),
      effective(esc: 91),
      effective(bands: {'critical': 10, 'high': 12, 'medium': 6}),
      effective(
        mon: monitoring({
          'UNKNOWN': {'enabled': true, 'min_count': 1},
        }),
      ),
      effective(
        mon: monitoring({
          'P2P_MATCH_OVERRIDE': {'enabled': 'yes', 'min_count': 1},
        }),
      ),
      {...effective(), 'source': 'branch'},
    ]) {
      expect(() => AssuranceSettings.fromJson(bad), throwsFormatException);
    }
  });

  test('commands carry exactly the settings fields within range', () {
    expect(AssuranceSettingsCommands.fields, [
      'level',
      'due_soon_days',
      'escalate_after_days',
      'finding_response_days',
      'rating_bands',
      'monitoring',
    ]);
    AssuranceSettingsCommands.validate(payload());
    AssuranceSettingsCommands.validate(payload({'level': 'entity'}));
    for (final bad in [
      payload({'extra': 1}),
      payload({'level': 'branch'}),
      payload({'due_soon_days': 31}),
      payload({'finding_response_days': '14'}),
      payload({
        'rating_bands': {'critical': 20, 'high': 20, 'medium': 6},
      }),
      payload({
        'monitoring': monitoring({
          'HR_ATTENDANCE_SELF_APPROVAL': {'enabled': true, 'min_count': 0},
        }),
      }),
    ]) {
      expect(
        () => AssuranceSettingsCommands.validate(bad),
        throwsFormatException,
        reason: '$bad',
      );
    }
    expect(
      AssuranceSettings.fromJson(effective()).toPayload('tenant'),
      payload(),
    );
  });

  test('a settings receipt confirms only the same level one version later', () {
    final r = {'level': 'tenant', 'version': 3, 'effective': effective()};
    expect(assuranceSettingsReceiptConfirms(r, 'tenant', 2), isTrue);
    expect(assuranceSettingsReceiptConfirms(r, 'entity', 2), isFalse);
    expect(assuranceSettingsReceiptConfirms(r, 'tenant', 3), isFalse);
  });

  test('an approved plan can be revised once into a draft', () {
    expect(PlanStatus.approved.next, {PlanStatus.superseded});
    expect(PlanStatus.superseded.next, isEmpty);
    expect(PlanStatus.parse('superseded'), PlanStatus.superseded);
    expect(AssurancePlanCommands.creates('supersede_plan'), isTrue);
    expect(
      AssurancePlanCommands.capability('supersede_plan'),
      'assurance.plan.manage',
    );
    final p = {
      'action': 'supersede_plan',
      'plan_id': uid(1),
      'supersedes_plan_id': uid(2),
      'name': 'FY27 plan (revised)',
    };
    AssurancePlanCommands.validate('supersede_plan', p);
    expect(
      () =>
          AssurancePlanCommands.validate('supersede_plan', {...p, 'name': 'x'}),
      throwsFormatException,
    );
  });

  test(
    'the overview accepts tenant deadlines and verifies levels with them',
    () {
      final o = AssuranceOverview.fromJson({
        'as_of': '2026-10-20',
        'response_sla_days': 30,
        'reminder_bands': {'due_soon_days': 5, 'escalate_after_days': 10},
        'mine': [
          {
            'engagement_id': uid(3),
            'engagement_name': 'Payroll review',
            'engagement_version': 4,
            'kind': 'evidence_request',
            'item_id': uid(4),
            'title': 'Payroll register',
            'owner_id': uid(5),
            'status': 'open',
            'due_date': '2026-10-25',
            'level': 'due_soon',
          },
        ],
        'team': <Object?>[],
        'counts': {'due_soon': 1, 'overdue': 0, 'escalated': 0},
      }, uid(5));
      expect(o.responseSlaDays, 30);
      expect(o.dueSoonDays, 5);
      expect(o.escalateAfterDays, 10);
    },
  );
}
