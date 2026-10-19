import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_expense_evidence.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_expense_evidence_platform.dart';
import 'package:jentra_desktop/src/features/projects/expense_evidence_controller.dart';
import 'package:jentra_desktop/src/features/projects/expense_evidence_screen.dart';

const scope = TenantContext(
  tenantId: '10000000-0000-4000-8000-000000000001',
  legalEntityId: '10000000-0000-4000-8000-000000000002',
  branchId: '10000000-0000-4000-8000-000000000003',
  actorId: '10000000-0000-4000-8000-000000000004',
);
const project = '20000000-0000-4000-8000-000000000001',
    expense = '20000000-0000-4000-8000-000000000002',
    document = '20000000-0000-4000-8000-000000000003';

class Keys implements SecretKeyStore {
  final values = <String, String>{};
  bool fail = false;
  @override
  Future<String?> read(String key) async {
    if (fail) throw StateError('Synthetic local cleanup failure');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class Files implements ExpenseEvidenceFiles {
  late ExpensePickedDocument file;
  Completer<ExpensePickedDocument?>? picker;
  int writes = 0;
  @override
  Future<ExpensePickedDocument?> chooseUpload() async =>
      picker == null ? file : picker!.future;
  @override
  Future<String?> chooseExport(String name) async => 'synthetic-selected-file';
  @override
  Future<void> write(String path, Uint8List bytes, String mime) async {
    writes++;
  }
}

class Server implements ExpenseEvidenceRepository {
  final rows = <String, ExpenseEvidenceDocument>{};
  final receipts = <String, ExpenseEvidenceConfirmation>{};
  String checksum = 'b' * 64;
  Uint8List readBytes = Uint8List.fromList([65, 66, 67, 68]);
  int writes = 0;
  bool deny = false,
      denyManage = false,
      denyExport = false,
      available = true,
      uncertain = false,
      keepReceipt = true;
  Completer<void>? readGate;
  Completer<void>? listGate;
  void Function()? onWrite, onRead;
  CommandEnvelope<Map<String, Object?>>? last;
  Map<String, Object?> metadata(
    String id, {
    String status = 'active',
    int version = 2,
  }) => {
    'id': id,
    'version': 1,
    'digest': 'a' * 64,
    'record_version': version,
    'status': status,
    'purpose': 'Synthetic private receipt',
    'mime': 'text/plain',
    'byte_size': 4,
    'checksum': checksum,
    'policy_id': project,
    'retired_at': null,
    'purge_after': null,
    'hold_review_date': null,
  };
  @override
  Future<bool> authorize(
    TenantContext s,
    String? p,
    String? x,
    String cap,
  ) async {
    if (deny ||
        denyExport && cap == expenseEvidenceExport ||
        denyManage && cap == expenseEvidenceManage) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Current evidence access denied',
      );
    }
    return available;
  }

  @override
  Future<ExpenseEvidencePage> documents(
    TenantContext s,
    String p,
    String x, {
    String? after,
  }) async {
    await listGate?.future;
    return ExpenseEvidencePage(
      rows.values.toList()..sort((a, b) => a.id.compareTo(b.id)),
      null,
    );
  }

  @override
  Future<ExpenseEvidenceConfirmation> command(
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    writes++;
    last = c;
    final p = c.payload, id = p['id'] as String, action = p['action'] as String;
    final entity = <String, Object?>{
      'tenant_id': scopec(c.context, 't'),
      'legal_entity_id': c.context.legalEntityId,
      'branch_id': c.context.branchId,
      'id': id,
      'version': 1,
      'action': action,
    };
    if (action != 'policy_create') {
      final status = action == 'reserve'
          ? 'reserved'
          : action == 'retire'
          ? 'retired'
          : 'active';
      entity.addAll({
        'digest': 'a' * 64,
        'record_version': c.expectedEntityVersion! + 1,
        'status': status,
        'project_id': p['project_id'],
        'expense_id': p['expense_id'],
      });
      rows[id] = ExpenseEvidenceDocument.fromJson({
        ...metadata(id, status: status, version: c.expectedEntityVersion! + 1),
        if (action == 'hold') 'hold_review_date': p['review_date'],
      });
    }
    final result = ExpenseEvidenceConfirmation.fromJson({
      'request_id': id,
      'command_id': c.commandId,
      'correlation_id': id,
      'warnings': [],
      'entity': entity,
    });
    if (keepReceipt) receipts[c.commandId] = result;
    onWrite?.call();
    if (uncertain) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Synthetic lost response',
      );
    }
    return result;
  }

  String scopec(TenantContext c, String _) => c.tenantId;
  @override
  Future<ExpenseEvidenceConfirmation?> receipt(
    TenantContext s,
    String commandId,
  ) async => receipts[commandId];
  @override
  Future<ExpenseEvidenceConfirmation> upload(
    CommandEnvelope<Map<String, Object?>> c,
    ExpenseEvidenceDocument doc,
    Uint8List bytes,
  ) => command(c);
  @override
  Future<Uint8List> document(
    TenantContext s,
    String p,
    String x,
    ExpenseEvidenceDocument d, {
    bool export = false,
  }) async {
    await readGate?.future;
    onRead?.call();
    return Uint8List.fromList(readBytes);
  }
}

