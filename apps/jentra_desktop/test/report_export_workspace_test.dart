import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/features/report_export/report_export_controller.dart';
import 'package:jentra_desktop/src/features/report_export/report_export_screen.dart';

import 'support/procurement_fakes.dart' show Keys;

const selection = {
  'source_type': 'close',
  'source_id': 'review-0042',
  'section': 'sources',
  'filters': {'component_key': 'GRNI:b'},
};

class ExportGateway implements ReportExportGateway {
  String? failure, readFailure;
  Completer<void>? registrationPause, previewPause;
  final registrationEntered = Completer<void>(),
      previewEntered = Completer<void>();
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  final previews = <Map<String, Object?>>[];
  String value = '-0.730000';
  @override
  Future<Map<String, Object?>> preview(
    TenantContext s,
    Map<String, Object?> p,
  ) async {
    previews.add(p);
    if (!previewEntered.isCompleted) previewEntered.complete();
    await previewPause?.future;
    if (readFailure != null) {
      throw DomainError(
        code: readFailure!,
        message: 'Export access must be refreshed',
      );
    }
    return {
      'version': 1,
      'source_hash': 'a' * 64,
      'metadata': {
        'id': p['source_id'],
        'version': 1,
        'tenant_id': s.tenantId,
        'legal_entity_id': s.legalEntityId,
        'branch_id': s.branchId,
        'working_branch_id': s.branchId,
        'actor_id': s.actorId,
        'entity_name': 'Jentra Trading',
        ...p,
        'as_of': '2026-09-25',
        'generated_at': '2026-09-26 14:00 UTC',
        'currency_code': 'LKR',
        'row_count': 1,
      },
      'rows': [
        {
          'id': 'source-0042',
          'source_type': 'supplier_bill',
          'source_id': 'bill-0042',
          'value': value,
        },
      ],
    };
  }

  @override
  Future<Map<String, Object?>> record(
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    commands.add(c);
    if (!registrationEntered.isCompleted) registrationEntered.complete();
    await registrationPause?.future;
    if (failure != null) {
      throw DomainError(code: failure!, message: 'Registration needs retry');
    }
    return {'id': c.payload['id'], 'status': 'registered'};
  }
}

class Files implements ReportExportFiles {
  bool cancel = false, failWrite = false;
  int choices = 0;
  Completer<void>? choosePause;
  final writes = <Uint8List>[];
  @override
  Future<String?> choose(String name) async {
    choices++;
    await choosePause?.future;
    return cancel ? null : 'C:/synthetic/$name';
  }

