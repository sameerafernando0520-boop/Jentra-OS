import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/features/assurance/assurance_access_controller.dart';
import 'package:jentra_desktop/src/features/assurance/assurance_access_screen.dart';
import 'package:jentra_desktop/src/shell/navigation.dart';
import 'package:jentra_domain/jentra_assurance.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_assurance_platform.dart';
import 'package:jentra_platform/jentra_platform.dart';

import 'support/procurement_fakes.dart' show Keys;

String uid(int n) => '94000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
final actor = uid(1), linked = uid(10), unlinked = uid(11);

class FakeAccessGateway implements AssuranceAccessGateway {
  String? failure;
  int pages = 1;
  final Map<String, int> versions = {linked: 2, unlinked: 0};
  final Map<String, List<Map<String, Object?>>> held = {
    linked: [
      {
        'role_code': 'assurance_auditor',
        'scope': 'entity',
        'legal_entity_id': uid(91),
        'branch_id': null,
      },
    ],
    unlinked: [],
  };
  final commands = <CommandEnvelope<Map<String, Object?>>>[];

  Map<String, Object?> member(String id, String label, bool isLinked) => {
    'membership_id': id,
    'label': label,
    'linked': isLinked,
    'version': versions[id] ?? 0,
    'assignments': held[id] ?? <Object?>[],
  };

  @override
  Future<AssuranceAccess> access(TenantContext s, {String? after}) async {
    if (failure == 'PERMISSION_DENIED') {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Audit access is required in this entity and branch.',
      );
    }
    final second = after != null;
    return AssuranceAccess.fromJson({
      'can_manage': true,
      'roles': <Object?>[],
      'members': second
          ? [member(uid(12), 'Kasun Silva', true)]
          : [
              member(linked, 'Nadeesha Perera', true),
              member(unlinked, 'Unlinked member ····0011', false),
            ],
      'next_cursor': !second && pages > 1 ? unlinked : null,
    });
  }

  @override
  Future<Map<String, Object?>> setRole(
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    commands.add(c);
    if (failure != null) {
      throw DomainError(code: failure!, message: 'Refused: $failure');
    }
    final id = c.payload['membership_id']! as String;
    versions[id] = (versions[id] ?? 0) + 1;
    return {...c.payload, 'version': versions[id]};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final scope = TenantContext(
    tenantId: uid(90),
    actorId: actor,
    legalEntityId: uid(91),
    branchId: uid(92),
  );
  late JentraLocalDatabase db;
  late QuotationDraftStore drafts;
  late FakeAccessGateway gateway;
  late AssuranceAccessController c;
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
    gateway = FakeAccessGateway();
    c = AssuranceAccessController(
      scope: scope,
      gateway: gateway,
      drafts: drafts,
      online: true,
    );
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });

  test('navigation shows audit access only to role managers', () {
    bool shown(Set<String> caps) =>
        visibleJentraDestinations(caps)
            .any((d) => d.path == '/governance/audit/access');
    expect(shown({'assurance.plan.manage'}), isFalse);
    expect(shown({'core.roles.manage'}), isTrue);
  });

  test('a grant is sealed with the member version and confirmed', () async {
    await c.initialize();
    expect(c.access!.members, hasLength(2));
    final m = c.access!.members.first;
    await c.startChange(m, AssuranceRole.lead, AccessScope.tenant, grant: true);
    await c.submit();
    expect(c.error, isNull);
    final sent = gateway.commands.single;
    expect(sent.expectedEntityVersion, 2);
    expect(sent.payload, {
      'membership_id': linked,
      'role_code': 'assurance_lead',
      'granted': true,
      'scope': 'tenant',
    });
    expect(c.pending, isFalse);
    expect(c.message, 'Audit lead given to Nadeesha Perera.');
  });

  test('an MFA refusal keeps the sealed request for the same retry', () async {
    await c.initialize();
    gateway.failure = 'MFA_REQUIRED';
    await c.startChange(
      c.access!.members.last,
      AssuranceRole.reviewer,
      AccessScope.entity,
      grant: true,
    );
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

  test('a version conflict asks for a refresh and blocks resending', () async {
    await c.initialize();
    gateway.failure = 'VERSION_CONFLICT';
    await c.startChange(
      c.access!.members.first,
      AssuranceRole.auditor,
      AccessScope.entity,
      grant: false,
    );
    await c.submit();
    expect(c.conflicted, isTrue);
    await c.submit();
    expect(gateway.commands, hasLength(1));
    expect(c.error, contains('Refresh'));
  });

  test('losing access clears members until access is rechecked', () async {
    await c.initialize();
    gateway.failure = 'PERMISSION_DENIED';
    await c.refresh();
    expect(c.accessDenied, isTrue);
    expect(c.access, isNull);
  });

  test('more members are appended from the next page', () async {
    gateway.pages = 2;
    await c.initialize();
    expect(c.access!.nextCursor, isNotNull);
    await c.more();
    expect(c.members.map((m) => m.label), [
      'Nadeesha Perera',
      'Unlinked member ····0011',
      'Kasun Silva',
    ]);
  });

  Future<void> render(WidgetTester t, bool dark) async {
    t.view.physicalSize = const Size(1024, 2200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        theme: dark ? JentraTheme.dark() : JentraTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: AssuranceAccessView(controller: c)),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('roles are explained and members never show an e-mail', (
    t,
  ) async {
    await c.initialize();
    await render(t, false);
    for (final r in AssuranceRole.values) {
      expect(find.text(r.label), findsWidgets);
      expect(find.text(r.summary), findsOneWidget);
    }
    expect(find.text('Nadeesha Perera'), findsOneWidget);
    expect(find.textContaining('@'), findsNothing);
  });

  testWidgets('keyboard focus reaches every change-access control', (t) async {
    await c.initialize();
    await render(t, false);
    final buttons = find.widgetWithText(OutlinedButton, 'Change access');
    expect(buttons, findsNWidgets(2));
    var reached = 0;
    for (var i = 0; i < 40; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      final focused = FocusManager.instance.primaryFocus?.context?.widget;
      if (focused != null &&
          find
              .ancestor(
                of: find.byWidget(focused),
                matching: find.widgetWithText(OutlinedButton, 'Change access'),
              )
              .evaluate()
              .isNotEmpty) {
        reached++;
      }
    }
    expect(reached, greaterThanOrEqualTo(2));
  });

  for (final dark in [false, true]) {
    testWidgets('audit access ${dark ? 'dark' : 'light'} 200 percent', (
      t,
    ) async {
      await c.initialize();
      await c.startChange(
        c.access!.members.last,
        AssuranceRole.processOwner,
        AccessScope.branch,
        grant: true,
      );
      await render(t, dark);
      await expectLater(
        find.byType(AssuranceAccessView),
        matchesGoldenFile(
          'goldens/audit_access_${dark ? 'dark' : 'light'}_200.png',
        ),
      );
    });
  }
}
