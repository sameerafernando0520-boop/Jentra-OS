import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/features/assurance/assurance_planning_controller.dart';
import 'package:jentra_desktop/src/features/assurance/assurance_planning_screen.dart';
import 'package:jentra_desktop/src/shell/navigation.dart';
import 'package:jentra_domain/jentra_assurance.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_assurance_platform.dart';
import 'package:jentra_platform/jentra_platform.dart';

import 'support/procurement_fakes.dart' show Keys;

String uid(int n) => '93000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
final actor = uid(1), maker = uid(2), owner = uid(3), planId = uid(10);

class FakePlanningGateway implements AssuranceGateway {
  String planStatus = 'draft';
  String? submittedBy, failure;
  int planVersion = 3, itemVersion = 2;
  bool planned = true;
  final commands = <CommandEnvelope<Map<String, Object?>>>[];

  @override
  Future<AssuranceUniverse> universe(TenantContext s) async =>
      AssuranceUniverse.fromJson({
        'items': [
          {
            'id': uid(20),
            'code': 'P2P',
            'name': 'Procure to pay',
            'category': 'process',
            'owner_id': owner,
            'status': 'active',
            'version': itemVersion,
            'assessment': {'rating': 'critical', 'score': 20},
          },
          {
            'id': uid(21),
            'code': 'ITGC',
            'name': 'IT general controls',
            'category': 'system',
            'owner_id': owner,
            'status': 'active',
            'version': 1,
            'assessment': {'rating': 'high', 'score': 12},
          },
        ],
        'templates': [
          {'id': uid(30), 'code': 'P2P-STD', 'version': 2, 'name': 'P2P'},
        ],
      });

  Map<String, Object?> _summary() => {
    'id': planId,
    'name': 'FY27 internal audit plan',
    'status': planStatus,
    'version': planVersion,
    'period_start': '2026-04-01',
    'period_end': '2027-03-31',
    'active_items': planned ? 1 : 0,
  };

  @override
  Future<AssurancePlanPage> plans(TenantContext s, {String? after}) async =>
      AssurancePlanPage.fromJson({
        'items': [_summary()],
        'next_cursor': null,
      });

  @override
  Future<AssurancePlanDetail> plan(TenantContext s, String planId) async =>
      AssurancePlanDetail.fromJson({
        'plan': {
          ..._summary(),
          'created_by': maker,
          'submitted_by': submittedBy,
          'approved_digest': planStatus == 'approved' ? 'e' * 64 : null,
        },
        'items': [
          if (planned)
            {
              'id': uid(40),
              'universe_item_id': uid(20),
              'code': 'P2P',
              'name': 'Procure to pay',
              'rating': 'critical',
              'frequency': 'quarterly',
              'template_id': uid(30),
              'lead_auditor_id': actor,
              'status': 'active',
              'occurrences': [
                {'occurrence': 1, 'engagement_id': uid(50)},
              ],
            },
        ],
        'uncovered_high_risk': [
          {'item_id': uid(21), 'code': 'ITGC', 'rating': 'high'},
        ],
      });

  @override
  Future<Map<String, Object?>> planCommand(
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    commands.add(c);
    if (failure != null) {
      throw DomainError(code: failure!, message: 'Refused: $failure');
    }
    final p = c.payload, action = p['action']! as String;
    return {
      'action': action,
      'aggregate_id': p[assurancePlanAggregateKey(action)],
      'version': c.expectedEntityVersion! + 1,
      if (action == 'instantiate_engagement')
        'engagement_id': p['engagement_id'],
    };
  }

