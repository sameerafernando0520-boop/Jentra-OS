import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_people_platform.dart';
import 'package:jentra_desktop/src/features/people/employee_controller.dart';
import 'package:jentra_desktop/src/features/people/employee_screen.dart';

final class _Keys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

final class _Employees implements EmployeeRepository {
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  String? failure, readFailure;
  bool failAfterConfirm = false;
  Map<String, Object?>? employee;

  Map<String, Object?> record({int version = 1}) => {
    'id': 'employee',
    'tenant_id': 'tenant',
    'legal_entity_id': 'entity',
    'branch_id': 'branch',
    'code': 'EMP-01',
    'display_name': 'Synthetic Employee',
    'work_email': 'synthetic@jentra.test',
    'version': version,
    'assignments': [
      {
        'id': 'assignment',
        'spell_id': 'spell',
        'branch_id': 'branch',
        'start_date': '2026-09-20',
        'end_date_exclusive': null,
        'job_title': 'Technician',
        'employment_type': 'permanent',
      },
    ],
  };

  void _check() {
    if (readFailure != null) {
      throw DomainError(
        code: readFailure!,
        message: readFailure == 'FEATURE_NOT_ENTITLED'
            ? 'People is not enabled on this business plan.'
            : readFailure!,
      );
    }
  }

  Map<String, Object?> _page(TenantContext scope, List<Object?> items) => {
    'tenant_id': scope.tenantId,
    'legal_entity_id': scope.legalEntityId,
    'branch_id': scope.branchId,
    'items': items,
    'next_cursor': null,
  };

  @override
  Future<Map<String, Object?>> directory(
    TenantContext scope, {
    String? asOfDate,
    String status = 'employed',
    String search = '',
    String? after,
  }) async {
    _check();
    return {
      ..._page(scope, [if (employee != null) employee]),
      'as_of': asOfDate ?? '2026-09-25',
      'status': status,
    };
  }

  @override
  Future<Map<String, Object?>> detail(
    TenantContext scope,
    String id,
    String asOfDate,
    String status,
  ) async {
    _check();
    return employee ?? record();
  }

  @override
  Future<Map<String, Object?>> history(
    TenantContext scope,
    String id, {
    String? after,
  }) async => _page(scope, [
    {
      'id': 'event',
      'action': 'create',
      'effective_date': '2026-09-20',
      'reason': null,
    },
  ]);

  @override
  Future<Map<String, Object?>> branches(
    TenantContext scope, {
    String search = '',
  }) async => _page(scope, [
    {'id': 'branch', 'name': 'Head Office', 'code': 'HQ'},
  ]);

