import 'package:jentra_domain/jentra_assurance.dart';
import 'package:test/test.dart';

String uid(int n) => '72000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
final me = uid(1), maker = uid(2), owner = uid(3), plan = uid(10);

Map<String, Object?> universe() => {
  'items': [
    {
      'id': uid(20),
      'code': 'P2P',
      'name': 'Procure to pay',
      'category': 'process',
      'owner_id': owner,
      'status': 'active',
      'version': 3,
      'assessment': {'rating': 'critical', 'score': 20},
    },
    {
      'id': uid(21),
      'code': 'NEWPROC',
      'name': 'New process',
      'category': 'process',
      'owner_id': me,
      'status': 'active',
      'version': 1,
      'assessment': null,
    },
    {
      'id': uid(22),
      'code': 'OLD',
      'name': 'Retired area',
      'category': 'system',
      'owner_id': owner,
      'status': 'retired',
      'version': 4,
      'assessment': {'rating': 'low', 'score': 2},
    },
  ],
  'templates': [
    {'id': uid(30), 'code': 'P2P-STD', 'version': 1, 'name': 'P2P v1'},
    {'id': uid(31), 'code': 'P2P-STD', 'version': 2, 'name': 'P2P v2'},
  ],
};

Map<String, Object?> detail({
  String status = 'draft',
  String? submittedBy,
  List<Map<String, Object?>>? items,
}) => {
  'plan': {
    'id': plan,
    'name': 'FY27 internal audit plan',
    'status': status,
    'version': 5,
    'period_start': '2026-04-01',
    'period_end': '2027-03-31',
    'created_by': maker,
    'submitted_by': submittedBy,
    'approved_digest': null,
  },
  'items':
      items ??
      [
        {
          'id': uid(40),
          'universe_item_id': uid(20),
          'code': 'P2P',
          'name': 'Procure to pay',
          'rating': 'critical',
          'frequency': 'quarterly',
          'template_id': uid(31),
          'lead_auditor_id': me,
          'status': 'active',
          'occurrences': [
            {'occurrence': 1, 'engagement_id': uid(50)},
          ],
        },
      ],
  'uncovered_high_risk': [
    {'item_id': uid(23), 'code': 'ITGC', 'rating': 'high'},
  ],
};

const manage = {'assurance.plan.manage', 'assurance.engagement.manage'};

void main() {
  test('universe parses ratings, status and current templates', () {
    final u = AssuranceUniverse.fromJson(universe());
    expect(u.items.first.rating, AssuranceSeverity.critical);
    expect(u.items[1].rating, isNull);
    expect(u.items[2].active, isFalse);
    expect(u.currentTemplates.single.version, 2);
    expect(u.canAssess(manage, u.items.first, me), isTrue);
    expect(u.canAssess(manage, u.items[1], me), isFalse);
    expect(u.canRetire(manage, u.items[2]), isFalse);
    expect(u.canRegister({'assurance.evidence.view'}), isFalse);
  });

  test('plannable areas are assessed, active and not already planned', () {
    final d = AssurancePlanDetail.fromJson(detail());
    final u = AssuranceUniverse.fromJson(universe());
    expect(d.plannable(u), isEmpty);
    final empty = AssurancePlanDetail.fromJson(detail(items: []));
    expect(empty.plannable(u).map((i) => i.code), ['P2P']);
    expect(empty.canSubmit(manage), isFalse);
    expect(d.canSubmit(manage), isTrue);
  });

  test('maker and submitter never approve their own plan', () {
    final d = AssurancePlanDetail.fromJson(
      detail(status: 'submitted', submittedBy: owner),
    );
    expect(d.canDecide(manage, me), isTrue);
    expect(d.canDecide(manage, maker), isFalse);
    expect(d.canDecide(manage, owner), isFalse);
    expect(d.canEdit(manage), isFalse);
    expect(d.canCancel(manage), isTrue);
    expect(d.uncovered.single.code, 'ITGC');
  });

  test('only planners revise approved plans; superseded plans are final', () {
    final approved = AssurancePlanDetail.fromJson(detail(status: 'approved'));
    expect(approved.canRevise(manage), isTrue);
    expect(approved.canRevise({'assurance.evidence.view'}), isFalse);
    expect(AssurancePlanDetail.fromJson(detail()).canRevise(manage), isFalse);
    final superseded = AssurancePlanDetail.fromJson(
      detail(status: 'superseded'),
    );
    expect(superseded.canRevise(manage), isFalse);
    expect(superseded.canInstantiate(manage, superseded.items.single), isFalse);
  });

  test('approved plans instantiate the next missing occurrence', () {
    final d = AssurancePlanDetail.fromJson(detail(status: 'approved'));
    final i = d.items.single;
    expect(d.nextOccurrence(i), 2);
    expect(d.canInstantiate(manage, i), isTrue);
    expect(d.canInstantiate({'assurance.plan.manage'}, i), isFalse);
    expect(d.canCancel(manage), isFalse);
  });

  test('plan register pages and fails closed on unknown status', () {
    final page = AssurancePlanPage.fromJson({
      'items': [
        {
          'id': plan,
          'name': 'FY27 internal audit plan',
          'status': 'approved',
          'version': 7,
          'period_start': '2026-04-01',
          'period_end': '2027-03-31',
          'active_items': 1,
        },
      ],
      'next_cursor': null,
    });
    expect(page.items.single.status, PlanStatus.approved);
    expect(page.nextCursor, isNull);
    expect(
      () => AssurancePlanPage.fromJson({
        'items': [
          {'id': plan, 'status': 'archived'},
        ],
        'next_cursor': null,
      }),
      throwsFormatException,
    );
  });

  test('plan receipts confirm the aggregate, version and engagement', () {
    final p = {
      'action': 'instantiate_engagement',
      'plan_id': plan,
      'plan_item_id': uid(40),
      'occurrence': 2,
      'engagement_id': uid(51),
    };
    final r = {
      'action': 'instantiate_engagement',
      'aggregate_id': plan,
      'version': 6,
      'engagement_id': uid(51),
    };
    expect(assurancePlanReceiptConfirms(r, p, 5), isTrue);
    expect(
      assurancePlanReceiptConfirms({...r, 'engagement_id': uid(52)}, p, 5),
      isFalse,
    );
    expect(assurancePlanReceiptConfirms({...r, 'version': 7}, p, 5), isFalse);
    expect(assurancePlanAggregateKey('assess_risk'), 'item_id');
    expect(() => assurancePlanAggregateKey('drop_plan'), throwsFormatException);
  });
}
