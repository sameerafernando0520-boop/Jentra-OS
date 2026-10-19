import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_desktop/src/features/people/organization_controller.dart';
import 'package:jentra_desktop/src/features/people/organization_screen.dart';
import 'package:jentra_desktop/src/shell/navigation.dart';

const scope = TenantContext(
  tenantId: '10000000-0000-0000-0000-000000000001',
  legalEntityId: '10000000-0000-0000-0000-000000000002',
  branchId: '10000000-0000-0000-0000-000000000003',
  actorId: '10000000-0000-0000-0000-000000000004',
);
const departmentId = '20000000-0000-0000-0000-000000000001';
const revisionId = '30000000-0000-0000-0000-000000000001';
const employeeId = '40000000-0000-0000-0000-000000000001';
const permissions = {
  'people.view',
  'people.organization.view',
  'people.organization.manage',
  'people.employees.view',
  'people.calendars.view',
};

class _Keys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _Organization implements OrganizationRepository {
  String? readFailure, commandFailure, failAfterConfirm;
  Completer<void>? gate;
  int version = 1;
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  DepartmentEntry get entry => DepartmentEntry.fromJson({
    'id': departmentId,
    'revision_id': revisionId,
    'code': 'OPS',
    'name': 'Synthetic Operations',
    'parent_id': null,
    'version': version,
    'start_date': '2026-09-01',
    'end_date_exclusive': null,
  });
  void check() {
    if (readFailure != null) {
      throw DomainError(
        code: readFailure!,
        message: 'Organization read unavailable.',
      );
    }
  }

  @override
  Future<DepartmentEntry> department(
    TenantContext scope,
    String id,
    CivilDate asOf,
  ) async {
    check();
    return entry;
  }

  @override
  Future<CalendarPage<DepartmentEntry>> departments(
    TenantContext scope,
    CivilDate asOf, {
    String search = '',
    String? after,
  }) async {
    await gate?.future;
    check();
    return CalendarPage([if (after == null) entry], null);
  }

  @override
  Future<CalendarPage<DepartmentRevision>> departmentHistory(
    TenantContext scope,
    String departmentId, {
    String? after,
  }) async {
    check();
    return CalendarPage([
      DepartmentRevision.fromJson({
        'id': revisionId,
        'name': 'Synthetic Operations',
        'parent_id': null,
        'start_date': '2026-09-01',
        'end_date_exclusive': null,
        'reason': 'Synthetic organization setup',
        'recorded_by': scope.actorId,
        'recorded_at': '2026-09-26T00:00:00Z',
        'supersedes_id': null,
        'superseded_at': null,
      }),
    ], null);
  }

  @override
  Future<OrganizationEmployeeState> employee(
    TenantContext scope,
    String id,
    CivilDate asOf, {
    String? after,
  }) async {
    check();
    return OrganizationEmployeeState(id, 1, asOf, CalendarPage([], null));
  }

  @override
  Future<OrganizationConfirmation> execute(
    String action,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    if (commandFailure != null) {
      throw DomainError(
        code: commandFailure!,
        message: 'Synthetic command failure.',
      );
    }
    readFailure = failAfterConfirm;
    return OrganizationConfirmation(
      id: command.payload['id'] as String,
      version: command.expectedEntityVersion! + 1,
      departmentRevisionId: command.payload['revision_id'] as String?,
    );
  }
}

