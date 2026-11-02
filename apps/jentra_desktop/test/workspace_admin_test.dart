import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/features/tenant/workspace_admin_controller.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/tenant/workspace_admin_screen.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_workspace_admin.dart';
import 'package:jentra_platform/jentra_workspace_admin_platform.dart';
import 'package:jentra_platform/jentra_platform.dart';

const scope = TenantContext(
  tenantId: '10000000-0000-0000-0000-000000000001',
  actorId: '10000000-0000-0000-0000-000000000002',
);
const id = '10000000-0000-0000-0000-000000000003';
const fields = {
  'name': 'Pilot Company',
  'code': 'PC',
  'currency_code': 'LKR',
  'timezone': 'Asia/Colombo',
};

final class _Recovery implements WorkspaceAdminRecovery {
  WorkspaceAdminPending? value;
  bool failSeal = false, failLoad = false, failComplete = false;
  @override
  Future<WorkspaceAdminPending?> load(TenantContext s) async {
    if (failLoad) throw StateError('read failed');
    return value;
  }

  @override
  Future<WorkspaceAdminPending> seal(WorkspaceAdminPending p) async {
    if (failSeal) throw StateError('write failed');
    return value = p;
  }

  @override
  Future<void> complete(TenantContext s, String commandId) async {
    if (failComplete) throw StateError('delete failed');
    expect(value?.command.commandId, commandId);
    value = null;
  }
}

final class _Gateway implements WorkspaceAdminRepository {
  final sent = <Map<String, Object?>>[];
  final rows = <WorkspaceAdminResource, List<WorkspaceAdminRecord>>{};
  Completer<WorkspaceAdminPage>? delayedRead;
  Completer<Map<String, Object?>>? delayedCommand;
  String? errorCode;
  String? readErrorCode;
  bool mismatched = false;
  _Recovery? recovery;
  @override
  Future<WorkspaceAdminPage> list(
    TenantContext s,
    WorkspaceAdminResource r, {
    String? after,
    int limit = 50,
  }) async {
    if (readErrorCode != null) {
      throw DomainError(
        code: readErrorCode!,
        message: 'Controlled read failure',
      );
    }
    final wait = delayedRead;
    if (wait != null) {
      delayedRead = null;
      return wait.future;
    }
    return WorkspaceAdminPage(
      items:
          rows[r] ??
          (r == WorkspaceAdminResource.entities
              ? [
                  WorkspaceAdminRecord({
                    'id': id,
                    'tenant_id': s.tenantId,
                    'name': 'Pilot Company',
                    'code': 'PC',
                    'status': 'active',
                    'version': 1,
                  }),
                ]
              : []),
    );
  }

  @override
  Future<Map<String, Object?>> command(
    WorkspaceAdminAction a,
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    expect(recovery?.value?.command.commandId, c.commandId);
    sent.add(c.toJson((v) => v));
    if (delayedCommand != null) return delayedCommand!.future;
    if (errorCode != null) {
      throw DomainError(code: errorCode!, message: 'Controlled rejection');
    }
    return response(a, c, mismatched: mismatched);
  }

  @override
  Future<Map<String, Object?>> myInvitations({String? after}) async => {
    'items': [],
    'next_cursor': null,
  };
  @override
  Future<Map<String, Object?>> acceptInvitation(
    String invitationId,
    String key,
  ) async => {};
}

BusinessScopeState _pilotScope() => const BusinessScopeState(
  tenants: [
    TenantSummary(
      id: '10000000-0000-0000-0000-000000000001',
      name: 'Pilot Group',
      slug: 'pilot-group',
      status: 'active',
      membershipStatus: 'active',
    ),
  ],
  legalEntities: [],
  branches: [],
  tenantId: '10000000-0000-0000-0000-000000000001',
  legalEntityId: null,
  branchId: null,
);

