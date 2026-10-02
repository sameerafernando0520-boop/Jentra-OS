import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_people_platform.dart';
import 'package:jentra_desktop/src/features/people/workforce_controller.dart';
import 'package:jentra_desktop/src/features/people/workforce_screen.dart';
import 'package:jentra_desktop/src/shell/navigation.dart';

const scope = TenantContext(
  tenantId: '10000000-0000-0000-0000-000000000001',
  legalEntityId: '10000000-0000-0000-0000-000000000002',
  branchId: '10000000-0000-0000-0000-000000000003',
  actorId: '10000000-0000-0000-0000-000000000004',
);
const id = '20000000-0000-0000-0000-000000000001',
    revision = '30000000-0000-0000-0000-000000000001';
const permissions = {
  'people.view',
  'people.employees.view',
  'people.organization.view',
  'people.calendars.view',
  'people.attendance.view',
  'people.attendance.manage',
  'people.attendance.import',
  'people.attendance.approve',
  'people.leave.view',
  'people.leave.manage',
  'people.leave.approve',
  'people.leave.policy.manage',
  'people.leave.adjust',
  'people.work_claims.view',
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

class _ClockFiles implements ClockImportFiles {
  String? content =
      'source_key,observed_utc\nSYN-1,2026-09-30T03:30:00Z\nSYN-2,2026-09-30T11:30:00Z';
  Completer<void>? gate;
  @override
  Future<String?> chooseCsv() async {
    await gate?.future;
    return content;
  }
}

Map<String, Object?> attendanceRow([int version = 1]) => {
  'id': id,
  'tenant_id': scope.tenantId,
  'legal_entity_id': scope.legalEntityId,
  'branch_id': scope.branchId,
  'employee_id': id,
  'version': version,
  'status': 'draft',
  'submitted_by': null,
  'decided_by': null,
  'active_claim_id': null,
  'created_by': scope.actorId,
  'created_at': '2026-09-30T00:00:00Z',
  'revision': {
    'id': revision,
    'version': version,
    'calendar_version_id': revision,
    'start_local': '2026-09-30T09:00:00',
    'end_local': '2026-09-30T17:00:00',
    'start_offset_seconds': 19800,
    'end_offset_seconds': 19800,
    'start_utc': '2026-09-30T03:30:00Z',
    'end_utc': '2026-09-30T11:30:00Z',
    'breaks': [],
    'gross_seconds': 28800,
    'break_seconds': 0,
    'payable_seconds': 28800,
    'reason': 'Synthetic recorded attendance',
    'raw_start_id': null,
    'raw_end_id': null,
    'supersedes_revision_id': null,
    'recorded_by': scope.actorId,
    'recorded_at': '2026-09-30T00:00:00Z',
  },
};

class _Repository implements WorkforceRepository {
  String? failure, readFailure;
  bool denied = false;
  int recordVersion = 1, authorizations = 0;
  Completer<void>? gate;
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  @override
  Future<void> authorize(
    TenantContext scope,
    String? employeeId,
    String capability,
  ) async {
    authorizations++;
    if (denied) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Current access was revoked.',
      );
    }
  }

  void check() {
    if (readFailure != null) {
      throw DomainError(
        code: readFailure!,
        message: 'Synthetic read unavailable.',
      );
    }
  }

  @override
  Future<WorkforcePage<LeavePolicy>> policies(
    TenantContext scope, {
    String? after,
  }) async {
    check();
    return const WorkforcePage([], null);
  }

  @override
  Future<WorkforcePage<AttendanceEntry>> attendance(
    TenantContext scope,
    String employeeId, {
    String? after,
  }) async {
    await gate?.future;
    check();
    return WorkforcePage([
      if (after == null) AttendanceEntry.fromJson(attendanceRow(recordVersion)),
    ], null);
  }

  @override
  Future<WorkforcePage<RawClockEvent>> rawEvents(
    TenantContext scope,
    String employeeId, {
    String? after,
  }) async => const WorkforcePage([], null);
  @override
  Future<WorkforcePage<RawClockBatch>> clockBatches(
    TenantContext scope,
    String employeeId, {
    String? after,
  }) async => const WorkforcePage([], null);

  @override
  Future<WorkforceDetail<AttendanceEntry, AttendanceHistoryEntry>>
  attendanceDetail(
    TenantContext scope,
    String entryId, {
    String? after,
  }) async => WorkforceDetail(
    AttendanceEntry.fromJson(attendanceRow(recordVersion)),
    const WorkforcePage([], null),
  );
  @override
  Future<Map<String, Object?>> execute(
    WorkforceCommandKind kind,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    if (failure != null) {
      throw DomainError(
        code: failure!,
        message: 'Synthetic command unavailable.',
      );
    }
    return {
      'id': command.payload['id'],
      'version': command.expectedEntityVersion! + 1,
    };
  }

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
  late EncryptedDraftRepository encrypted;
  late _Repository repository;
  late WorkforceController c;
  late DateTime now;
  late _ClockFiles clockFiles;
  setUp(() async {
    db = JentraLocalDatabase(NativeDatabase.memory());
    encrypted = EncryptedDraftRepository(db, DraftCipher(keyStore: _Keys()));
    repository = _Repository();
    now = DateTime.utc(2026, 9, 30);
    clockFiles = _ClockFiles();
    c = WorkforceController(
      scope: scope,
      repository: repository,
      employees: null,
      organizations: null,
      calendars: null,
      drafts: {
        for (final kind in [
          WorkforceCommandKind.attendance,
          WorkforceCommandKind.leavePolicy,
          WorkforceCommandKind.leaveGrant,
        ])
          kind: workforceDrafts(encrypted, kind),
      },
      leaveDrafts: SensitiveLeaveDraftStore(
        encrypted,
        (s, e) => repository.authorize(s, e, 'people.leave.view'),
        clock: () => now,
      ),
      permissions: permissions,
      online: true,
      clock: () => now,
      monitor: false,
      clockFiles: clockFiles,
    );
    c.asOfDate = '2026-09-30';
    await c.initialize();
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  test(
    'clock CSV preview retains stable sealed IDs and exact encrypted retry',
    () async {
      c.employeeId = id;
      await c.begin(WorkforceCommandKind.attendance, 'raw_import_batch');
      await c.chooseClockFile();
      expect(c.error, isNull);
      expect((c.form!['records'] as List).length, 2);
      final original = c.form!['records'];
      repository.failure = 'UNCERTAIN_RESULT';
      await c.submit();
      expect(c.pending, isNotNull);
      await c.chooseClockFile();
      expect(c.form!['records'], original);
      await c.submit();
      expect(repository.commands.length, 2);
      expect(
        repository.commands.last.toJson((p) => p),
        repository.commands.first.toJson((p) => p),
      );
      c.setField('source_system', 'Changed');
      expect(c.form!['source_system'], 'Synthetic clock import');
    },
  );
  test(
    'source-system edit invalidates batch and malformed file cannot submit',
    () async {
      c.employeeId = id;
      await c.begin(WorkforceCommandKind.attendance, 'raw_import_batch');
      await c.chooseClockFile();
      c.setField('source_system', 'Other synthetic clock');
      expect(c.form!['records'], isEmpty);
      expect(c.form!['manifest_digest'], '');
      clockFiles.content =
          'source_key,observed_utc\nSYN-1,2026-02-30T03:30:00Z';
      await c.chooseClockFile();
      expect(c.error, isNotNull);
      await c.submit();
      expect(repository.commands, isEmpty);
    },
  );
  test('late chosen file cannot restore an old context', () async {
    c.employeeId = id;
    await c.begin(WorkforceCommandKind.attendance, 'raw_import_batch');
    clockFiles.gate = Completer<void>();
    final choosing = c.chooseClockFile();
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    clockFiles.gate!.complete();
    await choosing;
    expect(c.form, isNull);
    expect(repository.commands, isEmpty);
  });
  Future<void> raw() async {
    c.employeeId = id;
    c.employeeName = 'Synthetic Employee · W4-01';
    await c.begin(WorkforceCommandKind.attendance, 'raw_import');
    c.setField('source_key', 'SYNTHETIC-EVENT-1');
    c.setField('observed_utc', '2026-09-30T03:30:00Z');
    await c.checksumRawEvent();
  }

  Widget app({
    bool editor = false,
    bool dark = false,
    JentraDensity density = JentraDensity.comfortable,
    double scale = 1,
  }) => MaterialApp(
    theme: dark
        ? JentraTheme.dark(density: density)
        : JentraTheme.light(density: density),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: RepaintBoundary(
        key: const Key('workforce-preview'),
        child: Scaffold(
          body: editor
              ? WorkforceEditor(controller: c)
              : WorkforceWorkspace(controller: c),
        ),
      ),
    ),
  );

  test('uncertain clock import keeps exact envelope and prevents editing or deletion', () async {
    await raw();
    repository.failure = 'UNCERTAIN_RESULT';
    await c.submit();
    final original = repository.commands.single.toJson((p) => p);
    expect(c.pending, isNotNull);
    c.setField('source_key', 'Must not replace');
    expect(c.form!['source_key'], 'SYNTHETIC-EVENT-1');
    await c.discard();
    expect(c.pending, isNotNull);
    repository.failure = null;
    await c.submit();
    expect(repository.commands.last.toJson((p) => p), original);
    expect(c.confirmed, isNotNull);
    expect(c.local, isNull);
  });
  test('version conflict requires comparison and explicit replacement before a new command', () async {
    c.employeeId = id;
    c.selectedAttendance = AttendanceEntry.fromJson(attendanceRow());
    await c.transition(WorkforceCommandKind.attendance, 'correct');
    c.setField('reason', 'Synthetic correction');
    repository.failure = 'VERSION_CONFLICT';
    await c.submit();
    expect(c.conflict, isTrue);
    expect(c.pending, isNull);
    await c.replaceConflict();
    expect(c.expectedVersion, 1);
    repository.recordVersion = 2;
    await c.compareConflict();
    expect(c.comparedVersion, 2);
    await c.replaceConflict();
    expect(c.expectedVersion, 2);
    expect(c.conflict, isFalse);
    repository.failure = null;
    await c.submit();
    expect(
      repository.commands.last.commandId,
      isNot(repository.commands.first.commandId),
    );
    expect(repository.commands.last.expectedEntityVersion, 2);
  });
  test('confirmed result survives an optional read failure', () async {
    await raw();
    repository.readFailure = 'OFFLINE';
    await c.submit();
    expect(c.confirmed, isNotNull);
    expect(c.pending, isNull);
    expect(c.error, isNull);
    expect(c.message, contains('Command confirmed'));
  });
  test(
    'revoked current access clears visible records and local private text',
    () async {
      c.employeeId = id;
      c.attendance = [AttendanceEntry.fromJson(attendanceRow())];
      repository.denied = true;
      await c.checkAccess();
      expect(c.accessDenied, isTrue);
      expect(c.attendance, isEmpty);
      expect(c.employeeId, isNull);
      expect(c.form, isNull);
    },
  );
  test(
    'initial employee-scoped access check waits for employee selection',
    () async {
      await c.checkAccess();
      expect(repository.authorizations, 0);
      expect(c.current, isTrue);
    },
  );
  test(
    'late workspace response cannot restore records after disposal',
    () async {
      c.employeeId = id;
      repository.gate = Completer<void>();
      final future = c.refresh();
      await Future<void>.delayed(Duration.zero);
      c.dispose();
      repository.gate!.complete();
      await future;
      expect(c.attendance, isEmpty);
      expect(c.employeeId, isNull);
      c = WorkforceController(
        scope: scope,
        repository: repository,
        employees: null,
        organizations: null,
        calendars: null,
        drafts: {},
        leaveDrafts: SensitiveLeaveDraftStore(encrypted, (s, e) async {}),
        permissions: permissions,
        online: false,
        monitor: false,
      );
    },
  );
  test('private leave body expires in memory and encrypted recovery', () async {
    c.kind = WorkforceCommandKind.leaveRequest;
    c.employeeId = id;
    c.form = {
      'action': 'create',
      'id': id,
      'employee_id': id,
      'policy_version_id': revision,
      'calendar_version_id': revision,
      'start_local': '2026-09-30T09:00:00',
      'end_local': '2026-09-30T17:00:00',
      'start_offset_seconds': 19800,
      'end_offset_seconds': 19800,
      'reason': 'SYNTHETIC_PRIVATE_REASON',
    };
    await c.saveLocal();
    expect(c.privateLocal, isNotNull);
    now = now.add(const Duration(hours: 24));
    await c.checkAccess();
    expect(c.form, isNull);
    expect(c.privateLocal, isNull);
    expect(await c.leaveDrafts.load(scope, id, id), isNull);
  });
  test(
    'expired private text cannot be resaved before the periodic access check',
    () async {
      c.kind = WorkforceCommandKind.leaveRequest;
      c.employeeId = id;
      c.form = {
        'action': 'create',
        'id': id,
        'employee_id': id,
        'policy_version_id': revision,
        'calendar_version_id': revision,
        'start_local': '2026-09-30T09:00:00',
        'end_local': '2026-09-30T17:00:00',
        'start_offset_seconds': 19800,
        'end_offset_seconds': 19800,
        'reason': 'SYNTHETIC_PRIVATE_REASON',
      };
      await c.saveLocal();
      now = now.add(const Duration(hours: 24));
      await c.saveLocal();
      expect(c.form, isNull);
      expect(await c.leaveDrafts.load(scope, id, id), isNull);
      expect(repository.commands, isEmpty);
    },
  );
  test(
    'saved exact request resumes when the employee directory is unavailable',
    () async {
      await raw();
      repository.failure = 'UNCERTAIN_RESULT';
      await c.submit();
      final original = repository.commands.single.toJson((p) => p);
      final saved = WorkforceSavedDraft(
        WorkforceCommandKind.attendance,
        c.local!,
      );
      c.form = null;
      c.local = null;
      c.kind = null;
      c.employeeId = null;
      c.employeeName = null;
      await c.resume(saved);
      expect(c.pending, isNotNull);
      expect(c.error, isNull);
      repository.failure = null;
      await c.submit();
      expect(repository.commands.last.toJson((p) => p), original);
    },
  );
  test(
    'workforce navigation requires module and a specific view capability',
    () {
      expect(
        visibleJentraDestinations({'people.view'})
            .any((r) => r.path == '/people/workforce'),
        isFalse,
      );
      expect(
        visibleJentraDestinations({'people.attendance.view'})
            .any((r) => r.path == '/people/workforce'),
        isFalse,
      );
      expect(
        visibleJentraDestinations({'people.view', 'people.attendance.view'})
            .any((r) => r.path == '/people/workforce'),
        isTrue,
      );
    },
  );
  for (final dark in [false, true]) {
    for (final density in JentraDensity.values) {
      testWidgets(
        'clock import ${dark ? 'dark' : 'light'} ${density.name} at 200 percent',
        (tester) async {
          tester.view.physicalSize = density == JentraDensity.compact
              ? const Size(1024, 720)
              : const Size(1920, 1080);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          c.employeeId = id;
          c.employeeName = 'Synthetic Employee';
          await c.begin(WorkforceCommandKind.attendance, 'raw_import_batch');
          await c.chooseClockFile();
          await tester.pumpWidget(
            app(editor: true, dark: dark, density: density, scale: 2),
          );
          await tester.pumpAndSettle();
          expect(
            find.text('Choose and preview clock CSV').hitTestable(),
            findsOneWidget,
          );
          expect(find.text('1. SYN-1'), findsOneWidget);
          await expectLater(
            find.byKey(const Key('workforce-preview')),
            matchesGoldenFile(
              'goldens/clock_import_${dark ? 'dark' : 'light'}_${density.name}_200.png',
            ),
          );
          await tester.tap(find.byType(TextFormField).first);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(
            Focus.of(tester.element(find.text('Choose and preview clock CSV')))
                .hasFocus,
            isTrue,
          );
          await tester.scrollUntilVisible(
            find.text('Confirm command'),
            250,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('Confirm command').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
    for (final density in JentraDensity.values) {
      testWidgets(
        '${dark ? 'dark' : 'light'} ${density.name} workforce at 200 percent',
        (tester) async {
          tester.view.physicalSize = const Size(1024, 720);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          c.employeeId = id;
          c.employeeName = 'Synthetic Employee · W4-01';
          await c.refresh();
          await tester.pumpWidget(app(dark: dark, density: density, scale: 2));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Attendance & leave').hitTestable(), findsOneWidget);
          await expectLater(
            find.byKey(const Key('workforce-preview')),
            matchesGoldenFile(
              'goldens/workforce_${dark ? 'dark' : 'light'}_${density.name}_200.png',
            ),
          );
          await tester.scrollUntilVisible(
            find.text('Encrypted recovery'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.ensureVisible(find.text('Encrypted recovery'));
          await tester.pumpAndSettle();
          expect(find.text('Encrypted recovery').hitTestable(), findsOneWidget);
        },
      );
    }
    testWidgets('${dark ? 'dark' : 'light'} workforce editor at 200 percent', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1024, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await raw();
      await tester.pumpWidget(app(editor: true, dark: dark, scale: 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Confirm command').hitTestable(), findsOneWidget);
      await expectLater(
        find.byKey(const Key('workforce-preview')),
        matchesGoldenFile(
          'goldens/workforce_editor_${dark ? 'dark' : 'light'}_200.png',
        ),
      );
    });
  }
  testWidgets('wide desktop workforce retains date and employee controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Choose employee').hitTestable(), findsOneWidget);
    expect(find.text('Apply date').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
