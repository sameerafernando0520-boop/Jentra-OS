@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_employee/src/data/employee_gateway.dart';
import 'package:jentra_employee/src/data/employee_storage.dart';
import 'package:jentra_employee/src/data/employee_storage_factory.dart'
    as storage_factory;
import 'package:jentra_employee/src/data/employee_storage_web.dart';
import 'package:jentra_employee/src/employee_controller.dart';

import 'support/employee_fixture.dart';

var _sequence = 0;
String _project() =>
    'https://storage-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}.example.test';

Matcher _failure(String code) =>
    throwsA(isA<EmployeeFailure>().having((error) => error.code, 'code', code));

Future<void> _cleanup(WebEmployeeKeyValueStore store) async {
  await store.close();
  await _request(_idb.deleteDatabase(store.databaseName));
}

void main() {
  test(
    'conditional factory selects the encrypted browser implementation',
    () async {
      final store = storage_factory.createEmployeeKeyValueStore(
        projectUrl: _project(),
      );
      expect(store, isA<WebEmployeeKeyValueStore>());
      final browserStore = store as WebEmployeeKeyValueStore;
      addTearDown(() => _cleanup(browserStore));
      expect(await store.read('jentra.employee.test.absent'), isNull);
    },
  );

  test('raw records contain only ciphertext, random IV and schema; key cannot export', () async {
    final store = WebEmployeeKeyValueStore(projectUrl: _project());
    addTearDown(() => _cleanup(store));
    const logicalKey = 'jentra.employee.auth.session.v1';
    const secret = 'synthetic-session-with-private-account-body';
    await store.write(logicalKey, secret);
    final first = await _snapshot(store.databaseName, 'records');
    expect(first.keys.single.toDart, matches(RegExp(r'^[0-9a-f]{64}$')));
    final record = first.values.single as JSObject;
    expect(_keys(record).toDart.map((key) => key.toDart).toSet(), {
      'schema',
      'iv',
      'ciphertext',
    });
    final iv = (record.getProperty('iv'.toJS) as JSUint8Array).toDart;
    final ciphertext =
        (record.getProperty('ciphertext'.toJS) as JSArrayBuffer).toDart;
    expect(iv.length, 12);
    expect(
      utf8.decode(Uint8List.view(ciphertext), allowMalformed: true),
      isNot(contains(secret)),
    );
    final metadata =
        (await _snapshot(store.databaseName, 'keys')).values.single as JSObject;
    final key = metadata.getProperty('key'.toJS) as JSObject;
    expect((key.getProperty('extractable'.toJS) as JSBoolean).toDart, isFalse);
    await expectLater(_subtle.exportKey('raw', key).toDart, throwsA(anything));
    await store.write(logicalKey, secret);
    final next =
        (await _snapshot(store.databaseName, 'records')).values.single
            as JSObject;
    expect(
      (next.getProperty('iv'.toJS) as JSUint8Array).toDart,
      isNot(orderedEquals(iv)),
    );
    expect(await store.read(logicalKey), secret);
  });

  test(
    'reopen restores encrypted auth PKCE draft and exact sealed command IDs',
    () async {
      final project = _project();
      final first = WebEmployeeKeyValueStore(projectUrl: project);
      final auth = EmployeeAuthStorage(first);
      final pkce = EmployeePkceStorage(first);
      final drafts = EmployeeDraftStore(first);
      await auth.persistSession(
        '{"token":"synthetic-only","actor":"$fixtureActor"}',
      );
      await pkce.setItem(key: 'verifier', value: 'synthetic-pkce-verifier');
      final pending = EmployeePendingCommand.create(
        workspace: fixtureWorkspace,
        actorId: fixtureActor,
        employeeId: fixtureEmployee,
        action: 'review_acknowledge',
        targetId: fixtureReview().id,
        expectedVersion: fixtureReview().version,
        now: DateTime.now(),
      );
      await drafts.savePending(pending);
      const person = EmployeeIdentity(
        workspace: fixtureWorkspace,
        actorId: fixtureActor,
        employeeId: fixtureEmployee,
        displayName: 'Fixture employee',
      );
      final today = DateTime.now();
      await drafts.saveDraft(
        person,
        EmployeeLeaveDraft(
          leaveType: 'Annual',
          reason: 'Synthetic private reason',
          startDate: today,
          endDate: today,
        ),
      );
      await first.close();
      final second = WebEmployeeKeyValueStore(projectUrl: project);
      addTearDown(() => _cleanup(second));
      expect(
        await EmployeeAuthStorage(second).accessToken(),
        '{"token":"synthetic-only","actor":"$fixtureActor"}',
      );
      expect(
        await EmployeePkceStorage(second).getItem(key: 'verifier'),
        'synthetic-pkce-verifier',
      );
      final restored = await EmployeeDraftStore(second)
          .loadPending(fixtureWorkspace, fixtureActor);
      expect(restored!.envelope.commandId, pending.envelope.commandId);
      expect(restored.envelope.idempotencyKey, pending.envelope.idempotencyKey);
      expect(restored.toJson(), pending.toJson());
      expect(
        (await EmployeeDraftStore(second).loadDraft(person))?.reason,
        'Synthetic private reason',
      );
      expect(
        await EmployeeDraftStore(second)
            .loadPending(fixtureWorkspace, fixtureEmployee),
        isNull,
      );
    },
  );

  test('moving a valid ciphertext to another logical owner fails without deleting recovery', () async {
    final store = WebEmployeeKeyValueStore(projectUrl: _project());
    addTearDown(() => _cleanup(store));
    const a = 'jentra.employee.v1.pending.actor-a';
    const b = 'jentra.employee.v1.pending.actor-b';
    await store.write(a, 'request-a');
    final first = await _snapshot(store.databaseName, 'records');
    final idA = first.keys.single;
    final recordA = first.values.single;
    await store.write(b, 'request-b');
    final both = await _snapshot(store.databaseName, 'records');
    final idB = both.keys.singleWhere((key) => key.toDart != idA.toDart);
    await _rawWrite(store.databaseName, 'records', idB, recordA!);
    await expectLater(store.read(b), _failure('STORAGE_UNAVAILABLE'));
    expect(await store.read(a), 'request-a');
    expect((await _snapshot(store.databaseName, 'records')).keys.length, 2);
  });

  test(
    'missing persisted crypto key never resets encrypted pending records',
    () async {
      final project = _project();
      final first = WebEmployeeKeyValueStore(projectUrl: project);
      await first.write(
        'jentra.employee.v1.pending.owner',
        'sealed-original-intent',
      );
      await _rawDelete(first.databaseName, 'keys', 'primary'.toJS);
      await first.close();
      final second = WebEmployeeKeyValueStore(projectUrl: project);
      addTearDown(() => _cleanup(second));
      await expectLater(
        second.read('jentra.employee.v1.pending.owner'),
        _failure('STORAGE_UNAVAILABLE'),
      );
      expect((await _snapshot(second.databaseName, 'keys')).keys, isEmpty);
      expect((await _snapshot(second.databaseName, 'records')).keys.length, 1);
    },
  );

  test('one context owns browser recovery until it closes; failed contender cannot release it', () async {
    final project = _project();
    final first = WebEmployeeKeyValueStore(projectUrl: project);
    await first.write('jentra.employee.test.private', 'original');
    final contender = WebEmployeeKeyValueStore(projectUrl: project);
    await expectLater(
      contender.read('jentra.employee.test.private'),
      _failure('BROWSER_STORAGE_IN_USE'),
    );
    await contender.close();
    await first.write('jentra.employee.test.private', 'still-owned');
    await first.close();
    final replacement = WebEmployeeKeyValueStore(projectUrl: project);
    addTearDown(() => _cleanup(replacement));
    expect(
      await replacement.read('jentra.employee.test.private'),
      'still-owned',
    );
  });

  test(
    'concurrent persistence and logout finish with verified session removal',
    () async {
      final store = WebEmployeeKeyValueStore(projectUrl: _project());
      addTearDown(() => _cleanup(store));
      final auth = EmployeeAuthStorage(store);
      final saving = auth.persistSession('synthetic-session');
      final removing = auth.removePersistedSession();
      await Future.wait([saving, removing]);
      expect(await auth.accessToken(), isNull);
      expect((await _snapshot(store.databaseName, 'records')).keys, isEmpty);
      await Future.wait(
        List.generate(
          12,
          (index) => store.write('jentra.employee.test.sequence', '$index'),
        ),
      );
      expect(await store.read('jentra.employee.test.sequence'), '11');
    },
  );

  test(
    'IndexedDB capability failure blocks auth and never falls back to memory',
    () async {
      final store = WebEmployeeKeyValueStore(projectUrl: _project());
      addTearDown(store.close);
      final nativeOpen = _idb.getProperty<JSFunction>('open'.toJS);
      JSAny? failOpen(String name, int version) {
        throw StateError('Synthetic IndexedDB unavailable');
      }

      _idb.setProperty('open'.toJS, failOpen.toJS);
      try {
        await expectLater(
          store.write('jentra.employee.auth.session.v1', 'synthetic-session'),
          _failure('STORAGE_UNAVAILABLE'),
        );
      } finally {
        _idb.setProperty('open'.toJS, nativeOpen);
      }
      await expectLater(
        store.read('jentra.employee.auth.session.v1'),
        _failure('STORAGE_UNAVAILABLE'),
      );
    },
  );

  test('loss of durable browser storage blocks command dispatch', () async {
    final store = WebEmployeeKeyValueStore(projectUrl: _project());
    final gateway = FixtureGateway();
    final controller = EmployeeController(
      gateway: gateway,
      draftStore: EmployeeDraftStore(store),
    );
    addTearDown(controller.dispose);
    addTearDown(gateway.close);
    addTearDown(() => _cleanup(store));
    await controller.start();
    expect(controller.phase, EmployeePhase.ready);
    final upgraded = await _open(store.databaseName, version: 2);
    upgraded.close();
    await controller.acknowledgeReview(controller.reviews.single);
    expect(gateway.receipts, isEmpty);
    expect(controller.error?.code, 'STORAGE_UNAVAILABLE');
    controller.lock();
  });

  test(
    'backend project namespaces cannot restore another project session',
    () async {
      final a = WebEmployeeKeyValueStore(projectUrl: _project());
      final b = WebEmployeeKeyValueStore(projectUrl: _project());
      addTearDown(() => _cleanup(a));
      addTearDown(() => _cleanup(b));
      await a.write('jentra.employee.auth.session.v1', 'project-a-session');
      expect(await b.read('jentra.employee.auth.session.v1'), isNull);
    },
  );
}

