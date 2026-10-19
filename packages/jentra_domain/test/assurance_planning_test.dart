import 'package:jentra_domain/jentra_assurance.dart';
import 'package:test/test.dart';

String uid(int n) => '60000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';

const controls = [
  {'control_code': 'P2P-3WM', 'title': 'Three-way match', 'risk': 'high'},
  {
    'control_code': 'P2P-VEND',
    'title': 'Vendor master changes',
    'risk': 'medium',
  },
];
const requests = [
  {
    'control_code': 'P2P-3WM',
    'description': 'Match exception report',
    'due_offset_days': 14,
  },
];

void main() {
  test('risk rating bands mirror the server', () {
    final bands = [
      for (final (l, i) in [
        (2, 2),
        (1, 5),
        (3, 3),
        (2, 5),
        (4, 4),
        (5, 4),
        (5, 5),
      ])
        assuranceRiskRating(l, i).name,
    ];
    expect(bands, [
      'low',
      'medium',
      'medium',
      'high',
      'high',
      'critical',
      'critical',
    ]);
    expect(() => assuranceRiskRating(6, 1), throwsFormatException);
    expect(() => assuranceRiskRating(1, 0), throwsFormatException);
  });

  test('occurrence periods split the plan period like the server', () {
    final start = DateTime.utc(2026, 4, 1);
    final end = DateTime.utc(2027, 3, 31);
    final q2 = assuranceOccurrencePeriod(start, end, 4, 2);
    expect(q2.start, DateTime.utc(2026, 7, 1));
    expect(q2.end, DateTime.utc(2026, 9, 29));
    final parts = [
      for (var k = 1; k <= 12; k++)
        assuranceOccurrencePeriod(start, end, 12, k),
    ];
    expect(parts.first.start, start);
    expect(parts.last.end, end);
    for (var k = 1; k < parts.length; k++) {
      expect(parts[k].start, parts[k - 1].end.add(const Duration(days: 1)));
    }
    expect(
      () => assuranceOccurrencePeriod(start, end, 4, 5),
      throwsFormatException,
    );
    expect(AuditFrequency.parse('quarterly').occurrences, 4);
    expect(() => AuditFrequency.parse('weekly'), throwsFormatException);
  });

  test('plan approval is final and maker-checker gated by MFA', () {
    expect(PlanStatus.submitted.next, {
      PlanStatus.approved,
      PlanStatus.draft,
      PlanStatus.cancelled,
    });
    expect(PlanStatus.approved.next, {PlanStatus.superseded});
    expect(AssurancePlanCommands.requiresRecentMfa('decide_plan'), isTrue);
    expect(AssurancePlanCommands.requiresRecentMfa('submit_plan'), isFalse);
    expect(
      AssurancePlanCommands.capability('instantiate_engagement'),
      'assurance.engagement.manage',
    );
    expect(AssurancePlanCommands.creates('create_plan'), isTrue);
    expect(AssurancePlanCommands.creates('add_plan_item'), isFalse);
  });

  test('templates are exact allow-lists', () {
    expect(assuranceTemplateValid(controls, requests), isTrue);
    expect(assuranceTemplateValid(controls, const []), isTrue);
    for (final (c, r) in <(Object?, Object?)>[
      (const [], requests),
      (
        [
          {...controls.first, 'owner_id': uid(1)},
        ],
        const [],
      ),
      ([controls.first, controls.first], const []),
      (
        controls,
        [
          {...requests.first, 'control_code': 'P2P-XX'},
        ],
      ),
      (
        controls,
        [
          {...requests.first, 'due_offset_days': 400},
        ],
      ),
      (controls, null),
    ]) {
      expect(assuranceTemplateValid(c, r), isFalse, reason: '$c $r');
    }
  });

  test('plan commands validate payloads before sending', () {
    final add = {
      'action': 'add_plan_item',
      'plan_id': uid(1),
      'plan_item_id': uid(2),
      'item_id': uid(3),
      'frequency': 'quarterly',
      'template_id': null,
      'lead_auditor_id': uid(4),
      'scope_summary': 'Design and operating effectiveness',
    };
    AssurancePlanCommands.validate('add_plan_item', add);
    AssurancePlanCommands.validate('create_template', {
      'action': 'create_template',
      'template_id': uid(5),
      'code': 'P2P-STD',
      'name': 'Procure to pay standard',
      'controls': controls,
      'requests': requests,
    });
    for (final (action, payload) in <(String, Map<String, Object?>)>[
      ('add_plan_item', {...add, 'frequency': 'weekly'}),
      ('add_plan_item', {...add, 'rating': 'low'}),
      (
        'assess_risk',
        {
          'action': 'assess_risk',
          'item_id': uid(3),
          'assessment_id': uid(6),
          'likelihood': 6,
          'impact': 1,
          'rationale': 'Workshop',
        },
      ),
      (
        'create_plan',
        {
          'action': 'create_plan',
          'plan_id': uid(1),
          'name': 'FY27 plan',
          'period_start': '2027-03-31',
          'period_end': '2026-04-01',
        },
      ),
      (
        'decide_plan',
        {
          'action': 'decide_plan',
          'plan_id': uid(1),
          'decision': 'reject',
          'reason': 'Not covered',
        },
      ),
      (
        'instantiate_engagement',
        {
          'action': 'instantiate_engagement',
          'plan_id': uid(1),
          'plan_item_id': uid(2),
          'occurrence': 13,
          'engagement_id': uid(7),
        },
      ),
    ]) {
      expect(
        () => AssurancePlanCommands.validate(action, payload),
        throwsFormatException,
        reason: '$action $payload',
      );
    }
  });
}