void main() {
  late JentraLocalDatabase db;
  late Keys keys;
  late Server server;
  late Files files;
  late SensitiveExpenseEvidenceDraftStore drafts;
  late ExpenseEvidenceController c;
  late DateTime now;
  setUpAll(() async {
    await (FontLoader(JentraTypography.sansFamily)
          ..addFont(
            rootBundle.load(
              'packages/jentra_design_system/assets/fonts/Manrope-Regular.ttf',
            ),
          )
          ..addFont(
            rootBundle.load(
              'packages/jentra_design_system/assets/fonts/Manrope-SemiBold.ttf',
            ),
          ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  ExpenseEvidenceController controller() => ExpenseEvidenceController(
    scope: scope,
    projectId: project,
    expenseId: expense,
    repository: server,
    drafts: drafts,
    files: files,
  );
  setUp(() async {
    db = JentraLocalDatabase(NativeDatabase.memory());
    keys = Keys();
    server = Server();
    files = Files();
    now = DateTime.utc(2026, 10, 5);
    final bytes = Uint8List.fromList([65, 66, 67, 68]),
        hash = (await Sha256().hash(bytes)).bytes
            .map((x) => x.toRadixString(16).padLeft(2, '0'))
            .join();
    server.checksum = hash;
    files.file = ExpensePickedDocument('text/plain', bytes, hash);
    server.rows[document] = ExpenseEvidenceDocument.fromJson(
      server.metadata(document),
    );
    drafts = SensitiveExpenseEvidenceDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: keys)),
      (s, p, x, cap) async {
        await server.authorize(s, p, x, cap);
      },
      clock: () => now,
    );
    c = controller();
  });
  tearDown(() async {
    c.dispose();
    keys.fail = false;
    await db.close();
  });
  test(
    'named verified proof selection remains separate from private bytes',
    () async {
      await c.load();
      c.select(c.documents.single, true);
      expect(c.proofs.single.toJson(), {
        'id': document,
        'version': 1,
        'digest': 'a' * 64,
      });
      expect(c.preview, null);
      await c.view(c.documents.single);
      expect(c.preview, [65, 66, 67, 68]);
      c.closePreview();
      expect(c.preview, null);
    },
  );
  test(
    'new upload reserves verifies and attaches exact scoped proof',
    () async {
      await c.load();
      await c.uploadNew('Synthetic upload purpose');
      expect(server.writes, 2);
      expect(c.confirmed!.entity['action'], 'complete');
      expect(c.proofs, hasLength(1));
      expect(server.last!.payload['expense_id'], expense);
      expect(
        await drafts.recoveryIds(
          scope,
          project,
          expense,
          expenseEvidenceManage,
        ),
        isEmpty,
      );
    },
  );
  test(
    'view-only evidence cannot change the expense proof selection',
    () async {
      server.denyManage = true;
      await c.load();
      expect(c.documents, hasLength(1));
      expect(c.canManage, false);
      c.select(c.documents.single, true);
      expect(c.proofs, isEmpty);
      expect(server.writes, 0);
    },
  );
  test('lost policy response is discoverable after controller recreation and resolves original identity', () async {
    await c.load();
    server.uncertain = true;
    await c.createPolicy(30, 'Synthetic entity policy');
    final command = server.last!;
    c.dispose();
    c = controller();
    await c.load();
    expect(c.policyRecoveries, [command.payload['id']]);
    server.uncertain = false;
    final savedReceipt = await drafts.receipt(
      scope,
      null,
      null,
      command.payload['id'] as String,
      expenseEvidenceRetention,
    );
    expect(savedReceipt!['command_id'], command.commandId);
    await c.retryPolicy(command.payload['id'] as String);
    expect(c.error, null);
    expect(c.confirmed!.commandId, command.commandId);
    expect(server.writes, 1);
    expect(c.policyRecoveries, isEmpty);
  });
  test(
    'expired policy body keeps minimal receipt and blocks replacement choice',
    () async {
      await c.load();
      server.uncertain = true;
      server.keepReceipt = false;
      await c.createPolicy(30, 'Private expired purpose');
      final command = server.last!;
      now = now.add(const Duration(hours: 25));
      c.dispose();
      c = controller();
      await c.load();
      await c.retryPolicy(command.payload['id'] as String);
      expect(c.notice, contains('expired'));
      expect(c.policyRecoveries, [command.payload['id']]);
      await c.createPolicy(60, 'Replacement rejected');
      expect(server.writes, 1);
      final receipt = await drafts.receipt(
        scope,
        null,
        null,
        command.payload['id'] as String,
        expenseEvidenceRetention,
      );
      expect(receipt!['command_id'], command.commandId);
      expect(receipt.containsKey('purpose'), false);
    },
  );
  test(
    'verified confirmation survives failed encrypted receipt cleanup',
    () async {
      await c.load();
      await db.customStatement(
        "CREATE TEMP TRIGGER fail_evidence_cleanup BEFORE DELETE ON encrypted_drafts BEGIN SELECT RAISE(ABORT, 'synthetic cleanup failure'); END",
      );
      await c.retention(
        c.documents.single,
        'hold',
        'Synthetic hold',
        reviewDate: '2026-11-05',
      );
      expect(c.confirmed!.entity['action'], 'hold');
      expect(c.error, null);
      expect(c.notice, contains('confirmed'));
      expect(c.recoveries, hasLength(1));
      await db.customStatement('DROP TRIGGER fail_evidence_cleanup');
      server.onWrite = null;
      await c.retry(document, expenseEvidenceRetention);
      expect(server.writes, 1);
      expect(c.recoveries, isEmpty);
    },
  );
  test(
    'retired original proof can be detached but never newly attached',
    () async {
      c.dispose();
      c = ExpenseEvidenceController(
        scope: scope,
        projectId: project,
        expenseId: expense,
        repository: server,
        drafts: drafts,
        files: files,
        initialProofs: [server.rows[document]!.proof],
      );
      server.rows[document] = ExpenseEvidenceDocument.fromJson(
        server.metadata(document, status: 'retired', version: 3),
      );
      await c.load();
      c.select(c.documents.single, false);
      expect(c.proofs, isEmpty);
      c.select(c.documents.single, true);
      expect(c.proofs, isEmpty);
      expect(server.writes, 0);
    },
  );
  test(
    'current permission loss clears private visible metadata and preview',
    () async {
      await c.load();
      await c.view(c.documents.single);
      server.deny = true;
      await c.load();
      expect(c.documents, isEmpty);
      expect(c.preview, null);
      expect(c.selected, isEmpty);
    },
  );
  test(
    'late file picker after disposal performs no reservation or upload',
    () async {
      await c.load();
      files.picker = Completer<ExpensePickedDocument?>();
      final work = c.uploadNew('Late source');
      await Future<void>.delayed(Duration.zero);
      c.dispose();
      files.picker!.complete(files.file);
      await work;
      expect(server.writes, 0);
      c = controller();
    },
  );
  test(
    'late private byte response after disposal cannot repopulate preview',
    () async {
      await c.load();
      server.readGate = Completer<void>();
      final work = c.view(c.documents.single);
      await Future<void>.delayed(Duration.zero);
      c.dispose();
      server.readGate!.complete();
      await work;
      expect(c.preview, null);
      c = controller();
    },
  );
  test('export rechecks authorization after bytes and never writes revoked content', () async {
    await c.load();
    server.onRead = () {
      server.denyExport = true;
    };
    await c.export(c.documents.single);
    expect(files.writes, 0);
    expect(c.preview, null);
    expect(c.error, contains('denied'));
  });
  testWidgets('unavailable delivery is explicit and upload stays disabled', (
    tester,
  ) async {
    server.available = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ExpenseEvidencePanel(
                scope: scope,
                projectId: project,
                expenseId: expense,
                repository: server,
                drafts: drafts,
                files: files,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('delivery is unavailable'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Choose and verify evidence'),
          )
          .onPressed,
      null,
    );
  });
  testWidgets('verified malformed image fails as an actionable preview state', (
    tester,
  ) async {
    server.rows[document] = ExpenseEvidenceDocument.fromJson({
      ...server.metadata(document),
      'mime': 'image/png',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ExpenseEvidencePanel(
                scope: scope,
                projectId: project,
                expenseId: expense,
                repository: server,
                drafts: drafts,
                files: files,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('View verified bytes'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
    expect(
      find.textContaining('cannot be decoded as an image'),
      findsOneWidget,
    );
  });
  testWidgets(
    'closing private image preview evicts its decoded framework cache',
    (tester) async {
      server.readBytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      server.rows[document] = ExpenseEvidenceDocument.fromJson({
        ...server.metadata(document),
        'mime': 'image/png',
        'byte_size': server.readBytes.length,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                ExpenseEvidencePanel(
                  scope: scope,
                  projectId: project,
                  expenseId: expense,
                  repository: server,
                  drafts: drafts,
                  files: files,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('View verified bytes'));
      await tester.pumpAndSettle();
      final provider = tester.widget<Image>(find.byType(Image)).image;
      final key = await provider.obtainKey(ImageConfiguration.empty);
      expect(
        PaintingBinding.instance.imageCache.statusForKey(key).untracked,
        false,
      );
      await tester.ensureVisible(find.text('Close private preview'));
      await tester.tap(find.text('Close private preview'));
      await tester.pumpAndSettle();
      expect(
        PaintingBinding.instance.imageCache.statusForKey(key).untracked,
        true,
      );
      expect(tester.takeException(), null);
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'private evidence remains readable at 200 percent ${dark ? 'dark' : 'light'}',
      (tester) async {
        tester.view.physicalSize = const Size(1024, 720);
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
            home: Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  ExpenseEvidencePanel(
                    scope: scope,
                    projectId: project,
                    expenseId: expense,
                    repository: server,
                    drafts: drafts,
                    files: files,
                    initialProofs: [server.rows[document]!.proof],
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('View verified bytes'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), null);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            'goldens/expense_evidence_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
      },
    );
  }
}
