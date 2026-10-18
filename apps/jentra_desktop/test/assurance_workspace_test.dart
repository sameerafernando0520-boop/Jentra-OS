import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/features/assurance/assurance_workspace_controller.dart';
import 'package:jentra_desktop/src/features/assurance/assurance_workspace_screen.dart';
import 'package:jentra_desktop/src/shell/navigation.dart';
import 'package:jentra_domain/jentra_assurance.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_assurance_platform.dart';
import 'package:jentra_platform/jentra_platform.dart';

import 'support/procurement_fakes.dart' show Keys;

String uid(int n) => '90000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
final actor = uid(1), lead = uid(2), eng = uid(3), finding = uid(4);
final today = DateTime.utc(2026, 10, 18);

Map<String, Object?> work(
  int n, {
  String kind = 'evidence_request',
  String? owner,
  String status = 'open',
  required String due,
  required String level,
}) => {
  'engagement_id': eng,
  'engagement_name': 'FY27 Treasury',
  'engagement_version': 9,
  'kind': kind,
  'item_id': uid(n),
  'title': kind == 'finding'
      ? 'Payments released by one signatory'
      : 'Bank mandate evidence $n',
  'owner_id': owner ?? actor,
  'status': status,
  'due_date': due,
  'level': level,
};

class FakeAssuranceGateway implements AssuranceGateway {
  String? failure, respondFailure;
  bool responded = false;
  Completer<void>? overviewPause;
  final overviewEntered = Completer<void>();
  final commands = <CommandEnvelope<Map<String, Object?>>>[];

  @override
  Future<AssuranceOverview> overview(TenantContext s) async {
    if (!overviewEntered.isCompleted) overviewEntered.complete();
    await overviewPause?.future;
    if (failure != null) {
      throw DomainError(code: failure!, message: 'Access needs rechecking');
    }
    return AssuranceOverview.fromJson({
      'as_of': '2026-10-18',
      'response_sla_days': 14,
      'mine': [
        work(10, due: '2026-10-08', level: 'escalated'),
        responded
            ? work(
                4,
                kind: 'finding',
                status: 'remediating',
                due: '2026-11-30',
                level: 'on_track',
              )
            : work(
                4,
                kind: 'finding',
                status: 'issued',
                due: '2026-10-12',
                level: 'overdue',
              ),
        work(12, due: '2026-10-20', level: 'due_soon'),
      ],
      'team': [work(13, owner: lead, due: '2026-10-15', level: 'overdue')],
      'counts': responded
          ? {'due_soon': 1, 'overdue': 1, 'escalated': 1}
          : {'due_soon': 1, 'overdue': 2, 'escalated': 1},
    }, actor);
  }

  @override
  Future<AssuranceEngagementPage> engagements(
    TenantContext s, {
    String? after,
  }) async {
    if (failure != null) {
      throw DomainError(code: failure!, message: 'Access needs rechecking');
    }
    return AssuranceEngagementPage.fromJson({
      'items': [
        {
          'id': eng,
          'name': 'FY27 Treasury',
          'status': 'fieldwork',
          'version': 9,
          'period_start': '2026-04-01',
          'period_end': '2027-03-31',
          'lead_auditor_id': lead,
          'evidence_frozen': false,
          'open_requests': 3,
          'overdue_requests': 2,
          'open_findings': 1,
          'overdue_findings': 1,
          'candidate_exceptions': 0,
        },
      ],
      'next_cursor': null,
    });
  }