typedef _Snapshot = ({List<JSString> keys, List<JSAny?> values});

Future<_Snapshot> _snapshot(String name, String store) async {
  final db = await _open(name);
  try {
    final tx = db.transaction([store.toJS].toJS, 'readonly');
    final done = _done(tx);
    final values = tx.objectStore(store).getAll();
    final keys = tx.objectStore(store).getAllKeys();
    JSArray<JSAny?>? result;
    JSArray<JSString>? ids;
    _on(values, 'success', () => result = values.result as JSArray<JSAny?>);
    _on(keys, 'success', () => ids = keys.result as JSArray<JSString>);
    await done;
    return (keys: ids!.toDart.toList(), values: result!.toDart.toList());
  } finally {
    db.close();
  }
}

Future<void> _rawWrite(
  String name,
  String store,
  JSString key,
  JSAny value,
) async {
  final db = await _open(name);
  try {
    final tx = db.transaction([store.toJS].toJS, 'readwrite');
    final done = _done(tx);
    tx.objectStore(store).put(value, key);
    await done;
  } finally {
    db.close();
  }
}

Future<void> _rawDelete(String name, String store, JSString key) async {
  final db = await _open(name);
  try {
    final tx = db.transaction([store.toJS].toJS, 'readwrite');
    final done = _done(tx);
    tx.objectStore(store).delete(key);
    await done;
  } finally {
    db.close();
  }
}

