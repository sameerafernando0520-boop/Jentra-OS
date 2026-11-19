import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_sales/src/data/sales_gateway.dart';
import 'package:jentra_sales/src/data/sales_store.dart';
import 'package:jentra_sales/src/models.dart';
import 'package:jentra_sales/src/sales_controller.dart';

SalesOrder _draft(SalesController c, String id) => SalesOrder(
  id: id,
  commandId: 'command-$id',
  customerId: c.customers.first.id,
  date: c.now(),
  lines: [SalesLine(c.products.first, '1')],
  local: true,
  customerState: 'Not requested',
  companyState: 'Not submitted',
  deliveryState: 'Not scheduled',
);

void main() {
  testWidgets(
    'an open preview expires local draft bodies at their original lease',
    (tester) async {
      var time = DateTime.utc(2026, 11, 4, 8);
      final store = MemorySalesStore();
      final c = SalesController(store: store, now: () => time);
      addTearDown(c.dispose);
      await c.enterPreview();
      await c.saveDraft(_draft(c, 'draft-open'));
      time = time.add(const Duration(hours: 24));
      await tester.pump(const Duration(hours: 24));
      await tester.pump();
      expect(c.orders.where((o) => o.local), isEmpty);
      expect(store.values.values.single, '[]');
    },
  );

  testWidgets(
    'a blocked same-id save cannot retain or resurrect an expired draft',
    (tester) async {
      var time = DateTime.utc(2026, 11, 4, 8);
      final store = _RecoverableStore();
      final c = SalesController(store: store, now: () => time);
      addTearDown(c.dispose);
      await c.enterPreview();
      await c.saveDraft(_draft(c, 'draft-original'));
      time = time.add(const Duration(hours: 23));
      await tester.pump(const Duration(hours: 23));

      final releaseWrite = Completer<void>();
      final writeStarted = Completer<void>();
      store.writeGate = releaseWrite;
      store.writeStarted = writeStarted;
      final saving = c
          .saveDraft(_draft(c, 'draft-original'))
          .then<Object?>(
            (_) => null,
            onError: (Object error, StackTrace _) => error,
          );
      await writeStarted.future;
      time = time.add(const Duration(hours: 1));
      await tester.pump(const Duration(hours: 1));
      await tester.pump();
      final hiddenWhileWriteIsBlocked = !c.orders.any(
        (o) => o.local && o.id == 'draft-original',
      );

      // Finish the blocked operation before asserting so a red run also cleans
      // up every pending write and expiry job.
      releaseWrite.complete();
      final error = await saving;
      await tester.pump();
      await tester.pump();
      expect(hiddenWhileWriteIsBlocked, isTrue);
      if (error != null) {
        expect(
          error,
          isA<SalesFailure>().having((e) => e.code, 'code', 'DRAFT_EXPIRED'),
        );
      }
      expect(c.orders.where((o) => o.local), isEmpty);
      expect(store.values.values.single, '[]');
    },
  );

  testWidgets(
    'a blocked new draft save redacts expired bodies and preserves its own lease',
    (tester) async {
      var time = DateTime.utc(2026, 11, 4, 8);
      final store = _RecoverableStore();
      final c = SalesController(store: store, now: () => time);
      addTearDown(c.dispose);
      await c.enterPreview();
      await c.saveDraft(_draft(c, 'draft-old'));
      time = time.add(const Duration(hours: 23));
      await tester.pump(const Duration(hours: 23));

      final releaseWrite = Completer<void>();
      final writeStarted = Completer<void>();
      store.writeGate = releaseWrite;
      store.writeStarted = writeStarted;
      final saving = c
          .saveDraft(_draft(c, 'draft-new'))
          .then<Object?>(
            (_) => null,
            onError: (Object error, StackTrace _) => error,
          );
      await writeStarted.future;
      time = time.add(const Duration(hours: 1));
      await tester.pump(const Duration(hours: 1));
      await tester.pump();
      final oldBodyHiddenWhileWriteIsBlocked = !c.orders.any(
        (o) => o.local && o.id == 'draft-old',
      );

      releaseWrite.complete();
      final error = await saving;
      await tester.pump();
      await tester.pump();
      expect(oldBodyHiddenWhileWriteIsBlocked, isTrue);
      expect(error, isNull);
      expect(c.orders.where((o) => o.local).map((o) => o.id), ['draft-new']);
      final saved = jsonDecode(store.values.values.single) as List;
      expect(saved.map((o) => (o as Map)['id']), ['draft-new']);
      await c.leave();
    },
  );

  test(
    'preview marks itself busy before waiting for account cleanup',
    () async {
      final account = _DelayedLogoutAccount();
      final c = SalesController(store: MemorySalesStore(), account: account);
      addTearDown(c.dispose);
      final opening = c.enterPreview();
      final wasBusy = c.busy;
      account.logout.complete();
      await opening;
      expect(wasBusy, isTrue);
    },
  );

  test('leaving during preview logout cannot reopen the workspace', () async {
    final account = _DelayedLogoutAccount();
    final c = SalesController(store: MemorySalesStore(), account: account);
    addTearDown(c.dispose);
    final opening = c.enterPreview();
    await c.leave();
    account.logout.complete();
    await opening;
    expect(c.preview, isFalse);
    expect(c.customers, isEmpty);
    expect(c.orders, isEmpty);
  });

  test('disposal during preview logout completes without notifying', () async {
    final account = _DelayedLogoutAccount();
    final store = _RecoverableStore();
    final c = SalesController(store: store, account: account);
    final opening = c.enterPreview();
    c.dispose();
    account.logout.complete();
    await expectLater(opening, completes);
    expect(store.reads, 0);
  });

  test('a failed draft read cannot replace recoverable drafts', () async {
    final store = _RecoverableStore();
    final original = SalesController(store: store);
    await original.enterPreview();
    await original.saveDraft(_draft(original, 'draft-old'));
    final originalWire = store.values.values.single;
    original.dispose();

    store.failNextRead = true;
    final c = SalesController(store: store);
    addTearDown(c.dispose);
    await c.enterPreview();
    expect(c.notice, isNotNull);
    await expectLater(
      c.saveDraft(_draft(c, 'draft-new')),
      throwsA(isA<SalesFailure>()),
    );
    expect(store.values.values.single, originalWire);

    await c.enterPreview();
    await c.saveDraft(_draft(c, 'draft-new'));
    expect(c.orders.where((o) => o.local).map((o) => o.id).toSet(), {
      'draft-old',
      'draft-new',
    });
  });

  test('an unsupported draft blob stays intact until recovery', () async {
    const originalWire = '{"future_schema":true}';
    final store = _RecoverableStore()
      ..values['jentra.sales.preview.drafts.v1'] = originalWire;
    final c = SalesController(store: store);
    addTearDown(c.dispose);
    await c.enterPreview();
    expect(c.notice, isNotNull);
    await expectLater(
      c.saveDraft(_draft(c, 'draft-new')),
      throwsA(isA<SalesFailure>()),
    );
    expect(store.values.values.single, originalWire);
  });

  test('preview recovery waits for an earlier draft write', () async {
    final store = _RecoverableStore();
    final c = SalesController(store: store);
    addTearDown(c.dispose);
    await c.enterPreview();
    final releaseWrite = Completer<void>();
    final writeStarted = Completer<void>();
    store.writeGate = releaseWrite;
    store.writeStarted = writeStarted;
    final saving = c.saveDraft(_draft(c, 'draft-first'));
    await writeStarted.future;
    final reopening = c.enterPreview();
    await Future<void>.delayed(Duration.zero);
    releaseWrite.complete();
    await Future.wait([saving, reopening]);
    expect(c.orders.where((o) => o.local).map((o) => o.id), ['draft-first']);
    await c.saveDraft(_draft(c, 'draft-second'));
    final saved = jsonDecode(store.values.values.single) as List;
    expect(saved.map((o) => (o as Map)['id']).toSet(), {
      'draft-first',
      'draft-second',
    });
  });

  test('reopening excludes drafts that expire during cleanup', () async {
    var time = DateTime.utc(2026, 11, 4, 8);
    final store = _RecoverableStore();
    final c = SalesController(store: store, now: () => time);
    addTearDown(c.dispose);
    await c.enterPreview();
    await c.saveDraft(_draft(c, 'draft-expired'));
    time = time.add(const Duration(hours: 1));
    await c.saveDraft(_draft(c, 'draft-near-expiry'));
    time = time.add(const Duration(hours: 1));
    await c.saveDraft(_draft(c, 'draft-still-valid'));
    await c.leave();
    time = time.add(const Duration(hours: 22));

    final releaseWrite = Completer<void>();
    final writeStarted = Completer<void>();
    store.writeGate = releaseWrite;
    store.writeStarted = writeStarted;
    final shown = <String>{};
    c.addListener(() {
      if (c.preview && !c.busy) {
        shown.addAll(c.orders.where((o) => o.local).map((o) => o.id));
      }
    });
    final opening = c.enterPreview();
    await writeStarted.future;
    time = time.add(const Duration(hours: 1));
    releaseWrite.complete();
    await opening;

    expect(shown, {'draft-still-valid'});
    final saved = jsonDecode(store.values.values.single) as List;
    expect(saved.map((o) => (o as Map)['id']), ['draft-still-valid']);
  });

  test('editing a draft does not restart its original 24-hour lease', () async {
    var time = DateTime.utc(2026, 11, 4, 8);
    final c = SalesController(store: MemorySalesStore(), now: () => time);
    addTearDown(c.dispose);
    await c.enterPreview();
    await c.saveDraft(_draft(c, 'draft-original'));
    time = time.add(const Duration(hours: 23));
    // The editor constructs a same-id replacement stamped with its current time.
    await c.saveDraft(_draft(c, 'draft-original'));
    time = time.add(const Duration(hours: 1));
    await c.enterPreview();
    expect(c.orders.where((o) => o.local), isEmpty);
  });
}

final class _DelayedLogoutAccount implements SalesAccountGateway {
  final logout = Completer<void>();
  int logouts = 0;

  @override
  Future<void> signIn(String email, String password) async {}

  @override
  Future<void> signOut() async {
    if (++logouts == 1) await logout.future;
  }
}

final class _RecoverableStore implements SalesKeyValueStore {
  final values = <String, String>{};
  bool failNextRead = false;
  int reads = 0;
  Completer<void>? writeGate;
  Completer<void>? writeStarted;

  @override
  Future<String?> read(String key) async {
    reads++;
    if (failNextRead) {
      failNextRead = false;
      throw const SalesFailure('STORAGE_UNAVAILABLE', 'Unavailable');
    }
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    final gate = writeGate;
    if (gate != null) {
      writeGate = null;
      writeStarted?.complete();
      await gate.future;
    }
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