  @override
  Future<Map<String, Object?>> engagement(TenantContext s, String id) async => {
    'engagement': {
      'id': id,
      'name': 'FY27 Treasury',
      'status': 'fieldwork',
      'version': 1,
      'period_start': '2026-04-01',
      'period_end': '2027-03-31',
      'scope_summary': 'Treasury and cash controls',
      'lead_auditor_id': lead,
      'evidence_frozen_at': null,
      'evidence_cutoff_digest': null,
    },
    'controls': [
      {
        'id': uid(30),
        'control_code': 'TRS-SIGN',
        'title': 'Dual signatories on payments',
        'owner_id': actor,
        'risk': 'high',
      },
    ],
    'requests': [],
    'exceptions': [],
    'findings': [],
    'reports': [],
    'events': [
      {
        'version': 1,
        'action': 'create_engagement',
        'aggregate_type': 'engagement',
        'aggregate_id': id,
        'from_status': null,
        'to_status': 'planning',
        'actor_id': lead,
        'occurred_at': '2026-10-01T09:00:00Z',
      },
    ],
  };

  @override
  Future<Map<String, Object?>> respond(
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    commands.add(c);
    if (respondFailure != null) {
      throw DomainError(
        code: respondFailure!,
        message: 'Response outcome needs retry',
      );
    }
    responded = true;
    return {
      'engagement_id': eng,
      'version': c.expectedEntityVersion! + 1,
      'action': 'respond',
      'aggregate_type': 'finding',
      'aggregate_id': finding,
      'to_status': 'remediating',
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final scope = TenantContext(
    tenantId: uid(20),
    actorId: actor,
    legalEntityId: uid(21),
    branchId: uid(22),
  );
  late JentraLocalDatabase db;
  late QuotationDraftStore drafts;
  late FakeAssuranceGateway gateway;
  late AssuranceWorkspaceController c;
  var disposed = false;
  AssuranceWorkspaceController make({bool canRespond = true}) =>
      AssuranceWorkspaceController(
        scope: scope,
        gateway: gateway,
        drafts: drafts,
        online: true,
        canRespond: canRespond,
        clock: () => today,
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
    disposed = false;
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = FakeAssuranceGateway();
    c = make();
  });
  tearDown(() async {
    if (!disposed) c.dispose();
    await db.close();
  });
  AssuranceWorkItem issued() =>
      c.overview!.mine.firstWhere((i) => i.kind == 'finding');
  Future<void> startResponse() async {
    await c.initialize();
    await c.startResponse(issued());
    c.field('response', 'Second signatory enforced in the bank portal');
  }

  test('navigation requires audit evidence access', () {
    expect(
      visibleJentraDestinations({'finance.view'})
          .any((d) => d.path == '/governance/audit'),
      isFalse,
    );
    expect(
      visibleJentraDestinations({'assurance.evidence.view'})
          .any((d) => d.path == '/governance/audit'),
      isTrue,
    );
  });

  test('initial load verifies access then shows work and register', () async {
    await c.initialize();
    expect(c.verified, isTrue);
    expect(c.overview!.count(ReminderLevel.escalated), 1);
    expect(c.engagements.single.overdueRequests, 2);
  });

  test(
    'a response is sealed with the engagement version and sent once',
    () async {
      await startResponse();
      await c.submitResponse();
      expect(c.error, isNull);
      final sent = gateway.commands.single;
      expect(sent.expectedEntityVersion, 9);
      expect(sent.payload, {
        'action': 'respond',
        'engagement_id': eng,
        'finding_id': finding,
        'response': 'Second signatory enforced in the bank portal',
        'due_date': '2026-11-17',
        'accept_risk': false,
      });
      expect(
        await drafts.load(scope, AssuranceWorkspaceController.slot),
        isNull,
      );
      expect(c.responding, isFalse);
      expect(
        c.overview!.mine.firstWhere((i) => i.kind == 'finding').status,
        'remediating',
      );
    },
  );

  test('an uncertain outcome is retried with the identical request', () async {
    await startResponse();
    gateway.respondFailure = 'UNCERTAIN_RESULT';
    await c.submitResponse();
    expect(c.pending, isTrue);
    c.field('response', 'Changed after sending');
    expect(c.form['response'], 'Second signatory enforced in the bank portal');
    gateway.respondFailure = null;
    await c.submitResponse();
    expect(gateway.commands, hasLength(2));
    expect(
      gateway.commands.first.idempotencyKey,
      gateway.commands.last.idempotencyKey,
    );
    expect(c.pending, isFalse);
  });

  test(
    'a version conflict releases the request and asks for a refresh',
    () async {
      await startResponse();
      gateway.respondFailure = 'VERSION_CONFLICT';
      await c.submitResponse();
      expect(c.pending, isFalse);
      expect(c.conflicted, isTrue);
      gateway.respondFailure = null;
      await c.submitResponse();
      expect(gateway.commands, hasLength(1));
      expect(c.error, contains('Refresh'));
    },
  );

  test('invalid responses are not sealed or sent', () async {
    await c.initialize();
    await c.startResponse(issued());
    c.field('response', 'ok');
    await c.submitResponse();
    expect(gateway.commands, isEmpty);
    expect(
      (await drafts.load(scope, AssuranceWorkspaceController.slot))!.pending,
      isNull,
    );
    expect(c.error, isNotNull);
  });

  test('without the response capability nothing can be started', () async {
    c.dispose();
    c = make(canRespond: false);
    await c.initialize();
    await c.startResponse(issued());
    expect(c.responding, isFalse);
  });

  test('team items and other owners cannot be responded to', () async {
    await c.initialize();
    await c.startResponse(c.overview!.team.single);
    await c.startResponse(c.overview!.mine.first);
    expect(c.responding, isFalse);
  });

  test('access loss clears audit work until access is rechecked', () async {
    await c.initialize();
    gateway.failure = 'MFA_REQUIRED';
    await c.refresh();
    expect(c.accessDenied, isTrue);
    expect(c.overview, isNull);
    expect(c.engagements, isEmpty);
    gateway.failure = null;
    await c.refresh();
    expect(c.accessDenied, isFalse);
    expect(c.overview, isNotNull);
  });

  test('a delayed read cannot repopulate after going offline', () async {
    gateway.overviewPause = Completer<void>();
    final task = c.initialize();
    await gateway.overviewEntered.future;
    c.setOnline(false);
    c.setOnline(true);
    gateway.overviewPause!.complete();
    await task;
    expect(c.overview, isNull);
    expect(c.verified, isFalse);
  });

  test('a response draft survives a restart but not another branch', () async {
    await startResponse();
    await c.saveResponse();
    c.dispose();
    disposed = true;
    final again = make();
    await again.initialize();
    expect(
      again.form['response'],
      'Second signatory enforced in the bank portal',
    );
    again.dispose();
    expect(
      await drafts.load(
        TenantContext(
          tenantId: scope.tenantId,
          actorId: actor,
          legalEntityId: scope.legalEntityId,
          branchId: uid(99),
        ),
        AssuranceWorkspaceController.slot,
      ),
      isNull,
    );
  });

  Future<void> render(WidgetTester t, bool dark) async {
    t.view.physicalSize = const Size(1024, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        theme: dark ? JentraTheme.dark() : JentraTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: AssuranceWorkspace(controller: c)),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    testWidgets(
      'governance workspace ${dark ? 'dark' : 'light'} 200 percent work queue and response',
      (t) async {
        await t.runAsync(c.initialize);
        await render(t, dark);
        expect(t.takeException(), isNull);
        expect(find.text('Escalated: 1'), findsOneWidget);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            'goldens/governance_work_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
        await t.scrollUntilVisible(
          find.text('Respond'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await t.tap(find.text('Respond'));
        await t.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await t.pumpAndSettle();
        expect(find.text('Management response'), findsOneWidget);
        expect(t.takeException(), isNull);
        await c.closeDetailIfAny();
        c.select('engagements');
        await t.pumpAndSettle();
        expect(find.textContaining('2 overdue'), findsOneWidget);
      },
    );
  }
}

extension on AssuranceWorkspaceController {
  Future<void> closeDetailIfAny() async {
    if (detail != null) closeDetail();
  }
}
