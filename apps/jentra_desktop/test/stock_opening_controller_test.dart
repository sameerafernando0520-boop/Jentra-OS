import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/features/stock_opening/stock_opening_controller.dart';
import 'package:jentra_domain/jentra_stock_opening.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_stock_opening_platform.dart';
import 'stock_opening_fixtures.dart';

void main() {
  late JentraLocalDatabase db;
  late StockOpeningDraftStore drafts;
  late FakeStockOpeningRepository repo;
  late StockOpeningController c;
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = StockOpeningDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: OpeningMemoryKeys())),
    );
    repo = FakeStockOpeningRepository();
    c = StockOpeningController(
      scope: openingScope,
      capabilities: openingPermissions,
      repository: repo,
      drafts: drafts,
      online: true,
    );
  });
  tearDown(() async {
    if (c.active) c.dispose();
    await db.close();
  });
  test(
    'uncertain posting retries identical envelope after reopening controller',
    () async {
      repo.doc = StockOpeningDocument(openingSnapshot(status: 'approved'));
      await c.open(repo.doc);
      repo.failure = TimeoutException('Response lost');
      await c.action('post');
      expect(c.pending, true);
      final original = repo.commands.single.toJson((p) => p);
      final slot = c.slot!;
      c.dispose();
      c = StockOpeningController(
        scope: openingScope,
        capabilities: openingPermissions,
        repository: repo,
        drafts: drafts,
        online: true,
      );
      await c.recover(slot);
      expect(c.form, isNull);
      expect(c.pending, true);
      repo.failure = null;
      await c.retry();
      expect(repo.commands.last.toJson((p) => p), original);
      expect(c.document!.status, 'posted');
      expect(c.local, isNull);
    },
  );
  test(
    'register reopen keeps interrupted and rejected posting snapshots read-only',
    () async {
      repo.doc = StockOpeningDocument(openingSnapshot(status: 'approved'));
      await c.open(repo.doc);
      repo.failure = TimeoutException('Response lost');
      await c.action('post');
      c.dispose();
      c = StockOpeningController(
        scope: openingScope,
        capabilities: openingPermissions,
        repository: repo,
        drafts: drafts,
        online: true,
      );
      await c.open(repo.doc);
      expect(c.pending, true);
      expect(c.form, isNull);
      expect(c.canEdit, false);
      repo.failure = const StockOpeningFailure(
        'PERIOD_CLOSED',
        'The opening period is closed.',
        definite: true,
      );
      await c.retry();
      expect(c.pending, false);
      await c.closeEditor();
      await c.open(repo.doc);
      expect(c.local!.data['operation'], 'post_stock_opening');
      expect(c.form, isNull);
      expect(c.canEdit, false);
    },
  );
  test(
    'submit and approval use the explicit opening transition command',
    () async {
      await c.open(repo.doc);
      await c.action('submit');
      expect(repo.rpcs.single, 'transition_stock_opening');
      await c.action('approve');
      expect(repo.rpcs.last, 'transition_stock_opening');
      expect(repo.commands.last.payload['decision'], 'approved');
    },
  );
  test('creator editor and submitter cannot approve their own count', () async {
    for (final field in ['created_by', 'prepared_by', 'submitted_by']) {
      repo.doc = StockOpeningDocument({
        ...openingSnapshot(status: 'pending_approval'),
        field: 'actor',
      });
      await c.open(repo.doc);
      expect(c.allows('approve'), false);
      await c.action('approve');
    }
    expect(repo.commands, isEmpty);
  });
  test('draft and incomplete approval cannot post', () async {
    for (final status in [
      'draft',
      'pending_approval',
      'rejected',
      'cancelled',
    ]) {
      repo.doc = StockOpeningDocument(openingSnapshot(status: status));
      await c.open(repo.doc);
      await c.action('post');
    }
    expect(repo.commands, isEmpty);
  });
  test('offline local edits survive and no command is sent', () async {
    c.setOnline(false);
    await c.create();
    expect(c.local, isNotNull);
    await c.saveServer();
    await c.action('submit');
    expect(repo.commands, isEmpty);
  });
  test(
    'storage failure preserves editor and prevents leaving or dispatch',
    () async {
      await c.open(repo.doc);
      await db.customStatement(
        "CREATE TEMP TRIGGER fail_opening BEFORE INSERT ON encrypted_drafts BEGIN SELECT RAISE(FAIL,'disk full'); END",
      );
      await c.edit();
      expect(c.form, isNotNull);
      expect(c.localSaveFailed, true);
      expect(await c.canLeave(), false);
      await c.closeEditor();
      expect(c.form, isNotNull);
      await c.saveServer();
      expect(repo.commands, isEmpty);
      await db.customStatement('DROP TRIGGER fail_opening');
      await c.saveLocal(c.form!);
      expect(c.localSaveFailed, false);
      expect(await c.canLeave(), true);
    },
  );
  test(
    'stale version retains fields until explicit discard and reload',
    () async {
      await c.open(repo.doc);
      await c.edit();
      await c.saveLocal({...c.form!, 'reason': 'Recount preserved'});
      repo.failure = const StockOpeningFailure(
        'VERSION_CONFLICT',
        'Changed',
        definite: true,
      );
      await c.saveServer();
      expect(c.conflict, true);
      expect(c.pending, false);
      expect(c.form!['reason'], 'Recount preserved');
      await c.saveServer();
      expect(repo.commands, hasLength(1));
      repo.failure = null;
      await c.discardAndReload();
      expect(c.conflict, false);
      expect(c.form, isNull);
    },
  );
  test('rapid save edits are serialized before server dispatch', () async {
    await c.open(repo.doc);
    await c.edit();
    final first = c.saveLocal({...c.form!, 'reason': 'First count'});
    final last = c.saveLocal({...c.form!, 'reason': 'Final counted stock'});
    await Future.wait([first, last]);
    await c.saveServer();
    expect(repo.commands.single.payload['reason'], 'Final counted stock');
  });
  test('duplicate posting clicks dispatch one command', () async {
    repo.doc = StockOpeningDocument(openingSnapshot(status: 'approved'));
    await c.open(repo.doc);
    repo.gate = Completer<void>();
    final first = c.action('post');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await c.action('post');
    repo.gate!.complete();
    await first;
    expect(repo.commands, hasLength(1));
  });
  test('lost cost permission blocks creation and recovery', () async {
    await c.open(repo.doc);
    await c.edit();
    final slot = c.slot!;
    c.dispose();
    c = StockOpeningController(
      scope: openingScope,
      capabilities: {'inventory.adjustments.post'},
      repository: repo,
      drafts: drafts,
      online: true,
    );
    await c.create();
    await c.recover(slot);
    expect(c.form, isNull);
    expect(repo.commands, isEmpty);
  });
}