  @override
  Future<AssuranceOverview> overview(TenantContext s) =>
      throw UnimplementedError();
  @override
  Future<AssuranceEngagementPage> engagements(
    TenantContext s, {
    String? after,
  }) => throw UnimplementedError();
  @override
  Future<Map<String, Object?>> engagement(TenantContext s, String id) =>
      throw UnimplementedError();
  @override
  Future<List<Object?>> tests(TenantContext s, String engagementId) =>
      throw UnimplementedError();
  @override
  Future<Map<String, Object?>> respond(
    CommandEnvelope<Map<String, Object?>> c,
  ) => throw UnimplementedError();
  @override
  Future<Map<String, Object?>> auditorCommand(
    CommandEnvelope<Map<String, Object?>> c,
  ) => throw UnimplementedError();
  @override
  Future<AuditPackVerification> auditPack(TenantContext s, String id) =>
      throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final scope = TenantContext(
    tenantId: uid(90),
    actorId: actor,
    legalEntityId: uid(91),
    branchId: uid(92),
  );
  const planner = {
    'assurance.plan.manage',
    'assurance.engagement.manage',
    'assurance.evidence.view',
  };
  late JentraLocalDatabase db;
  late QuotationDraftStore drafts;
  late FakePlanningGateway gateway;
  late AssurancePlanningController c;
  AssurancePlanningController make({Set<String> caps = planner}) =>
      AssurancePlanningController(
        scope: scope,
        gateway: gateway,
        drafts: drafts,
        online: true,
        capabilities: caps,
        clock: () => DateTime.utc(2026, 10, 19),
      );
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    const base = 'packages/jentra_design_system/assets/fonts/';
    await (FontLoader(JentraTypography.sansFamily)
          ..addFont(rootBundle.load('${base}Manrope-Regular.ttf'))
          ..addFont(rootBundle.load('${base}Manrope-SemiBold.ttf')))
        .load();
  });
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = FakePlanningGateway();
    c = make();
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });

  test('navigation shows planning to planners and evidence viewers', () {
    bool shown(Set<String> caps) =>
        visibleJentraDestinations(caps)
            .any((d) => d.path == '/governance/audit/planning');
    expect(shown({'finance.view'}), isFalse);
    expect(shown({'assurance.plan.manage'}), isTrue);
    expect(shown({'assurance.evidence.view'}), isTrue);
  });

  test('a risk assessment uses the area version and whole numbers', () async {
    await c.initialize();
    expect(c.verified, isTrue);
    await c.startCommand('assess_risk', {
      'item_id': uid(20),
      'likelihood': '3',
      'impact': '3',
      'rationale': '',
    });
    c.field('likelihood', '4');
    c.field('impact', '5');
    c.field('rationale', 'Annual risk workshop');
    await c.submit();
    expect(c.error, isNull);
    final sent = gateway.commands.single;
    expect(sent.expectedEntityVersion, 2);
    expect(sent.payload['likelihood'], 4);
    expect(sent.payload['impact'], 5);
    expect(sent.payload['assessment_id'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(sent.payload.containsKey('plan_id'), isFalse);
  });

  test('a new plan is created at version 0 and opened', () async {
    await c.initialize();
    await c.startCommand('create_plan', {
      'name': 'FY28 internal audit plan',
      'period_start': '2027-04-01',
      'period_end': '2028-03-31',
    });
    await c.submit();
    expect(c.error, isNull);
    final sent = gateway.commands.single;
    expect(sent.expectedEntityVersion, 0);
    expect(c.section, 'plan');
    expect(c.plan, isNotNull);
  });

  test('items are added against the plan version with no template', () async {
    gateway.planned = false;
    await c.initialize();
    await c.openPlan(planId);
    expect(c.plan!.plannable(c.universe!).map((i) => i.code), ['P2P', 'ITGC']);
    await c.startCommand('add_plan_item', {
      'item_id': uid(21),
      'frequency': 'semiannual',
      'template_id': '',
      'lead_auditor_id': actor,
      'scope_summary': 'Access and change management',
    });
    await c.submit();
    expect(c.error, isNull);
    final sent = gateway.commands.single;
    expect(sent.expectedEntityVersion, 3);
    expect(sent.payload['plan_id'], planId);
    expect(sent.payload['template_id'], isNull);
  });

  test('the maker cannot decide; an independent approver can', () async {
    gateway
      ..planStatus = 'submitted'
      ..submittedBy = maker;
    await c.initialize();
    await c.openPlan(planId);
    expect(c.plan!.canDecide(c.capabilities, actor), isTrue);
    expect(c.plan!.canDecide(c.capabilities, maker), isFalse);
    gateway.failure = 'MFA_REQUIRED';
    await c.startCommand('decide_plan', {
      'decision': 'approve',
      'reason': 'Coverage accepted',
    });
    await c.submit();
    expect(c.pending, isTrue);
    expect(c.accessDenied, isFalse);
    gateway.failure = null;
    await c.submit();
    expect(gateway.commands, hasLength(2));
    expect(
      gateway.commands.first.idempotencyKey,
      gateway.commands.last.idempotencyKey,
    );
    expect(c.pending, isFalse);
  });

  test('an approved plan creates the next occurrence', () async {
    gateway.planStatus = 'approved';
    await c.initialize();
    await c.openPlan(planId);
    final item = c.plan!.items.single;
    expect(c.plan!.nextOccurrence(item), 2);
    await c.startCommand('instantiate_engagement', {
      'plan_item_id': item.id,
      'occurrence': '2',
    });
    await c.submit();
    expect(c.error, isNull);
    expect(gateway.commands.single.payload['occurrence'], 2);
    expect(c.message, contains('Engagement created'));
  });

  test('without planning rights nothing can be started', () async {
    c.dispose();
    c = make(caps: {'assurance.evidence.view'});
    await c.initialize();
    await c.startCommand('create_plan', {'name': 'x'});
    expect(c.commanding, isFalse);
  });

  Future<void> render(WidgetTester t, bool dark) async {
    t.view.physicalSize = const Size(1024, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        theme: dark ? JentraTheme.dark() : JentraTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: AssurancePlanning(controller: c)),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    testWidgets(
      'audit planning ${dark ? 'dark' : 'light'} 200 percent plan detail',
      (t) async {
        gateway
          ..planStatus = 'submitted'
          ..submittedBy = maker;
        await t.runAsync(c.initialize);
        await t.runAsync(() => c.openPlan(planId));
        await render(t, dark);
        expect(t.takeException(), isNull);
        expect(find.text('Decide'), findsOneWidget);
        expect(find.text('High-risk areas not covered'), findsOneWidget);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            'goldens/audit_planning_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
      },
    );
  }
}