Future<_Db> _open(String name, {int? version}) async {
  final result = await _request(
    version == null ? _idb.open(name) : _idb.open(name, version),
  );
  return _Db(result as JSObject);
}

Future<JSAny?> _request(_Req request) {
  final completed = Completer<JSAny?>();
  _on(request, 'success', () => completed.complete(request.result));
  _on(
    request,
    'error',
    () =>
        completed.completeError(StateError('Synthetic raw IDB helper failed')),
  );
  return completed.future;
}

Future<void> _done(_Tx transaction) {
  final completed = Completer<void>();
  void fail() {
    if (!completed.isCompleted) {
      completed.completeError(StateError('Raw transaction failed'));
    }
  }

  _on(transaction, 'complete', completed.complete);
  _on(transaction, 'error', fail);
  _on(transaction, 'abort', fail);
  return completed.future;
}

void _on(_Events target, String name, void Function() callback) =>
    target.addEventListener(name, ((JSAny? _) => callback()).toJS);

@JS('indexedDB')
external _Idb get _idb;
@JS('crypto.subtle')
external _Subtle get _subtle;
@JS('Object.keys')
external JSArray<JSString> _keys(JSObject object);

extension type _Events(JSObject _) implements JSObject {
  external void addEventListener(String name, JSFunction callback);
}

extension type _Idb(JSObject _) implements JSObject {
  external _Req open(String name, [int version]);
  external _Req deleteDatabase(String name);
}

extension type _Req(JSObject _) implements _Events {
  external JSAny? get result;
}

extension type _Db(JSObject _) implements JSObject {
  external _Tx transaction(JSArray<JSString> stores, String mode);
  external void close();
}

extension type _Tx(JSObject _) implements _Events {
  external _Store objectStore(String name);
}

extension type _Store(JSObject _) implements JSObject {
  external _Req getAll();
  external _Req getAllKeys();
  external _Req put(JSAny value, JSAny key);
  external _Req delete(JSAny key);
}

extension type _Subtle(JSObject _) implements JSObject {
  external JSPromise<JSArrayBuffer> exportKey(String format, JSObject key);
}