Map<String, Object?> response(
  WorkspaceAdminAction a,
  CommandEnvelope<Map<String, Object?>> c, {
  bool mismatched = false,
}) => {
  'request_id': c.commandId,
  'warnings': [],
  'entity': {
    'id': id,
    'tenant_id': c.context.tenantId,
    'version': a.creates ? 1 : c.expectedEntityVersion! + 1,
    'action': a.wire,
    ...c.payload,
    if (mismatched) 'name': 'Different company',
  },
};
WorkspaceAdminController _controller(
  _Gateway g,
  _Recovery r, {
  Set<String> caps = const {
    'core.tenant.manage',
    'core.roles.manage',
    'core.members.invite',
  },
}) {
  g.recovery = r;
  return WorkspaceAdminController(
    scope: scope,
    gateway: g,
    recovery: r,
    capabilities: caps,
    online: true,
  );
}

Future<void> _pumpAdmin(
  WidgetTester tester,
  WorkspaceAdminController c, {
  bool dark = false,
}) async {
  tester.view.physicalSize = const Size(1024, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workspaceAdminControllerProvider.overrideWithValue(c),
        businessScopeProvider.overrideWithBuild(
          (ref, notifier) async => _pilotScope(),
        ),
      ],
      child: MaterialApp(
        theme: dark ? JentraTheme.dark() : JentraTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(body: WorkspaceAdminScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
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
  test('CA-E6 recovery failure prevents all mutation transport', () async {
    final g = _Gateway(),
        r = _Recovery()..failSeal = true,
        c = _controller(g, r);
    addTearDown(c.dispose);
    await c.initialize();
    expect(await c.send(WorkspaceAdminAction.createEntity, fields), isFalse);
    expect(g.sent, isEmpty);
  });
  test('CA-E8 backend must confirm its read contract before new mutations are enabled', () async {
    final g = _Gateway()..readErrorCode = 'PROVIDER_UNAVAILABLE',
        r = _Recovery(),
        c = _controller(g, r);
    addTearDown(c.dispose);
    await c.initialize();
    expect(c.available, isFalse);
    expect(c.locked, isTrue);
    expect(await c.send(WorkspaceAdminAction.createEntity, fields), isFalse);
    expect(g.sent, isEmpty);
    g.readErrorCode = null;
    await c.load(c.resource);
    expect(c.available, isTrue);
    expect(c.locked, isFalse);
  });
  test('CA-10 a disposed controller cannot seal a new command', () async {
    final g = _Gateway(), r = _Recovery(), c = _controller(g, r);
    await c.initialize();
    c.dispose();
    expect(await c.send(WorkspaceAdminAction.createEntity, fields), isFalse);
    expect(r.value, isNull);
    expect(g.sent, isEmpty);
  });
  test('CA-E6 recovery read failure keeps mutation controls locked', () async {
    final g = _Gateway(),
        r = _Recovery()..failLoad = true,
        c = _controller(g, r);
    addTearDown(c.dispose);
    await c.initialize();
    expect(c.ready, isFalse);
    expect(c.locked, isTrue);
    expect(await c.send(WorkspaceAdminAction.createEntity, fields), isFalse);
  });
  test(
    'CA-A7 unknown result retains exact request for explicit retry',
    () async {
      final g = _Gateway()..errorCode = 'UNCERTAIN_RESULT',
          r = _Recovery(),
          c = _controller(g, r);
      addTearDown(c.dispose);
      await c.initialize();
      expect(await c.send(WorkspaceAdminAction.createEntity, fields), isFalse);
      expect(c.pending, isNotNull);
      expect(
        await c.send(WorkspaceAdminAction.createEntity, {
          ...fields,
          'name': 'Other',
        }),
        isFalse,
      );
      g.errorCode = null;
      await c.retry();
      expect(g.sent.length, 2);
      expect(
        workspaceAdminCanonical(g.sent.first),
        workspaceAdminCanonical(g.sent.last),
      );
      expect(c.pending, isNull);
      expect(r.value, isNull);
    },
  );
  test(
    'CA-08 known precommit conflict releases only the rejected command',
    () async {
      final g = _Gateway()..errorCode = 'VERSION_CONFLICT',
          r = _Recovery(),
          c = _controller(g, r);
      addTearDown(c.dispose);
      await c.initialize();
      await c.send(WorkspaceAdminAction.createEntity, fields);
      expect(c.pending, isNull);
      expect(r.value, isNull);
      g.errorCode = null;
      expect(await c.send(WorkspaceAdminAction.createEntity, fields), isTrue);
      expect(g.sent.first['command_id'], isNot(g.sent.last['command_id']));
    },
  );
  test('CA-08 malformed success cannot remove pending recovery', () async {
    final g = _Gateway()..mismatched = true,
        r = _Recovery(),
        c = _controller(g, r);
    addTearDown(c.dispose);
    await c.initialize();
    expect(await c.send(WorkspaceAdminAction.createEntity, fields), isFalse);
    expect(c.pending, isNotNull);
    expect(r.value, isNotNull);
  });
  test('CA-08 failed local acknowledgement retains original request', () async {
    final g = _Gateway(),
        r = _Recovery()..failComplete = true,
        c = _controller(g, r);
    addTearDown(c.dispose);
    await c.initialize();
    expect(await c.send(WorkspaceAdminAction.createEntity, fields), isFalse);
    expect(c.pending, isNotNull);
    r.failComplete = false;
    await c.retry();
    expect(g.sent.length, 2);
    expect(g.sent.first, g.sent.last);
    expect(c.pending, isNull);
  });
  test(
    'CA-10 offline invalidation ignores a late read and reconnect recovers',
    () async {
      final wait = Completer<WorkspaceAdminPage>(),
          g = _Gateway()..delayedRead = wait,
          r = _Recovery(),
          c = _controller(g, r);
      addTearDown(c.dispose);
      final initialization = c.initialize();
      await Future<void>.delayed(Duration.zero);
      c.setOnline(false);
      expect(c.pages, isEmpty);
      c.setOnline(true);
      await Future<void>.delayed(Duration.zero);
      wait.complete(
        WorkspaceAdminPage(
          items: [
            WorkspaceAdminRecord({
              'id': id,
              'tenant_id': scope.tenantId,
              'version': 1,
              'name': 'Late private row',
            }),
          ],
        ),
      );
      await initialization;
      await Future<void>.delayed(Duration.zero);
      expect(
        c.pages[WorkspaceAdminResource.entities]!.items.single.name,
        'Pilot Company',
      );
      expect(c.ready, isTrue);
    },
  );
  test(
    'CA-10 disposal ignores late confirmation and keeps sealed recovery',
    () async {
      final wait = Completer<Map<String, Object?>>(),
          g = _Gateway()..delayedCommand = wait,
          r = _Recovery(),
          c = _controller(g, r);
      await c.initialize();
      final sending = c.send(WorkspaceAdminAction.createEntity, fields);
      await Future<void>.delayed(Duration.zero);
      final pending = r.value!;
      c.dispose();
      wait.complete(response(pending.action, pending.command));
      expect(await sending, isFalse);
      expect(r.value, isNotNull);
      expect(c.pages, isEmpty);
    },
  );
  test(
    'CA-A1 denial clears private rows and preserves uncertain command',
    () async {
      final g = _Gateway()..errorCode = 'PERMISSION_DENIED',
          r = _Recovery(),
          c = _controller(g, r);
      addTearDown(c.dispose);
      await c.initialize();
      await c.send(WorkspaceAdminAction.createEntity, fields);
      expect(c.denied, isTrue);
      expect(c.pages, isEmpty);
      expect(c.pending, isNotNull);
    },
  );
  test(
    'CA-01 invitation manager can read scope choices but cannot edit roles',
    () async {
      final g = _Gateway(),
          r = _Recovery(),
          c = _controller(g, r, caps: {'core.members.invite'});
      addTearDown(c.dispose);
      await c.initialize();
      expect(c.canRead(WorkspaceAdminResource.entities), isTrue);
      expect(c.canRead(WorkspaceAdminResource.roles), isTrue);
      expect(
        await c.send(WorkspaceAdminAction.createRole, {
          'name': 'Role',
          'code': 'role',
          'permissions': ['sales.view'],
          'requires_mfa': false,
        }),
        isFalse,
      );
      expect(g.sent, isEmpty);
    },
  );
  testWidgets('CA-A9 administration renders at 1024x720 and 200 percent text', (
    tester,
  ) async {
    final g = _Gateway(), r = _Recovery(), c = _controller(g, r);
    await c.initialize();
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(1024, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preview = GlobalKey();
    Future<void> capture(String name) async {
      final boundary =
          preview.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
        final directory = Directory('../../build/company-access-preview');
        await directory.create(recursive: true);
        await File('${directory.path}/$name.png').writeAsBytes(bytes);
      } finally {
        image.dispose();
      }
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceAdminControllerProvider.overrideWithValue(c),
          businessScopeProvider.overrideWithBuild(
            (ref, notifier) async => _pilotScope(),
          ),
        ],
        child: MaterialApp(
          theme: JentraTheme.light(),
          builder: (context, child) => RepaintBoundary(
            key: preview,
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
          ),
          home: const Scaffold(body: WorkspaceAdminScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Company & access'), findsOneWidget);
    expect(find.text('Pilot Company'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() => capture('companies-200'));
    await tester.tap(find.text('Add company'));
    await tester.pumpAndSettle();
    expect(find.text('Registered company name'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() => capture('add-company-200'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
  testWidgets(
    'CA-10 an open invitation form stays invalid after disconnect and reconnect',
    (tester) async {
      final g = _Gateway(), r = _Recovery(), c = _controller(g, r);
      addTearDown(c.dispose);
      await c.initialize();
      await c.load(WorkspaceAdminResource.invitations);
      await _pumpAdmin(tester, c);
      await tester.tap(find.text('Invite staff'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Staff email'),
        'private-staff@pilot.invalid',
      );
      c.setOnline(false);
      await tester.pumpAndSettle();
      expect(find.text('Workplace changed'), findsOneWidget);
      expect(find.text('private-staff@pilot.invalid'), findsNothing);
      expect(find.text('Save change'), findsNothing);
      c.setOnline(true);
      await tester.pumpAndSettle();
      expect(find.text('Workplace changed'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(g.sent, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'CA-10 a staff confirmation clears its private target after disconnect',
    (tester) async {
      final g = _Gateway(), r = _Recovery(), c = _controller(g, r);
      addTearDown(c.dispose);
      g.rows[WorkspaceAdminResource.members] = [
        WorkspaceAdminRecord({
          'id': id,
          'tenant_id': scope.tenantId,
          'user_id': '10000000-0000-0000-0000-000000000004',
          'name': 'Private Staff',
          'status': 'active',
          'version': 1,
          'assignments': [],
        }),
      ];
      await c.initialize();
      await c.load(WorkspaceAdminResource.members);
      await _pumpAdmin(tester, c);
      await tester.tap(find.text('Suspend access'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm change'), findsOneWidget);
      c.setOnline(false);
      await tester.pumpAndSettle();
      expect(find.text('Workplace changed'), findsOneWidget);
      expect(find.textContaining('Private Staff'), findsNothing);
      expect(find.text('Confirm change'), findsNothing);
      expect(g.sent, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'CA-A4 privileged role form enforces MFA at 200 percent in dark theme',
    (tester) async {
      final g = _Gateway(), r = _Recovery(), c = _controller(g, r);
      addTearDown(c.dispose);
      g.rows[WorkspaceAdminResource.permissions] = [
        WorkspaceAdminRecord({
          'id': 'finance.view',
          'code': 'finance.view',
          'name': 'View finance',
          'privileged': true,
        }),
      ];
      await c.initialize();
      await c.load(WorkspaceAdminResource.roles);
      await _pumpAdmin(tester, c, dark: true);
      await tester.tap(find.text('Create role'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Role name'),
        'Finance reader',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Code'),
        'finance_reader',
      );
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      final mfa = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(mfa.value, isTrue);
      expect(mfa.onChanged, isNull);
      await tester.tap(find.text('Save change'));
      await tester.pumpAndSettle();
      expect(g.sent, hasLength(1));
      expect(g.sent.single['payload'], {
        'name': 'Finance reader',
        'code': 'finance_reader',
        'permissions': ['finance.view'],
        'requires_mfa': true,
      });
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
