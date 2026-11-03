import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/features/tenant/staff_account_dialog.dart';
import 'package:jentra_desktop/src/features/tenant/workspace_admin_controller.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_workspace_admin.dart';
import 'package:jentra_platform/jentra_workspace_admin_platform.dart';

const actor = '10000000-0000-0000-0000-000000000001';
const tenant = '20000000-0000-0000-0000-000000000001';
const sales = '30000000-0000-0000-0000-000000000001';
const inventory = '30000000-0000-0000-0000-000000000002';

final class _Unused
    implements WorkspaceAdminRepository, WorkspaceAdminRecovery {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Staff credentials must not enter command recovery.');
}

final class _Recovery implements StaffAccountRecovery {
  StaffAccountRequest? request;
  @override
  Future<StaffAccountRequest?> load(TenantContext scope) async => request;
  @override
  Future<void> save(TenantContext scope, StaffAccountRequest value) async {
    if (request != null) {
      expect(value.toJson(), request!.toJson());
    }
    request = value;
  }

  @override
  Future<void> complete(TenantContext scope, String requestId) async {
    expect(request?.requestId, requestId);
    request = null;
  }
}

final class _Gateway implements WorkspaceStaffGateway {
  final sent = <Map<String, Object?>>[];
  bool uncertain = false;
  bool accessChanged = false;
  @override
  Future<void> create({
    required TenantContext scope,
    required String requestId,
    required String username,
    required String displayName,
    required Set<String> roleIds,
    required String password,
  }) async {
    sent.add({
      'request_id': requestId,
      'username': username,
      'display_name': displayName,
      'role_ids': roleIds.toList()..sort(),
      'password': password,
    });
    if (accessChanged) {
      throw const DomainError(
        code: 'ACCESS_CHANGED',
        message: 'Existing staff access changed.',
      );
    }
    if (uncertain && sent.length == 1) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Retry the original details.',
      );
    }
  }
}

void main() {
  late WorkspaceAdminController controller;
  late _Gateway gateway;
  late _Recovery recovery;
  setUp(() {
    gateway = _Gateway();
    recovery = _Recovery();
    final unused = _Unused();
    controller =
        WorkspaceAdminController(
            scope: const TenantContext(tenantId: tenant, actorId: actor),
            gateway: unused,
            recovery: unused,
            capabilities: {'core.roles.manage', 'core.members.invite'},
            online: true,
          )
          ..ready = true
          ..available = true;
    controller.catalogues[WorkspaceAdminResource.roles] = [
      WorkspaceAdminRecord({
        'id': sales,
        'name': 'Sales tasks',
        'code': 'sales_staff',
        'permissions': ['sales.view'],
      }),
      WorkspaceAdminRecord({
        'id': inventory,
        'name': 'Inventory tasks',
        'code': 'inventory_staff',
        'permissions': ['inventory.view'],
      }),
    ];
  });
  tearDown(() => controller.dispose());
  Future<ProviderContainer> mount(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        workspaceAdminControllerProvider.overrideWithValue(controller),
        workspaceStaffGatewayProvider.overrideWithValue(gateway),
        workspaceStaffRecoveryProvider.overrideWithValue(recovery),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: JentraTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => StaffAccountDialog(controller: controller),
                ),
                child: const Text('Open staff form'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open staff form'));
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> password(WidgetTester tester) async {
    for (final name in ['staff-password', 'staff-password-confirmation']) {
      final field = find.byKey(ValueKey(name));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, 'Synthetic-password-only12!');
    }
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester) async {
    for (final entry in {
      'staff-display-name': 'Sales colleague',
      'staff-username': 'company_sales',
    }.entries) {
      final field = find.byKey(ValueKey(entry.key));
      await tester.ensureVisible(field);
      await tester.enterText(field, entry.value);
    }
    await password(tester);
    for (final label in ['Sales tasks', 'Inventory tasks']) {
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).hitTestable());
      await tester.pumpAndSettle();
    }
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('staff-create-submit')));
    await tester.pumpAndSettle();
  }

  testWidgets('admin creates one account with both assigned sections', (
    tester,
  ) async {
    await mount(tester);
    await fill(tester);
    await submit(tester);
    expect(gateway.sent, hasLength(1));
    expect(gateway.sent.single['role_ids'], [sales, inventory]);
    expect(recovery.request, isNull);
    expect(find.byType(StaffAccountDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'uncertain creation freezes details and retries the original identity',
    (tester) async {
      gateway.uncertain = true;
      await mount(tester);
      await fill(tester);
      await submit(tester);
      expect(find.text('Retry original request'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('staff-username')))
            .enabled,
        isFalse,
      );
      expect(
        recovery.request!.toJson().keys,
        unorderedEquals(['request_id', 'username', 'display_name', 'role_ids']),
      );
      await submit(tester);
      expect(gateway.sent, hasLength(2));
      expect(gateway.sent.last, gateway.sent.first);
    },
  );
  testWidgets(
    'reopening restores request identity and requires password re-entry',
    (tester) async {
      gateway.uncertain = true;
      await mount(tester);
      await fill(tester);
      await submit(tester);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open staff form'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('staff-password')))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('staff-username')))
            .controller!
            .text,
        'company_sales',
      );
      await password(tester);
      await submit(tester);
      expect(gateway.sent.last, gateway.sent.first);
    },
  );
  testWidgets(
    'changed delegation releases recovery so another account can be created',
    (tester) async {
      gateway.accessChanged = true;
      await mount(tester);
      await fill(tester);
      await submit(tester);
      expect(recovery.request, isNull);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('staff-username')))
            .enabled,
        isTrue,
      );
      gateway.accessChanged = false;
      await fill(tester);
      await tester.enterText(
        find.byKey(const ValueKey('staff-username')),
        'another_staff',
      );
      await submit(tester);
      expect(gateway.sent, hasLength(2));
      expect(
        gateway.sent.last['request_id'],
        isNot(gateway.sent.first['request_id']),
      );
      expect(find.byType(StaffAccountDialog), findsNothing);
    },
  );

  testWidgets(
    'authority change wipes entered passwords and blocks submission',
    (tester) async {
      final container = await mount(tester);
      await fill(tester);
      final secret = tester
          .widget<TextFormField>(find.byKey(const ValueKey('staff-password')))
          .controller!;
      container.updateOverrides([
        workspaceAdminControllerProvider.overrideWithValue(null),
        workspaceStaffGatewayProvider.overrideWithValue(gateway),
        workspaceStaffRecoveryProvider.overrideWithValue(recovery),
      ]);
      await tester.pumpAndSettle();
      expect(secret.text, isEmpty);
      expect(find.text('Administrator access changed'), findsOneWidget);
      expect(find.byKey(const ValueKey('staff-create-submit')), findsNothing);
      expect(gateway.sent, isEmpty);
    },
  );
}