  @override
  Future<void> write(String path, Uint8List bytes, String mimeType) async {
    if (failWrite) throw StateError('Synthetic local write failure');
    writes.add(Uint8List.fromList(bytes));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  late JentraLocalDatabase db;
  late QuotationDraftStore drafts;
  late ExportGateway gateway;
  late Files files;
  late ReportExportController c;
  var disposed = false;
  ReportExportController make() => ReportExportController(
    scope: scope,
    gateway: gateway,
    drafts: drafts,
    files: files,
    online: true,
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
    gateway = ExportGateway();
    files = Files();
    c = make();
  });
  tearDown(() async {
    if (!disposed) c.dispose();
    await db.close();
  });
  test(
    'cancelled file target sends no registration and writes no bytes',
    () async {
      await c.initialize(selection);
      files.cancel = true;
      await c.deliver();
      expect(gateway.commands, isEmpty);
      expect(files.writes, isEmpty);
      expect(c.pending, isFalse);
    },
  );
  test(
    'delivered artifact exactly matches registered hash and scope',
    () async {
      await c.initialize(selection);
      await c.deliver();
      expect(c.error, isNull);
      expect(c.form['status'], 'delivered');
      expect(files.writes, hasLength(1));
      final p = gateway.commands.single.payload;
      expect(
        p['file_sha256'],
        await ReportExportCodec.hash(files.writes.single),
      );
      expect(p['filters'], selection['filters']);
      final table = const SetupTabularCodec.reportExport().decodeXlsx(
        files.writes.single,
      );
      expect(table.rows.last[table.headers.indexOf('data_value')], '-0.730000');
    },
  );
  test(
    'uncertain registration writes no file and retries identical envelope',
    () async {
      await c.initialize(selection);
      gateway.failure = 'UNCERTAIN_RESULT';
      await c.deliver();
      expect(c.pending, isTrue);
      expect(files.writes, isEmpty);
      c.format('csv');
      expect(c.form['file_format'], 'xlsx');
      gateway.failure = null;
      await c.deliver();
      expect(gateway.commands.first.commandId, gateway.commands.last.commandId);
      expect(gateway.commands.first.payload, gateway.commands.last.payload);
      expect(files.writes, hasLength(1));
    },
  );
  test(
    'native write failure preserves registered job and byte hash for retry',
    () async {
      await c.initialize(selection);
      files.failWrite = true;
      await c.deliver();
      expect(c.form['status'], 'registered');
      expect(c.error, contains('Local delivery failed'));
      final job = c.form['job_id'];
      files.failWrite = false;
      await c.deliver();
      expect(gateway.commands, hasLength(1));
      expect(c.form['job_id'], job);
      expect(c.form['status'], 'delivered');
    },
  );
  test(
    'recovered registration requires fresh permission before delivery',
    () async {
      await c.initialize(selection);
      files.failWrite = true;
      await c.deliver();
      c.dispose();
      disposed = true;
      c = make();
      disposed = false;
      files.failWrite = false;
      gateway.readFailure = 'PERMISSION_DENIED';
      await c.initialize(selection);
      await c.deliver();
      expect(c.denied, isTrue);
      expect(files.writes, isEmpty);
      expect(gateway.commands, hasLength(1));
    },
  );
  test(
    'registered evidence cannot silently change during delivery recovery',
    () async {
      await c.initialize(selection);
      files.failWrite = true;
      await c.deliver();
      files.failWrite = false;
      gateway.value = '-0.740000';
      await c.deliver();
      expect(c.error, contains('no longer match'));
      expect(files.writes, isEmpty);
      expect(gateway.commands, hasLength(1));
    },
  );
  test(
    'offline acknowledgement persists registration but does not write',
    () async {
      await c.initialize(selection);
      gateway.registrationPause = Completer<void>();
      final task = c.deliver();
      await gateway.registrationEntered.future;
      c.setOnline(false);
      gateway.registrationPause!.complete();
      await task;
      final local = await drafts.load(scope, ReportExportController.slot);
      expect(local!.form['status'], 'registered');
      expect(local.pending, isNull);
      expect(files.writes, isEmpty);
      expect(c.document, isEmpty);
    },
  );
  test('disposed route still atomically confirms registration without file delivery', () async {
    await c.initialize(selection);
    gateway.registrationPause = Completer<void>();
    final task = c.deliver();
    await gateway.registrationEntered.future;
    c.dispose();
    disposed = true;
    gateway.registrationPause!.complete();
    await task;
    expect(
      (await drafts.load(scope, ReportExportController.slot))!.form['status'],
      'registered',
    );
    expect(files.writes, isEmpty);
  });
  test(
    'failed encrypted confirmation preserves sealed command for retry',
    () async {
      await c.initialize(selection);
      gateway.failure = 'UNCERTAIN_RESULT';
      await c.deliver();
      gateway.failure = null;
      await db.customStatement(
        "create trigger fail_export_confirm before update on encrypted_drafts begin select raise(abort, 'EXPORT_CONFIRM_FAILURE'); end;",
      );
      await c.deliver();
      expect(
        (await drafts.load(scope, ReportExportController.slot))!.pending,
        isNotNull,
      );
      expect(files.writes, isEmpty);
      await db.customStatement('drop trigger fail_export_confirm');
      await c.deliver();
      expect(gateway.commands.map((x) => x.commandId).toSet(), hasLength(1));
      expect(files.writes, hasLength(1));
    },
  );
  test(
    'disconnect during file choice prevents registration and write',
    () async {
      await c.initialize(selection);
      files.choosePause = Completer<void>();
      final task = c.deliver();
      while (files.choices == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      c.setOnline(false);
      files.choosePause!.complete();
      await task;
      expect(gateway.commands, isEmpty);
      expect(files.writes, isEmpty);
    },
  );
  test(
    'MFA expiry clears export evidence and fresh recheck restores it',
    () async {
      await c.initialize(selection);
      gateway.readFailure = 'MFA_REQUIRED';
      await c.refresh();
      expect(c.denied, isTrue);
      expect(c.document, isEmpty);
      gateway.readFailure = null;
      await c.refresh();
      expect(c.denied, isFalse);
      expect(c.verified, isTrue);
    },
  );
  test(
    'stale preview cannot repopulate offline evidence after reconnect',
    () async {
      gateway.previewPause = Completer<void>();
      final task = c.initialize(selection);
      await gateway.previewEntered.future;
      c.setOnline(false);
      c.setOnline(true);
      gateway.previewPause!.complete();
      await task;
      expect(c.document, isEmpty);
      expect(c.verified, isFalse);
    },
  );
  test(
    'encrypted registration payload is isolated by actor and entity',
    () async {
      await c.initialize(selection);
      gateway.failure = 'UNCERTAIN_RESULT';
      await c.deliver();
      expect(
        await drafts.load(
          const TenantContext(
            tenantId: 't',
            actorId: 'other',
            legalEntityId: 'e',
            branchId: 'b',
          ),
          ReportExportController.slot,
        ),
        isNull,
      );
      expect(
        await drafts.load(
          const TenantContext(
            tenantId: 't',
            actorId: 'a',
            legalEntityId: 'other',
            branchId: 'b',
          ),
          ReportExportController.slot,
        ),
        isNull,
      );
    },
  );
  testWidgets(
    'export link carries selected report section and exact filter through deep link',
    (t) async {
      Uri? opened;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(
              body: ReportExportLink(
                sourceType: 'close',
                sourceId: 'report',
                section: 'sources',
                filters: {'component_key': 'GRNI:b'},
              ),
            ),
          ),
          GoRoute(
            path: '/finance/report-export',
            builder: (context, state) {
              opened = state.uri;
              return const Scaffold(body: Text('Export review'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await t.pumpWidget(MaterialApp.router(routerConfig: router));
      await t.tap(find.text('Export filtered evidence'));
      await t.pumpAndSettle();
      expect(opened!.queryParameters, {
        'source': 'close',
        'id': 'report',
        'section': 'sources',
        'component_key': 'GRNI:b',
      });
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'governed export ${dark ? 'dark' : 'light'} 200 percent delivery choice reachable',
      (t) async {
        await c.initialize(selection);
        t.view.physicalSize = const Size(1024, 1500);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(
          MaterialApp(
            theme: dark ? JentraTheme.dark() : JentraTheme.light(),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(body: ReportExportWorkspace(controller: c)),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            'goldens/report_export_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
        await t.ensureVisible(find.text('Choose file and export'));
        files.cancel = true;
        await t.tap(find.text('Choose file and export'));
        await t.pumpAndSettle();
        expect(gateway.commands, isEmpty);
        expect(files.writes, isEmpty);
        expect(t.takeException(), isNull);
      },
    );
  }
}
