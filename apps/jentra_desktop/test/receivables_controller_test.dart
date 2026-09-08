import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/features/receivables/receivables_controller.dart';
import 'package:jentra_domain/jentra_receivables.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_receivables_platform.dart';

const scope = TenantContext(
  tenantId: 'tenant',
  actorId: 'actor',
  legalEntityId: 'entity',
  branchId: 'branch',
);
final permissions = {
  for (final k in ReceivableKind.values) ...[
    '${k.permission}.view',
    k.managePermission,
    k.postPermission,
  ],
  'finance.receipts.allocate',
  'finance.receivables.view',
  'finance.setup.manage',
  'workflow.approvals.decide',
};

class MemoryKeys implements SecretKeyStore {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }
}

Map<String, Object?> snapshot({
  String status = 'draft',
  ReceivableKind kind = ReceivableKind.invoice,
}) => {
  'id': '00000000-0000-4000-8000-000000000001',
  'document_type': kind.wire,
  'document_number': 'INV-0001',
  'customer_id': 'customer',
  'customer_name': 'Acme Workplace Services',
  'document_date': '2026-09-07',
  'due_date': '2026-10-07',
  'currency_code': 'LKR',
  'grand_total': '118000.000000',
  'base_total': '118000.000000',
  'tax_total': '18000.000000',
  'version': 3,
  'status': status,
  'lines': [
    {
      'id': 'line',
      'description': 'Managed workplace installation',
      'base_quantity': '1.000000',
      'taxable_amount': '100000.000000',
      'tax_amount': '18000.000000',
      'line_total': '118000.000000',
      'snapshot': {
        'line_id': 'line',
        'product_id': 'product',
        'description': 'Managed workplace installation',
        'unit_id': 'unit',
        'base_quantity': '1',
        'quantity': '1',
        'unit_price': '100000',
        'conversion_numerator': '1',
        'conversion_denominator': '1',
      },
    },
  ],
};

class FakeReceivables implements ReceivablesRepository {
  ReceivableDocument doc = ReceivableDocument(snapshot());
  Object? failure;
  Completer<void>? gate;
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  final rpcs = <String>[];
  @override
  Future<CursorPage<ReceivableDocument>> page(
    TenantContext s,
    ReceivableKind k, {
    String? cursor,
    String? status,
  }) async => CursorPage(items: [doc], limit: 50);
  @override
  Future<ReceivableDocument> find(
    TenantContext s,
    ReceivableKind k,
    String id,
  ) async => doc;
  @override
  Future<Map<String, Object?>> command(
    String rpc,
    CommandEnvelope<Map<String, Object?>> e,
  ) async {
    commands.add(e);
    rpcs.add(rpc);
    await gate?.future;
    if (failure != null) throw failure!;
    return {
      'request_id': 'request',
      'command_id': e.commandId,
      'entity': doc.data,
    };
  }

  @override
  Future<CursorPage<Map<String, Object?>>> references(
    TenantContext s,
    String resource, {
    String? cursor,
    String? customerId,
    String? sourceId,
  }) async => CursorPage(items: [], limit: 50);
  @override
  Future<Map<String, Object?>> statement(
    TenantContext s,
    String customer,
    String currency,
    String asOf,
    List<int> buckets,
  ) async => {
    'open_amount': '118000.000000',
    'open_base_amount': '118000.000000',
    'rows': [],
    'aging': [],
    'bucket_days': buckets,
  };
}

void main() {
  late JentraLocalDatabase db;
  late ReceivableDraftStore drafts;
  late FakeReceivables repo;
  late ReceivablesController c;
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = ReceivableDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: MemoryKeys())),
    );
    repo = FakeReceivables();
    c = ReceivablesController(
      scope: scope,
      capabilities: permissions,
      repository: repo,
      drafts: drafts,
      online: true,
    );
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  test('uncertain posting keeps envelope and identical retry', () async {
    repo.doc = ReceivableDocument(snapshot(status: 'approved'));
    await c.open(repo.doc);
    repo.failure = TimeoutException('dropped');
    await c.action('post');
    expect(c.pending, true);
    final saved = repo.commands.single.toJson((p) => p);
    repo.failure = null;
    await c.retry();
    expect(repo.commands.last.toJson((p) => p), saved);
    expect(c.pending, false);
    expect(c.local, isNull);
    expect(c.message, contains('request'));
  });
  test('duplicate clicks dispatch one mutation', () async {
    repo.doc = ReceivableDocument(snapshot(status: 'approved'));
    await c.open(repo.doc);
    repo.gate = Completer<void>();
    final first = c.action('post');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await c.action('post');
    repo.gate!.complete();
    await first;
    expect(repo.commands, hasLength(1));
  });
  test('offline drafts persist but cannot submit or post', () async {
    c.setOnline(false);
    await c.create();
    expect(c.form, isNotNull);
    expect(await drafts.load(scope, c.slot!), isNotNull);
    await c.saveServer();
    await c.action('post');
    expect(repo.commands, isEmpty);
  });
  test('view-only permission cannot create or post', () async {
    final view = ReceivablesController(
      scope: scope,
      capabilities: {'sales.invoices.view'},
      repository: repo,
      drafts: drafts,
      online: true,
    );
    await view.create();
    expect(view.form, isNull);
    await view.open(repo.doc);
    await view.action('post');
    expect(repo.commands, isEmpty);
    view.dispose();
  });
  test(
    'stale version retains draft and blocks overwrite until explicit reload',
    () async {
      await c.open(repo.doc);
      await c.edit();
      repo.failure = const ReceivableFailure(
        'VERSION_CONFLICT',
        'Changed',
        definite: true,
      );
      await c.saveServer();
      expect(c.conflict, true);
      expect(c.form, isNotNull);
      expect(c.pending, false);
      final count = repo.commands.length;
      await c.saveServer();
      expect(repo.commands, hasLength(count));
      await c.discardAndReload();
      expect(c.conflict, false);
      expect(c.form, isNull);
    },
  );
  test('closing editor preserves all latest serialized field edits', () async {
    await c.create();
    final slot = c.slot!;
    await Future.wait([
      for (var i = 0; i < 5; i++) c.saveLocal({...c.form!, 'notes': 'edit $i'}),
    ]);
    await c.closeEditor();
    expect((await drafts.load(scope, slot))!.form['notes'], 'edit 4');
    await c.recover(slot);
    expect(c.form!['notes'], 'edit 4');
  });
  test(
    'definite posting rejection does not strand hidden pending command',
    () async {
      repo.doc = ReceivableDocument(snapshot(status: 'approved'));
      await c.open(repo.doc);
      repo.failure = const ReceivableFailure(
        'PERIOD_CLOSED',
        'Closed',
        definite: true,
      );
      await c.action('post');
      expect(c.local, isNotNull);
      expect(c.pending, false);
      expect(c.local!.form['document_type'], 'sales_invoice');
      await c.discardAndReload();
      expect(c.local, isNull);
      expect(c.canAct, true);
    },
  );
}
