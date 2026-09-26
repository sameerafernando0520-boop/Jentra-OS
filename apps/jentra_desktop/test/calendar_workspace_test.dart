import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_people_platform.dart';
import 'package:jentra_desktop/src/features/people/calendar_controller.dart';
import 'package:jentra_desktop/src/features/people/calendar_screen.dart';
import 'package:jentra_desktop/src/shell/navigation.dart';

const _tenant = '10000000-0000-0000-0000-000000000001';
const _entity = '10000000-0000-0000-0000-000000000002';
const _branch = '10000000-0000-0000-0000-000000000003';
const _actor = '10000000-0000-0000-0000-000000000004';
const _calendar = '20000000-0000-0000-0000-000000000001';
const _version = '30000000-0000-0000-0000-000000000001';
const _scope = TenantContext(
  tenantId: _tenant,
  legalEntityId: _entity,
  branchId: _branch,
  actorId: _actor,
);
const _permissions = {
  'people.view',
  'people.calendars.view',
  'people.calendars.manage',
};

final class _Keys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

final class _Calendars implements WorkCalendarRepository {
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  String? failure, readFailure, failAfterConfirm;
  Map<String, Object?> current = {
    'id': _calendar,
    'tenant_id': _tenant,
    'legal_entity_id': _entity,
    'code': 'HQ',
    'name': 'Head Office calendar',
    'version': 1,
  };
  Map<String, Object?> pattern = {
    'id': _version,
    'calendar_id': _calendar,
    'tenant_id': _tenant,
    'legal_entity_id': _entity,
    'start_date': '2026-09-01',
    'end_date_exclusive': '2027-01-01',
    'timezone': 'Asia/Colombo',
    'weekly_intervals': [
      {
        'day_of_week': 1,
        'start_minute': 540,
        'end_minute': 1020,
        'end_day_offset': 0,
      },
      {
        'day_of_week': 5,
        'start_minute': 1320,
        'end_minute': 360,
        'end_day_offset': 1,
      },
    ],
    'date_overrides': [
      {
        'date': '2026-10-02',
        'is_working_day': false,
        'reason': 'Synthetic closure',
      },
    ],
    'published_by': _actor,
    'published_at': '2026-09-26T00:00:00Z',
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

  WorkCalendarIdentity get identity => WorkCalendarIdentity.fromJson(current);
  CalendarVersionDetail get version => CalendarVersionDetail.fromJson(pattern);
  CalendarDirectoryEntry entry(String date) => CalendarDirectoryEntry(
    identity,
    version.summary.coverage.contains(CivilDate.parse(date))
        ? version.summary.coverage
        : null,
  );
  @override
  Future<CalendarDirectoryPage> directory(
    TenantContext scope, {
    String? asOfDate,
    String search = '',
    String? after,
  }) async {
    _check();
    final date = asOfDate ?? '2026-09-26';
    return CalendarDirectoryPage(
      CivilDate.parse(date),
      CalendarPage([if (after == null) entry(date)], null),
    );
  }

  @override
  Future<CalendarDetail> detail(
    TenantContext scope,
    String calendarId,
    String versionId,
  ) async {
    _check();
    return CalendarDetail(identity, version);
  }

  @override
  Future<CalendarPage<CalendarVersionSummary>> versions(
    TenantContext scope,
    String calendarId, {
    String? after,
  }) async {
    _check();
    return CalendarPage([version.summary], null);
  }

  @override
  Future<CalendarPage<CalendarHistoryEvent>> history(
    TenantContext scope,
    String calendarId, {
    String? after,
  }) async {
    _check();
    return CalendarPage([
      CalendarHistoryEvent(
        id: '40000000-0000-0000-0000-000000000001',
        action: 'create',
        publishedVersionId: pattern['id'] as String,
        effectiveDate: CivilDate.parse(pattern['start_date'] as String),
        reason: 'Synthetic calendar approved',
        actorId: _actor,
        recordedAt: DateTime.utc(2026, 9, 26),
        before: null,
        after: CalendarConfirmation(identity, pattern['id'] as String),
      ),
    ], null);
  }

  @override
  Future<CalendarConfirmation> execute(
    String action,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    if (failure != null) throw DomainError(code: failure!, message: failure!);
    final payload = command.payload;
    current = {
      ...current,
      'id': payload['id'],
      'version': command.expectedEntityVersion! + 1,
      if (action == 'create') 'code': payload['code'],
      if (action != 'publish') 'name': payload['name'],
    };
    if (action != 'rename') {
      pattern = {
        ...pattern,
        for (final key in [
          'start_date',
          'end_date_exclusive',
          'timezone',
          'weekly_intervals',
          'date_overrides',
        ])
          key: payload[key],
        'id': payload['version_id'],
        'calendar_id': payload['id'],
      };
    }
    if (failAfterConfirm != null) readFailure = failAfterConfirm;
    return CalendarConfirmation(
      identity,
      action == 'rename' ? null : payload['version_id'] as String,
    );
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
  late JentraLocalDatabase db;
  late CalendarDraftStore drafts;
  late _Calendars repository;
  late CalendarController controller;
  CalendarController make({
    bool online = true,
    Set<String> permissions = _permissions,
  }) => CalendarController(
    scope: _scope,
    repository: repository,
    drafts: drafts,
    permissions: permissions,
    online: online,
  );
  void fill() {
    controller.beginCreate();
    controller.edit('code', 'LAB');
    controller.edit('name', 'Synthetic Calendar');
    controller.edit('end_date_exclusive', '2027-01-01');
    controller.edit('timezone', 'Asia/Colombo');
    controller.edit('reason', 'Synthetic calendar setup');
  }

  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = CalendarDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: _Keys())),
    );
    repository = _Calendars();
    controller = make();
  });
  tearDown(() async {
    controller.dispose();
    await db.close();
  });
  Future<void> pump(
    WidgetTester tester, {
    bool dark = false,
    double scale = 2,
    Size size = const Size(1024, 1500),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? JentraTheme.dark() : JentraTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: CalendarWorkspace(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
  }

  test(
    'uncertain publication recovers its exact envelope and prevents edits',
    () async {
      await controller.initialize();
      fill();
      repository.failure = 'UNCERTAIN_RESULT';
      await controller.submit();
      final original = repository.commands.single.toJson((value) => value);
      expect(controller.local?.pending, isNotNull);
      controller.edit('name', 'Mutated');
      expect(controller.form!['name'], 'Synthetic Calendar');
      await controller.discard();
      expect(controller.local?.pending, isNotNull);
      controller.dispose();
      controller = make();
      await controller.initialize();
      expect(controller.local?.pending, isNotNull);
      repository.failure = null;
      await controller.submit();
      expect(repository.commands.last.toJson((value) => value), original);
      expect(controller.local, isNull);
      expect(controller.selected?.version, 1);
    },
  );
  test('a confirmed publication survives optional refresh failure', () async {
    await controller.initialize();
    await controller.open(repository.entry('2026-09-26'));
    fill();
    repository.failAfterConfirm = 'READ_FAILED';
    await controller.submit();
    expect(controller.local, isNull);
    expect(controller.selected?.name, 'Synthetic Calendar');
    expect(controller.versions, isEmpty);
    expect(controller.events, isEmpty);
    expect(controller.message, 'Calendar action confirmed.');
    expect(controller.error, contains('Action confirmed'));
  });
  test(
    'revocation clears every visible calendar and draft but preserves encrypted retry',
    () async {
      await controller.initialize();
      await controller.open(repository.entry('2026-09-26'));
      fill();
      repository.failure = 'PERMISSION_DENIED';
      await controller.submit();
      final id = repository.commands.single.commandId;
      expect(controller.accessDenied, isTrue);
      expect(controller.form, isNull);
      expect(controller.local, isNull);
      expect(controller.items, isEmpty);
      expect(controller.selected, isNull);
      expect(controller.detail, isNull);
      expect(controller.events, isEmpty);
      expect(controller.versions, isEmpty);
      expect(
        (await drafts.load(
          _scope,
          CalendarController.slot,
        ))!.pending!.envelope.commandId,
        id,
      );
      repository.failure = null;
      await controller.refresh();
      expect(controller.local?.pending, isNotNull);
      await controller.submit();
      expect(repository.commands.last.commandId, id);
      expect(controller.local, isNull);
    },
  );
  test(
    'permission loss after confirmation hides the confirmed calendar',
    () async {
      await controller.initialize();
      fill();
      repository.failAfterConfirm = 'FEATURE_NOT_ENTITLED';
      await controller.submit();
      expect(controller.accessDenied, isTrue);
      expect(controller.selected, isNull);
      expect(controller.form, isNull);
      expect(await drafts.load(_scope, CalendarController.slot), isNull);
    },
  );
  test(
    'stale draft needs explicit comparison and replacement before a new command',
    () async {
      await controller.initialize();
      await controller.open(repository.entry('2026-09-26'));
      controller.beginAction('rename');
      controller.edit('name', 'Reviewed name');
      controller.edit('reason', 'Synthetic rename');
      repository.failure = 'VERSION_CONFLICT';
      await controller.submit();
      expect(controller.conflict, isTrue);
      expect(controller.local?.pending, isNull);
      controller.edit('name', 'Silent change');
      expect(controller.form!['name'], 'Reviewed name');
      await controller.submit();
      expect(repository.commands, hasLength(1));
      repository.current = {...repository.current, 'version': 2};
      repository.failure = null;
      await controller.compareConflict();
      expect(controller.form!['version'], 1);
      await controller.replaceConflict();
      expect(controller.form!['version'], 2);
      expect(controller.conflict, isFalse);
      await controller.submit();
      expect(repository.commands.last.expectedEntityVersion, 2);
      expect(controller.selected?.version, 3);
      expect(
        repository.commands.last.commandId,
        isNot(repository.commands.first.commandId),
      );
    },
  );
  test('offline editing saves locally and cannot publish', () async {
    controller.dispose();
    controller = make(online: false);
    await controller.initialize();
    controller.asOfDate = '2026-09-26';
    fill();
    await controller.saveLocal();
    expect(controller.local, isNotNull);
    await controller.submit();
    expect(repository.commands, isEmpty);
    expect(await controller.canLeave(), isTrue);
  });
  test(
    'invalid local times, overlapping intervals and out-of-range exceptions fail before dispatch',
    () async {
      await controller.initialize();
      fill();
      controller.editRow('weekly_intervals', 0, 'start_time', '25:00');
      await controller.submit();
      expect(repository.commands, isEmpty);
      expect(controller.error, contains('HH:MM'));
      controller.editRow('weekly_intervals', 0, 'start_time', '09:00');
      controller.addRow('weekly_intervals');
      await controller.submit();
      expect(repository.commands, isEmpty);
      expect(controller.error, contains('overlap'));
      controller.removeRow('weekly_intervals', 5);
      controller.addRow('date_overrides');
      controller.editRow('date_overrides', 0, 'date', '2027-01-01');
      controller.editRow('date_overrides', 0, 'reason', 'Outside');
      await controller.submit();
      expect(repository.commands, isEmpty);
      expect(controller.error, contains('within version'));
    },
  );
  test('a saved editor is retained until explicitly discarded', () async {
    await controller.initialize();
    fill();
    await controller.saveLocal();
    final id = controller.form!['id'];
    controller.beginCreate();
    expect(controller.form!['id'], id);
    await controller.discard();
    controller.beginCreate();
    expect(controller.form!['id'], isNot(id));
  });
  test(
    'calendar navigation requires its own capability, independent of employee read',
    () {
      final paths = visibleJentraDestinations(
        _permissions,
      ).map((item) => item.path);
      expect(paths, contains('/people/calendars'));
      expect(paths, isNot(contains('/people')));
      expect(
        visibleJentraDestinations({
          'people.view',
          'people.employees.view',
        }).map((item) => item.path),
        isNot(contains('/people/calendars')),
      );
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      '${dark ? 'dark' : 'light'} calendar workspace renders at 200 percent text',
      (tester) async {
        await controller.initialize();
        await controller.open(repository.entry('2026-09-26'));
        await pump(tester, dark: dark);
        expect(find.text('Work calendars'), findsOneWidget);
        expect(find.textContaining('22:00–06:00 next day'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(CalendarWorkspace),
          matchesGoldenFile(
            'goldens/calendar_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
        await tester.scrollUntilVisible(
          find.text('Calendar history'),
          700,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Synthetic calendar approved'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      '${dark ? 'dark' : 'light'} calendar editor keeps publish actions reachable at 200 percent text',
      (tester) async {
        await controller.initialize();
        await pump(tester, dark: dark, size: const Size(1024, 720));
        await tester.tap(find.text('New calendar'));
        await tester.pumpAndSettle();
        expect(find.text('Publish rules'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(Dialog),
          matchesGoldenFile(
            'goldens/calendar_editor_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
        await tester.tap(find.text('Publish rules'));
        await tester.pumpAndSettle();
        expect(repository.commands, isEmpty);
        expect(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.textContaining('Reason is required'),
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(find.text('Resume draft'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('plan denial removes calendar data and keeps retry reachable', (
    tester,
  ) async {
    await controller.initialize();
    await controller.open(repository.entry('2026-09-26'));
    repository.readFailure = 'FEATURE_NOT_ENTITLED';
    await controller.refresh();
    await pump(tester, size: const Size(1024, 720));
    expect(find.textContaining('Head Office'), findsNothing);
    expect(find.text('Retry calendar access'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(CalendarWorkspace),
      matchesGoldenFile('goldens/calendar_plan_denied_light_200.png'),
    );
    repository.readFailure = null;
    await tester.tap(find.text('Retry calendar access'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Head Office calendar'), findsOneWidget);
  });
  testWidgets('wide desktop uses a register beside selected version details', (
    tester,
  ) async {
    await controller.initialize();
    await controller.open(repository.entry('2026-09-26'));
    await pump(tester, scale: 1, size: const Size(1440, 1100));
    expect(
      tester.getTopLeft(find.text('HQ · Head Office calendar')).dx,
      lessThan(tester.getTopLeft(find.text('Head Office calendar')).dx),
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(CalendarWorkspace),
      matchesGoldenFile('goldens/calendar_wide_light.png'),
    );
  });
  testWidgets('read-only operators browse versions without draft controls', (
    tester,
  ) async {
    controller.dispose();
    controller = make(permissions: {'people.view', 'people.calendars.view'});
    await controller.initialize();
    await controller.open(repository.entry('2026-09-26'));
    await pump(tester);
    expect(find.text('New calendar'), findsNothing);
    expect(find.text('Publish new version'), findsNothing);
    expect(find.text('Rename calendar'), findsNothing);
    expect(find.text('Published versions'), findsOneWidget);
  });
  testWidgets('removing an interval retains the next row values', (
    tester,
  ) async {
    await controller.initialize();
    fill();
    controller.editRow('weekly_intervals', 1, 'start_time', '10:15');
    await pump(tester, scale: 1, size: const Size(1100, 1000));
    await tester.tap(find.text('Resume draft'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byTooltip('Remove working interval 1'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(Dialog),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byTooltip('Remove working interval 1'));
    await tester.pumpAndSettle();
    expect(
      (controller.form!['weekly_intervals'] as List).first['start_time'],
      '10:15',
    );
    expect(find.text('10:15'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
