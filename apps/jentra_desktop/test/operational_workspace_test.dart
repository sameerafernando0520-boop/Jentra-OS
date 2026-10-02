import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:jentra_desktop/src/features/operations/operational_controller.dart';
import 'package:jentra_desktop/src/features/operations/operational_file_gateway.dart';
import 'package:jentra_desktop/src/features/operations/operational_screen.dart';
import 'package:jentra_desktop/src/features/operations/operational_report_controller.dart';

import 'support/procurement_fakes.dart' show Keys;

class OperationalFake implements OperationalGateway {
  Completer<Map<String, Object?>>? held;
  Object? failure;
  final cursors = <String?>[];
  final submittedFilters = <Map<String, Object?>>[];
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  final rejections = <CommandEnvelope<Map<String, Object?>>>[];
  bool uncertain = false;
  bool uncertainRejection = false;
  @override
  Future<Map<String, Object?>> generate(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    if (uncertain) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Retry the saved request',
      );
    }
    return {'id': command.payload['id'], 'status': 'generated'};
  }

  @override
  Future<Map<String, Object?>> rejectAttachment(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    rejections.add(command);
    if (uncertainRejection) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Retry the saved rejection',
      );
    }
    return {'id': command.payload['id'], 'status': 'rejected'};
  }

  @override
  Future<Map<String, Object?>> reportPage(
    TenantContext scope,
    String id,
    String section, {
    int after = 0,
  }) async => {
    'summary': {
      'id': id,
      'kind': commands.isEmpty ? 'current_list' : commands.last.payload['kind'],
      'row_count': 1,
      'generated_at': '2026-09-28T00:00:00Z',
    },
    'items': [],
    'next_cursor': null,
  };
  @override
  Future<Map<String, Object?>> currentPage(
    TenantContext scope,
    String kind, {
    Map<String, Object?> filters = const {},
    String? after,
  }) async {
    cursors.add(after);
    submittedFilters.add(Map.of(filters));
    if (held != null) return held!.future;
    if (failure != null) throw failure!;
    return {
      'items': [
        {
          'id': after == null ? 'first' : 'second',
          'document_number': 'BILL-0042',
          'status': 'posted',
          'document_date': '2026-09-20',
          'currency_code': 'LKR',
          'total': '900719925474.099999',
        },
      ],
      'next_cursor': after == null ? 'first' : null,
    };
  }

  @override
  Future<Map<String, Object?>> evidence(
    TenantContext scope,
    String kind,
    String id, {
    String? after,
  }) async => {
    'header': {'id': id, 'document_number': 'BILL-0042'},
    'items': <Map<String, Object?>>[],
    'attachments': [
      {
        'id': '00000000-0000-4000-8000-000000000042',
        'file_name': 'proof.pdf',
        'upload_status': 'ready',
        'version': 2,
      },
    ],
    'next_cursor': null,
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class OperationalFileFake implements OperationalFileGateway {
  final registerKeys = <String>[];
  final completeKeys = <String>[];
  int uploads = 0;
  bool uncertainCompletion = true;

  SetupRecord record(TenantContext scope, String status) =>
      SetupRecord.fromJson(BusinessSetupResource.attachments, {
        'id': '00000000-0000-4000-8000-000000000042',
        'tenant_id': scope.tenantId,
        'legal_entity_id': scope.legalEntityId,
        'aggregate_type': 'supplier_bill',
        'aggregate_id': '00000000-0000-4000-8000-000000000001',
        'upload_status': status,
        'version': 1,
      });

  @override
  Future<SetupRecord> register(
    TenantContext scope,
    Map<String, Object?> metadata,
    String idempotencyKey,
  ) async {
    registerKeys.add(idempotencyKey);
    expect(metadata['file_name'], 'proof.pdf');
    return record(scope, 'staged');
  }

  @override
  Future<void> upload(SetupRecord staged, Uint8List bytes) async {
    uploads++;
    expect(bytes, [1, 2, 3, 4]);
  }

  @override
  Future<SetupRecord> complete(
    TenantContext scope,
    SetupRecord staged,
    String checksumSha256,
    String idempotencyKey,
  ) async {
    completeKeys.add(idempotencyKey);
    expect(checksumSha256, hasLength(64));
    if (uncertainCompletion) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Confirm the saved file request',
      );
    }
    return record(scope, 'ready');
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
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  const target = (
    tenantId: 't',
    entityId: 'e',
    branchId: 'b',
    kind: 'supplier_bill',
    id: null,
  );
  late OperationalFake gateway;
  late OperationalController controller;
  setUp(() {
    gateway = OperationalFake();
    controller = OperationalController(
      scope: scope,
      gateway: gateway,
      target: target,
      online: true,
    );
  });
  tearDown(() => controller.dispose());
  test(
    'bounded navigation replaces the current page and supports back',
    () async {
      await controller.refresh();
      expect(controller.rows.single['id'], 'first');
      await controller.next();
      expect(controller.rows.single['id'], 'second');
      await controller.previous();
      expect(controller.rows.single['id'], 'first');
      expect(gateway.cursors, [null, 'first', null]);
    },
  );
  test('scope mismatch does not issue a source read', () async {
    final other = OperationalController(
      scope: scope,
      gateway: gateway,
      target: (
        tenantId: 'other',
        entityId: 'e',
        branchId: 'b',
        kind: 'supplier_bill',
        id: null,
      ),
      online: true,
    );
    await other.refresh();
    expect(gateway.cursors, isEmpty);
    expect(other.verified, isFalse);
    other.dispose();
  });
  test('disconnect discards late financial evidence', () async {
    gateway.held = Completer();
    final pending = controller.refresh();
    controller.setOnline(false);
    gateway.held!.complete({
      'items': [
        {'id': 'late'},
      ],
      'next_cursor': null,
    });
    await pending;
    expect(controller.rows, isEmpty);
    expect(controller.verified, isFalse);
    expect(controller.busy, isFalse);
  });
  test('revoked permission clears earlier evidence', () async {
    await controller.refresh();
    gateway.failure = const DomainError(
      code: 'PERMISSION_DENIED',
      message: 'Unavailable',
    );
    await controller.refresh();
    expect(controller.rows, isEmpty);
    expect(controller.verified, isFalse);
    expect(controller.error, contains('unavailable'));
  });
  test(
    'encrypted view filters restore but source rows require a new read',
    () async {
      final db = JentraLocalDatabase(NativeDatabase.memory());
      final drafts = QuotationDraftStore(
        EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
      );
      OperationalController make() => OperationalController(
        scope: scope,
        gateway: gateway,
        target: target,
        drafts: drafts,
        online: true,
      );
      var view = make();
      try {
        await view.initialize();
        await view.filter({
          'search': 'BILL-0042',
          'status': 'posted',
          'from_date': '2026-09-01',
          'to_date': '2026-09-30',
        });
        expect(view.verified, isTrue);
        view.dispose();
        view = make();
        gateway.failure = const DomainError(
          code: 'PERMISSION_DENIED',
          message: 'Unavailable',
        );
        await view.initialize();
        expect(view.filters['search'], 'BILL-0042');
        expect(gateway.submittedFilters.last['status'], 'posted');
        expect(view.rows, isEmpty);
        expect(view.verified, isFalse);
      } finally {
        view.dispose();
        await db.close();
      }
    },
  );
  test(
    'uncertain frozen list request survives restart and ignores edited filters',
    () async {
      final db = JentraLocalDatabase(NativeDatabase.memory());
      final drafts = QuotationDraftStore(
        EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
      );
      OperationalController make() => OperationalController(
        scope: scope,
        gateway: gateway,
        target: target,
        online: true,
        drafts: drafts,
      );
      var current = make();
      try {
        await current.initialize();
        await current.filter({'status': 'posted'});
        gateway.uncertain = true;
        await current.freezeCurrentList();
        expect(current.reportPending, isTrue);
        final original = gateway.commands.single;
        current.dispose();
        current = make();
        await current.initialize();
        await current.filter({'status': 'draft'});
        gateway.uncertain = false;
        await current.freezeCurrentList();
        expect(gateway.commands.last.commandId, original.commandId);
        expect(gateway.commands.last.idempotencyKey, original.idempotencyKey);
        expect(gateway.commands.last.payload, original.payload);
        expect(current.reportPending, isFalse);
        expect(current.reportSummary['id'], original.payload['id']);
        current.setOnline(false);
        expect(current.reportSummary, isEmpty);
      } finally {
        current.dispose();
        await db.close();
      }
    },
  );
  test(
    'dated report retries the exact sealed party and cutoff after restart',
    () async {
      final db = JentraLocalDatabase(NativeDatabase.memory());
      final drafts = QuotationDraftStore(
        EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
      );
      OperationalReportController make() => OperationalReportController(
        scope: scope,
        kind: 'supplier_statement',
        gateway: gateway,
        drafts: drafts,
        online: true,
      );
      const original = <String, Object?>{
        'party_id': '00000000-0000-4000-8000-000000000001',
        'currency_code': 'LKR',
        'as_of': '2026-09-20',
        'bucket_days': [30, 60, 90],
      };
      var report = make();
      try {
        await report.initialize();
        gateway.uncertain = true;
        await report.freeze(original);
        expect(report.pending, isTrue);
        final sealed = gateway.commands.single;
        report.dispose();
        report = make();
        await report.initialize();
        gateway.uncertain = false;
        await report.freeze({...original, 'as_of': '2026-09-21'});
        expect(gateway.commands.last.commandId, sealed.commandId);
        expect(gateway.commands.last.idempotencyKey, sealed.idempotencyKey);
        expect(gateway.commands.last.payload, sealed.payload);
        expect(report.pending, isFalse);
        expect(report.summary['kind'], 'supplier_statement');
        report.setOnline(false);
        expect(report.summary, isEmpty);
      } finally {
        report.dispose();
        await db.close();
      }
    },
  );
  test(
    'file completion retries the sealed command without uploading again',
    () async {
      final db = JentraLocalDatabase(NativeDatabase.memory());
      final drafts = QuotationDraftStore(
        EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
      );
      final files = OperationalFileFake();
      const detail = (
        tenantId: 't',
        entityId: 'e',
        branchId: 'b',
        kind: 'supplier_bill',
        id: '00000000-0000-4000-8000-000000000001',
      );
      OperationalController make() => OperationalController(
        scope: scope,
        gateway: gateway,
        target: detail,
        drafts: drafts,
        files: files,
        online: true,
      );
      var current = make();
      try {
        await current.initialize();
        await current.addFile(
          SelectedAttachmentFile(
            name: 'proof.pdf',
            mimeType: 'application/pdf',
            bytes: Uint8List.fromList([1, 2, 3, 4]),
          ),
        );
        expect(current.filePhase, 'complete');
        expect(current.filePending, isTrue);
        expect(files.uploads, 1);
        expect(files.completeKeys, hasLength(1));
        current.dispose();
        current = make();
        await current.initialize();
        expect(current.filePhase, 'complete');
        files.uncertainCompletion = false;
        await current.addFile(null);
        expect(files.completeKeys, [
          files.completeKeys.first,
          files.completeKeys.first,
        ]);
        expect(files.uploads, 1);
        expect(current.filePending, isFalse);
        expect(current.verified, isTrue);
      } finally {
        current.dispose();
        await db.close();
      }
    },
  );
  test(
    'reasoned file rejection reuses its sealed command after restart',
    () async {
      final db = JentraLocalDatabase(NativeDatabase.memory());
      final drafts = QuotationDraftStore(
        EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
      );
      const detail = (
        tenantId: 't',
        entityId: 'e',
        branchId: 'b',
        kind: 'supplier_bill',
        id: '00000000-0000-4000-8000-000000000001',
      );
      OperationalController make() => OperationalController(
        scope: scope,
        gateway: gateway,
        target: detail,
        drafts: drafts,
        online: true,
      );
      var current = make();
      try {
        await current.initialize();
        final file =
            (current.evidence['attachments'] as List).single
                as Map<String, Object?>;
        gateway.uncertainRejection = true;
        await current.rejectAttachment(file, 'Wrong source document');
        expect(current.rejectionPending, isTrue);
        final sealed = gateway.rejections.single;
        current.dispose();
        current = make();
        await current.initialize();
        gateway.uncertainRejection = false;
        await current.rejectAttachment(null, null);
        expect(gateway.rejections.last.commandId, sealed.commandId);
        expect(gateway.rejections.last.idempotencyKey, sealed.idempotencyKey);
        expect(gateway.rejections.last.payload, sealed.payload);
        expect(current.rejectionPending, isFalse);
        expect(current.verified, isTrue);
      } finally {
        current.dispose();
        await db.close();
      }
    },
  );
  for (final width in [1024.0, 1440.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'operational list ${width.toInt()} ${dark ? 'dark' : 'light'} 200%',
        (tester) async {
          await controller.refresh();
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? JentraTheme.dark() : JentraTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: RepaintBoundary(
                key: const Key('operational-golden'),
                child: Scaffold(
                  body: OperationalWorkspace(
                    controller: controller,
                    canExport: true,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(const Key('operational-golden')),
            matchesGoldenFile(
              'goldens/operational_list_${width.toInt()}_${dark ? 'dark' : 'light'}_200.png',
            ),
          );
        },
      );
    }
  }
}
