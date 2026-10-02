import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_platform/jentra_people_platform.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_desktop/src/features/people/private_hr_controller.dart';
import 'package:jentra_desktop/src/features/people/private_hr_screen.dart';
import 'package:jentra_desktop/src/shell/navigation.dart';

const scope = TenantContext(
  tenantId: '10000000-0000-0000-0000-000000000001',
  legalEntityId: '10000000-0000-0000-0000-000000000002',
  branchId: '10000000-0000-0000-0000-000000000003',
  actorId: '10000000-0000-0000-0000-000000000004',
);
const employee = '20000000-0000-0000-0000-000000000001',
    reviewId = '30000000-0000-0000-0000-000000000001',
    revision = '40000000-0000-0000-0000-000000000001',
    reviewerId = '50000000-0000-0000-0000-000000000001';
const caps = {
  'people.view',
  'people.hr.private.view',
  'people.hr.private.manage',
  'people.hr.documents.view',
  'people.hr.documents.manage',
  'people.reviews.view',
  'people.reviews.manage',
  'people.account_links.manage',
  'people.hr.retention.manage',
  'people.hr.export',
  'people.hr.erase',
  'people.self.view',
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

class _Files implements HrFiles {
  HrPickedDocument? picked;
  Completer<void>? gate;
  Uint8List? written;
  @override
  Future<HrPickedDocument?> chooseUpload() async {
    await gate?.future;
    return picked;
  }

  @override
  Future<String?> chooseExport(String name) async {
    await gate?.future;
    return 'synthetic-export.json';
  }

  @override
  Future<void> write(String path, Uint8List bytes, String mime) async {
    written = Uint8List.fromList(bytes);
  }
}

class _Hr implements HrRepository {
  String? accessFailure, readFailure, commandFailure, afterConfirmFailure;
  Completer<void>? contactGate;
  int version = 1;
  final commands = <CommandEnvelope<Map<String, Object?>>>[],
      receipts = <String, HrConfirmation>{};
  final body = <String, Object?>{
    for (final key in hrContactFields)
      key: key == 'personal_phone' ? 'SYNTHETIC_PRIVATE_PHONE' : null,
  };
  HrRecord get subject => HrRecord.fromJson(HrRecordKind.subject, {
    'id': employee,
    'code': 'SYN-01',
    'display_name': 'Synthetic Employee',
  });
  HrRecord get reviewer => HrRecord.fromJson(HrRecordKind.subject, {
    'id': reviewerId,
    'code': 'SYN-02',
    'display_name': 'Synthetic Reviewer',
  });
  HrRecord get profile => HrRecord.fromJson(HrRecordKind.profile, {
    'employee_id': employee,
    'version': version,
    'revision_id': revision,
    'body': body,
    'recorded_by': scope.actorId,
    'recorded_at': '2026-09-28T00:00:00Z',
  });
  HrRecord get review => HrRecord.fromJson(HrRecordKind.review, {
    'id': reviewId,
    'version': 2,
    'revision_id': revision,
    'reviewer_id': reviewerId,
    'status': 'submitted',
    'start_date': '2026-09-01',
    'end_date_exclusive': '2026-10-01',
    'body': {
      'objectives': ['Synthetic delivery objective'],
      'comments': 'SYNTHETIC_PRIVATE_REVIEW',
    },
    'recorded_by': reviewerId,
    'recorded_at': '2026-09-28T00:00:00Z',
  });
  void check() {
    if (readFailure != null) {
      throw DomainError(
        code: readFailure!,
        message: 'Private read unavailable.',
      );
    }
  }

  @override
  Future<void> authorize(TenantContext s, String? e, String cap) async {
    if (accessFailure != null) {
      throw DomainError(
        code: accessFailure!,
        message: 'Private access changed.',
      );
    }
  }

  @override
  Future<HrPage> subjects(
    TenantContext s,
    String capability, {
    String search = '',
    String? after,
  }) async {
    check();
    return HrPage(after == null ? [subject, reviewer] : [], null);
  }

  @override
  Future<HrProfileState> contacts(
    TenantContext s,
    String id, {
    String? after,
  }) async {
    await contactGate?.future;
    check();
    return HrProfileState(profile, const HrPage([], null));
  }

  @override
  Future<HrPage> page(
    TenantContext s,
    HrCollection collection, {
    String? employee,
    String? reviewId,
    String? after,
  }) async {
    check();
    return HrPage(collection == HrCollection.reviews ? [review] : [], null);
  }

  @override
  Future<HrPolicyState> policy(TenantContext s) async => HrPolicyState(
    HrRecord.fromJson(HrRecordKind.policy, {
      'id': reviewId,
      'version': 1,
      'purpose': 'Synthetic test cycle',
      'contract': 'w4-private-hr-v1',
      'retention_days': 30,
      'closed_at': null,
      'hold_reason': null,
      'hold_review_date': null,
    }),
    false,
  );
  @override
  Future<HrRecord> self(TenantContext s) async => HrRecord.fromJson(
    HrRecordKind.self,
    {'employee_id': employee, 'display_name': 'Synthetic Employee'},
  );
  @override
  Future<HrConfirmation> command(
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    await authorize(
      c.context,
      c.payload['employee_id'] as String?,
      HrCommands.capability(c.payload['action'] as String),
    );
    commands.add(c);
    final prior = receipts[c.commandId];
    if (prior != null) return prior;
    if (commandFailure != null) {
      throw DomainError(
        code: commandFailure!,
        message: 'Synthetic command result unavailable.',
      );
    }
    if (c.expectedEntityVersion != null &&
        c.payload['action'] == 'profile_save' &&
        c.expectedEntityVersion != version) {
      throw const DomainError(
        code: 'VERSION_CONFLICT',
        message: 'Compare the private server version.',
      );
    }
    final entity = {
      'id': c.payload['id'],
      'tenant_id': sco(scope.tenantId),
      'legal_entity_id': scope.legalEntityId,
      'branch_id': scope.branchId,
      'employee_id': c.payload['employee_id'],
      'version': c.expectedEntityVersion! + 1,
      'action': c.payload['action'],
      'revision_id': c.payload['revision_id'],
      'digest': null,
    };
    final result = HrConfirmation.fromJson({
      'request_id': c.commandId,
      'command_id': c.commandId,
      'correlation_id': c.commandId,
      'entity': entity,
      'warnings': [],
    });
    receipts[c.commandId] = result;
    if (c.payload['action'] == 'profile_save') {
      version++;
      body
        ..clear()
        ..addAll(hrMap(c.payload['body']));
    }
    if (afterConfirmFailure != null) readFailure = afterConfirmFailure;
    return result;
  }

  String sco(String value) => value;
  @override
  Future<HrConfirmation?> receipt(TenantContext s, String id) async =>
      receipts[id];
  @override
  Future<Map<String, Object?>> exportContent(TenantContext s, String id) async {
    await authorize(s, employee, 'people.hr.export');
    return {
      'format': 'w4-hr-export-v1',
      'export_id': id,
      'body': body,
      'employee_id': employee,
      'kind': 'profile',
    };
  }

  @override
  Future<Uint8List> document(
    TenantContext s,
    String employee,
    HrRecord doc, {
    bool export = false,
  }) async => Uint8List.fromList(utf8.encode('Synthetic private preview'));
  @override
  Future<HrConfirmation> upload(
    CommandEnvelope<Map<String, Object?>> c,
    HrRecord doc,
    Uint8List bytes,
  ) => command(c);
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
  late _Hr repository;
  late _Files files;
  late PrivateHrController c;
  var now = DateTime.utc(2026, 9, 28);
  setUp(() async {
    now = DateTime.utc(2026, 9, 28);
    db = JentraLocalDatabase(NativeDatabase.memory());
    repository = _Hr();
    files = _Files();
    c = PrivateHrController(
      scope: scope,
      repository: repository,
      drafts: PrivateHrDraftStore(
        EncryptedDraftRepository(db, DraftCipher(keyStore: _Keys())),
        repository.authorize,
        clock: () => now,
      ),
      files: files,
      permissions: caps,
      online: true,
      clock: () => now,
      monitor: false,
    );
    await c.initialize();
    await c.openSubject(repository.subject);
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  Future<void> edit() async {
    await c.begin('profile_save');
    c.editContact('personal_phone', 'SYNTHETIC_EDITED_PRIVATE');
    c.edit('reason', 'Synthetic edit');
  }

  Widget app({
    bool dark = false,
    JentraDensity density = JentraDensity.comfortable,
    double scale = 1,
    bool editor = false,
  }) => MaterialApp(
    theme: dark
        ? JentraTheme.dark(density: density)
        : JentraTheme.light(density: density),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: RepaintBoundary(
        key: const Key('private-hr-preview'),
        child: Scaffold(
          body: editor
              ? SingleChildScrollView(child: PrivateHrEditor(controller: c))
              : PrivateHrWorkspace(controller: c),
        ),
      ),
    ),
  );
  test(
    'uncertain private request keeps exact identity and body through retry',
    () async {
      await edit();
      repository.commandFailure = 'UNCERTAIN_RESULT';
      await c.submit();
      final original = c.local!.pending!.envelope;
      expect(c.form, isNotNull);
      c.editContact('personal_phone', 'blocked edit');
      expect(c.form!['body'], original.payload['body']);
      repository.commandFailure = null;
      await c.submit();
      expect(repository.commands.last.commandId, original.commandId);
      expect(repository.commands.last.payload, original.payload);
      expect(c.confirmed, isNotNull);
      expect(c.form, isNull);
      expect(c.recovery, isEmpty);
    },
  );
  test(
    'confirmed mutation survives an optional later private read failure',
    () async {
      await edit();
      repository.afterConfirmFailure = 'UNCERTAIN_RESULT';
      await c.submit();
      expect(c.confirmed, isNotNull);
      expect(c.message, contains('confirmed'));
      expect(c.error, contains('confirmed'));
      expect(c.form, isNull);
    },
  );
  test(
    'conflicts require current content comparison before replacing edits',
    () async {
      await edit();
      repository.version = 2;
      await c.submit();
      expect(c.conflict, isTrue);
      expect(c.local!.pending, isNull);
      await c.retainCompared();
      expect(c.expectedVersion, 1);
      await c.compare();
      expect(c.comparedContacts!.profile!.version, 2);
      await c.retainCompared();
      expect(c.expectedVersion, 2);
      await c.submit();
      expect(c.confirmed!.version, 3);
    },
  );
  test(
    'private revocation clears form, profile, preview and recovery immediately',
    () async {
      await edit();
      await c.save();
      c.previewBytes = Uint8List.fromList([1, 2, 3]);
      final bytes = c.previewBytes!;
      repository.accessFailure = 'PERMISSION_DENIED';
      await c.checkAccess();
      expect(c.current, isFalse);
      expect(c.form, isNull);
      expect(c.contactState, isNull);
      expect(c.previewBytes, isNull);
      expect(bytes, [0, 0, 0]);
      expect(c.recovery, isEmpty);
    },
  );
  test('late response is discarded after controller disposal', () async {
    repository.contactGate = Completer();
    final pending = c.refresh();
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    repository.contactGate!.complete();
    await pending;
    expect(c.contactState, isNull);
    expect(c.subjects, isEmpty);
    // Avoid invoking ChangeNotifier.dispose twice in tearDown.
    c = PrivateHrController(
      scope: scope,
      repository: repository,
      drafts: c.drafts,
      files: files,
      permissions: caps,
      online: true,
      monitor: false,
    );
  });
  test(
    '24-hour expiry drops text and exposes only unresolved receipt recovery',
    () async {
      await edit();
      repository.commandFailure = 'UNCERTAIN_RESULT';
      await c.submit();
      final id = c.local!.pending!.envelope.commandId;
      now = now.add(const Duration(hours: 24));
      await c.checkAccess();
      expect(c.form, isNull);
      expect(c.recovery.single.expiresAt, isNull);
      await c.resume(c.recovery.single);
      await c.resolveExpired();
      expect(c.expiredRecovery, isNotNull);
      expect(c.message, contains('stays blocked'));
      final command = repository.commands.last;
      repository.commandFailure = null;
      final result = await repository.command(command);
      expect(result.commandId, id);
      await c.resolveExpired();
      expect(c.expiredRecovery, isNull);
      expect(c.confirmed, isNotNull);
    },
  );
  test(
    'new review uses a fresh identity even when another review is selected',
    () async {
      await c.changeView(PrivateHrView.reviews);
      await c.openSubject(repository.subject);
      await c.openReview(repository.review);
      await c.begin('review_create', reviewer: repository.reviewer);
      expect(c.form!['id'], isNot(reviewId));
      expect(c.expectedVersion, 0);
      expect(c.form!['reviewer_id'], reviewerId);
    },
  );
  test('file-dialog access revocation prevents exporting bytes', () async {
    await c.prepareExport();
    await c.submit();
    expect(c.preparedExportId, isNotNull);
    files.gate = Completer();
    final export = c.writePreparedExport();
    await Future<void>.delayed(Duration.zero);
    repository.accessFailure = 'PERMISSION_DENIED';
    files.gate!.complete();
    await export;
    expect(files.written, isNull);
    expect(c.current, isFalse);
  });
  test(
    'plain People access exposes account proposals without HR data',
    () async {
      final navigation = visibleJentraDestinations({'people.view'});
      expect(navigation.map((d) => d.path), contains('/people/private'));
      final other = PrivateHrController(
        scope: scope,
        repository: repository,
        drafts: c.drafts,
        files: files,
        permissions: {'people.view'},
        online: true,
        monitor: false,
      );
      try {
        expect(other.views, [PrivateHrView.myAccount]);
        await other.initialize();
        expect(other.contactState, isNull);
        expect(other.subjects, isEmpty);
      } finally {
        other.dispose();
      }
    },
  );
  testWidgets('permission loss removes private values and their text fields', (
    tester,
  ) async {
    await edit();
    await tester.pumpWidget(app(editor: true));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsWidgets);
    repository.accessFailure = 'PERMISSION_DENIED';
    await c.checkAccess();
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('SYNTHETIC_EDITED_PRIVATE'), findsNothing);
  });
  testWidgets(
    'private editor controls are reachable with 200 percent text and keyboard focus',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await edit();
      await tester.pumpWidget(app(editor: true, scale: 2));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Confirm action'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Confirm action').hitTestable(), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('review decision form retains separate attributable text', (
    tester,
  ) async {
    await c.changeView(PrivateHrView.reviews);
    await c.openSubject(repository.subject);
    await c.begin('review_decide', record: repository.review);
    await tester.pumpWidget(app(editor: true, scale: 2));
    await tester.pumpAndSettle();
    expect(find.text('Independent review decision'), findsOneWidget);
    expect(find.text('Confirm action'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final dark in [false, true]) {
    for (final density in JentraDensity.values) {
      testWidgets(
        'private contacts ${dark ? 'dark' : 'light'} ${density.name} at 200 percent',
        (tester) async {
          tester.view.physicalSize = const Size(1024, 720);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(app(dark: dark, density: density, scale: 2));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Private HR').hitTestable(), findsOneWidget);
          await expectLater(
            find.byKey(const Key('private-hr-preview')),
            matchesGoldenFile(
              'goldens/private_hr_${dark ? 'dark' : 'light'}_${density.name}_200.png',
            ),
          );
          await tester.scrollUntilVisible(
            find.text('Edit private contacts'),
            250,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.ensureVisible(
            find.widgetWithText(OutlinedButton, 'Edit private contacts'),
          );
          await tester.pumpAndSettle();
          expect(
            find.text('Edit private contacts').hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final dark in [false, true]) {
    testWidgets(
      'private contact editor ${dark ? 'dark' : 'light'} at 200 percent',
      (tester) async {
        tester.view.physicalSize = const Size(1024, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await edit();
        await tester.pumpWidget(app(editor: true, dark: dark, scale: 2));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const Key('private-hr-preview')),
          matchesGoldenFile(
            'goldens/private_hr_editor_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
      },
    );
  }
  testWidgets('wide private workspace preserves desktop actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Reload').hitTestable(), findsOneWidget);
  });
}