  @override
  Future<Map<String, Object?>> execute(
    String action,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    if (failure != null) throw DomainError(code: failure!, message: failure!);
    employee = record(version: command.expectedEntityVersion! + 1);
    if (failAfterConfirm) readFailure = 'READ_FAILED';
    return employee!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  const scope = TenantContext(
    tenantId: 'tenant',
    actorId: 'actor',
    legalEntityId: 'entity',
    branchId: 'branch',
  );
  const permissions = {
    'people.view',
    'people.employees.view',
    'people.employees.manage',
    'people.employment.manage',
    'people.employees.history.view',
  };
  late JentraLocalDatabase db;
  late EmployeeDraftStore drafts;
  late _Employees repository;
  late EmployeeController controller;

  EmployeeController make({bool online = true}) => EmployeeController(
    scope: scope,
    repository: repository,
    drafts: drafts,
    permissions: permissions,
    online: online,
  );

  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = EmployeeDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: _Keys())),
    );
    repository = _Employees();
    controller = make();
  });
  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  test(
    'AC-419 uncertain employee request replays its sealed envelope',
    () async {
      await controller.initialize();
      controller.beginCreate();
      controller.edit('code', 'EMP-01');
      controller.edit('display_name', 'Synthetic Employee');
      controller.edit('job_title', 'Technician');
      repository.failure = 'UNCERTAIN_RESULT';
      await controller.submit();
      expect(controller.local?.pending, isNotNull);
      final first = repository.commands.single.toJson((value) => value);
      controller.edit('code', 'EMP-02');
      expect(controller.form?['code'], 'EMP-01');
      controller.dispose();
      controller = make();
      await controller.initialize();
      expect(controller.local?.pending, isNotNull);
      repository.failure = null;
      await controller.submit();
      expect(repository.commands.last.toJson((value) => value), first);
      expect(controller.local, isNull);
      expect(controller.selected?['version'], 1);
    },
  );

  test(
    'confirmed action survives optional directory refresh failure',
    () async {
      await controller.initialize();
      controller.beginCreate();
      controller.edit('code', 'EMP-01');
      controller.edit('display_name', 'Synthetic Employee');
      controller.edit('job_title', 'Technician');
      repository.failAfterConfirm = true;
      await controller.submit();
      expect(controller.local, isNull);
      expect(controller.selected?['id'], 'employee');
      expect(controller.error, contains('Action confirmed'));
    },
  );

  test('permission revocation clears loaded employee data', () async {
    repository.employee = repository.record();
    await controller.initialize();
    await controller.open('employee');
    expect(controller.selected, isNotNull);
    repository.readFailure = 'PERMISSION_DENIED';
    await controller.refresh();
    expect(controller.accessDenied, isTrue);
    expect(controller.items, isEmpty);
    expect(controller.selected, isNull);
    expect(controller.events, isEmpty);
  });

  test(
    'plan revocation clears loaded data and recovery requires a fresh read',
    () async {
      repository.employee = repository.record();
      await controller.initialize();
      await controller.open('employee');
      repository.readFailure = 'FEATURE_NOT_ENTITLED';
      await controller.refresh();
      expect(controller.accessDenied, isTrue);
      expect(controller.items, isEmpty);
      expect(controller.selected, isNull);
      repository.readFailure = null;
      await controller.refresh();
      expect(controller.accessDenied, isFalse);
      expect(controller.items, hasLength(1));
    },
  );

  test('plan loss retains an uncertain command until access returns', () async {
    await controller.initialize();
    controller.beginCreate();
    controller.edit('code', 'EMP-01');
    controller.edit('display_name', 'Synthetic Employee');
    controller.edit('job_title', 'Technician');
    repository.failure = 'UNCERTAIN_RESULT';
    await controller.submit();
    final originalId = controller.local!.pending!.envelope.commandId;
    repository.failure = 'FEATURE_NOT_ENTITLED';
    await controller.submit();
    expect(controller.accessDenied, isTrue);
    expect(controller.local!.pending!.envelope.commandId, originalId);
    repository.failure = null;
    await controller.refresh();
    await controller.submit();
    expect(controller.local, isNull);
    expect(repository.commands.last.commandId, originalId);
  });

  testWidgets('plan denial hides employee data and offers a fresh retry', (
    tester,
  ) async {
    repository.employee = repository.record();
    await controller.initialize();
    repository.readFailure = 'FEATURE_NOT_ENTITLED';
    await controller.refresh();
    tester.view.physicalSize = const Size(1024, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: JentraTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: EmployeeWorkspace(controller: controller)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('People is not enabled on this business plan.'),
      findsOneWidget,
    );
    expect(find.textContaining('Synthetic Employee'), findsNothing);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(EmployeeWorkspace),
      matchesGoldenFile('goldens/employee_plan_denied_light_200.png'),
    );
    repository.readFailure = null;
    await tester.tap(find.text('Retry employee access'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Synthetic Employee'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
      '${dark ? 'dark' : 'light'} employee workspace renders at 200 percent text',
      (tester) async {
        controller.asOfDate = '2026-09-25';
        controller.items = [repository.record()];
        controller.selected = repository.record();
        controller.events = [
          {
            'id': 'event',
            'action': 'create',
            'effective_date': '2026-09-20',
            'reason': 'Synthetic onboarding',
          },
        ];
        tester.view.physicalSize = const Size(1024, 1500);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? JentraTheme.dark() : JentraTheme.light(),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(body: EmployeeWorkspace(controller: controller)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Employees'), findsOneWidget);
        expect(find.text('Synthetic Employee'), findsWidgets);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(EmployeeWorkspace),
          matchesGoldenFile(
            'goldens/employee_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
      },
    );
  }

  testWidgets('employee editor keeps actions reachable at 200 percent text', (
    tester,
  ) async {
    controller.asOfDate = '2026-09-25';
    tester.view.physicalSize = const Size(1024, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: JentraTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(body: EmployeeWorkspace(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New employee'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Confirm action'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(AlertDialog),
      matchesGoldenFile('goldens/employee_editor_light_200.png'),
    );
  });
}