class _Employees implements EmployeeRepository {
  Map<String, Object?> row(TenantContext scope) => {
    'id': employeeId,
    'tenant_id': scope.tenantId,
    'legal_entity_id': scope.legalEntityId,
    'branch_id': scope.branchId,
    'code': 'EMP-01',
    'display_name': 'Synthetic Technician',
    'work_email': null,
    'version': 1,
    'assignments': [
      {
        'id': revisionId,
        'spell_id': revisionId,
        'branch_id': scope.branchId,
        'start_date': '2026-09-01',
        'end_date_exclusive': null,
        'job_title': 'Technician',
        'employment_type': 'permanent',
      },
    ],
  };
  @override
  Future<Map<String, Object?>> directory(
    TenantContext scope, {
    String? asOfDate,
    String status = 'employed',
    String search = '',
    String? after,
  }) async => {
    'items': [if (after == null) row(scope)],
    'as_of': asOfDate,
  };
  @override
  Future<Map<String, Object?>> detail(
    TenantContext scope,
    String id,
    String asOfDate,
    String status,
  ) async => row(scope);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Calendars implements WorkCalendarRepository {
  @override
  Future<CalendarDirectoryPage> directory(
    TenantContext scope, {
    String? asOfDate,
    String search = '',
    String? after,
  }) async =>
      CalendarDirectoryPage(CivilDate.parse(asOfDate!), CalendarPage([], null));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    const base = 'packages/jentra_design_system/assets/fonts/';
    await (FontLoader(JentraTypography.sansFamily)
          ..addFont(rootBundle.load('${base}Manrope-Regular.ttf'))
          ..addFont(rootBundle.load('${base}Manrope-SemiBold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  late JentraLocalDatabase db;
  late _Organization repository;
  late OrganizationController c;
  setUp(() async {
    db = JentraLocalDatabase(NativeDatabase.memory());
    repository = _Organization();
    c = OrganizationController(
      scope: scope,
      repository: repository,
      employees: _Employees(),
      calendars: _Calendars(),
      drafts: organizationDrafts(
        EncryptedDraftRepository(db, DraftCipher(keyStore: _Keys())),
      ),
      permissions: permissions,
      online: true,
    );
    c.asOfDate = '2026-09-26';
    await c.initialize();
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  void create() {
    c.beginDepartment();
    c.edit('code', 'DELIVERY');
    c.edit('name', 'Delivery');
    c.edit('reason', 'Synthetic creation');
  }

  Widget app({
    bool editor = false,
    bool dark = false,
    JentraDensity density = JentraDensity.comfortable,
    double scale = 1,
  }) => ProviderScope(
    overrides: [organizationControllerProvider.overrideWithValue(c)],
    child: MaterialApp(
      theme: dark
          ? JentraTheme.dark(density: density)
          : JentraTheme.light(density: density),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: RepaintBoundary(
          key: const Key('organization-preview'),
          child: Scaffold(
            body: editor
                ? OrganizationEditor(controller: c)
                : OrganizationWorkspace(controller: c),
          ),
        ),
      ),
    ),
  );
  test(
    'AC-419 uncertain command retains its exact original IDs and body',
    () async {
      create();
      repository.commandFailure = 'UNCERTAIN_RESULT';
      await c.submit();
      final original = repository.commands.single;
      expect(c.local!.pending, isNotNull);
      c.edit('name', 'Must not overwrite');
      expect(c.form!['name'], 'Delivery');
      repository.commandFailure = null;
      await c.submit();
      expect(
        repository.commands.last.toJson((p) => p),
        original.toJson((p) => p),
      );
      expect(c.confirmed, isNotNull);
      expect(c.local, isNull);
    },
  );
  test(
    'AC-401 permission loss clears visible organization and recovered values',
    () async {
      create();
      await c.save();
      repository.readFailure = 'PERMISSION_DENIED';
      await c.refresh();
      expect(c.departments, isEmpty);
      expect(c.recovery, isEmpty);
      expect(c.form, isNull);
      expect(c.local, isNull);
      expect(c.accessDenied, isTrue);
    },
  );
  test('AC-419 confirmation survives optional history-read failure', () async {
    create();
    repository.failAfterConfirm = 'UNCERTAIN_RESULT';
    await c.submit();
    expect(c.confirmed, isNotNull);
    expect(c.message, 'Organization change confirmed.');
    expect(c.local, isNull);
    expect(c.error, contains('confirmed'));
  });
  test('AC-401 disposed context discards a late directory response', () async {
    repository.gate = Completer<void>();
    final work = c.refresh();
    c.dispose();
    repository.gate!.complete();
    await work;
    expect(c.departments, isEmpty);
    c = OrganizationController(
      scope: scope,
      repository: repository,
      employees: null,
      calendars: null,
      drafts: organizationDrafts(
        EncryptedDraftRepository(db, DraftCipher(keyStore: _Keys())),
      ),
      permissions: permissions,
      online: true,
    );
  });
  test(
    'AC-419 stale department draft requires explicit comparison and retention',
    () async {
      await c.openDepartment(repository.entry);
      c.beginDepartment(revise: true);
      c.edit('reason', 'Synthetic revision');
      repository.commandFailure = 'VERSION_CONFLICT';
      await c.submit();
      expect(c.conflict, isTrue);
      expect(c.local!.pending, isNull);
      repository.version = 2;
      await c.compare();
      expect(c.comparedVersion, 2);
      await c.replaceConflict();
      expect(c.expectedVersion, 2);
      expect(c.conflict, isFalse);
    },
  );
  testWidgets('AC-403 missing assignment stays visibly unconfigured', (
    tester,
  ) async {
    await c.openEmployee(employeeId);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.textContaining('unconfigured on this date'),
    );
    expect(find.textContaining('unconfigured on this date'), findsOneWidget);
    expect(find.text('Assign organization'), findsOneWidget);
  });
  test(
    'AC-401 navigation requires both organization and People capabilities',
    () {
      expect(
        visibleJentraDestinations({'people.view'})
            .any((d) => d.path == '/people/organization'),
        isFalse,
      );
      expect(
        visibleJentraDestinations(permissions)
            .any((d) => d.path == '/people/organization'),
        isTrue,
      );
    },
  );
  testWidgets('AC-419 keyboard focus reaches editor fields and actions', (
    tester,
  ) async {
    create();
    await tester.pumpWidget(app(editor: true));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(TextFormField, 'Reserved department code'),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, isNotNull);
    expect(tester.takeException(), isNull);
  });
  for (final dark in [false, true]) {
    for (final density in JentraDensity.values) {
      testWidgets(
        'AC-419 ${dark ? 'dark' : 'light'} ${density.name} organization at 200 percent',
        (tester) async {
          tester.view.physicalSize = const Size(1024, 720);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await c.openDepartment(repository.entry);
          await tester.pumpWidget(app(dark: dark, density: density, scale: 2));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Create department').hitTestable(), findsOneWidget);
          await expectLater(
            find.byKey(const Key('organization-preview')),
            matchesGoldenFile(
              'goldens/organization_${dark ? 'dark' : 'light'}_${density.name}_200.png',
            ),
          );
          await tester.scrollUntilVisible(
            find.text('Choose employee'),
            250,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('Choose employee').hitTestable(), findsOneWidget);
        },
      );
    }
    testWidgets(
      'AC-419 ${dark ? 'dark' : 'light'} organization editor at 200 percent',
      (tester) async {
        tester.view.physicalSize = const Size(1024, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        create();
        await tester.pumpWidget(app(editor: true, dark: dark, scale: 2));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Confirm change').hitTestable(), findsOneWidget);
        expect(find.text('Close').hitTestable(), findsOneWidget);
        await expectLater(
          find.byKey(const Key('organization-preview')),
          matchesGoldenFile(
            'goldens/organization_editor_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
        await tester.ensureVisible(
          find.widgetWithText(TextFormField, 'Reason'),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('AC-419 wide organization workspace retains desktop controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await c.openDepartment(repository.entry);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Apply filters').hitTestable(), findsOneWidget);
    expect(find.text('Revise department').hitTestable(), findsOneWidget);
  });
}
