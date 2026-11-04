import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_workspace_admin.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_workspace_admin_platform.dart';
import 'package:jentra_platform/src/browser_protected_store.dart';
import 'package:jentra_platform/src/platform_draft_keys_web.dart';

// Shared by the browser unit suite and the compiled, locally served probe.
// Only synthetic scopes are used; no authentication or backend calls occur.
final browserStorageScenarios = <({String name, Future<void> Function() run})>[
  (
    name: 'WR-03 protected key is non-extractable and survives reopen',
    run: _key,
  ),
  (name: 'WR-04 competing lease cannot replace pending recovery', run: _lease),
  (name: 'WR-03 missing key never resets encrypted recovery', run: _missing),
  (
    name: 'WR-03 SQLite restart restores the exact command envelope',
    run: _sqlite,
  ),
];
int _sequence = 0;
String _project() =>
    'https://os-browser-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}.example.test';
void _check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<JSAny?> _request(web.IDBRequest request) {
  final result = Completer<JSAny?>();
  request.onsuccess = ((web.Event _) => result.complete(request.result)).toJS;
  request.onerror = ((web.Event _) => result.completeError(
    StateError('Synthetic IndexedDB request failed'),
  )).toJS;
  return result.future;
}

Future<web.IDBDatabase> _database(String name) async =>
    (await _request(web.window.indexedDB.open(name))) as web.IDBDatabase;
Future<void> _cleanup(ProtectedBrowserKeyValueStore store) async {
  await store.close();
  await _request(web.window.indexedDB.deleteDatabase(store.databaseName));
}

Future<void> _failure(Future<Object?> Function() operation, String code) async {
  try {
    await operation();
  } on BrowserStorageFailure catch (error) {
    _check(error.code == code, 'Expected $code, received ${error.code}');
    return;
  }
  throw StateError('Expected protected storage failure $code');
}

Future<void> _key() async {
  final first = ProtectedBrowserKeyValueStore(projectUrl: _project());
  final different = ProtectedBrowserKeyValueStore(projectUrl: _project());
  _check(
    first.databaseName != different.databaseName,
    'Project namespaces must differ',
  );
  const key = 'jentra.desktop.test.synthetic-key';
  const secret = 'synthetic-private-key-material';
  final second = ProtectedBrowserKeyValueStore(projectUrl: first.projectOrigin);
  try {
    await first.write(key, secret);
    final db = await _database(first.databaseName);
    try {
      final metadata =
          (await _request(
                db
                    .transaction('keys'.toJS, 'readonly')
                    .objectStore('keys')
                    .get('primary'.toJS),
              ))
              as JSObject;
      final cryptoKey = metadata.getProperty('key'.toJS) as web.CryptoKey;
      _check(!cryptoKey.extractable, 'Browser key must be non-extractable');
      bool exported = false;
      try {
        await web.window.crypto.subtle.exportKey('raw', cryptoKey).toDart;
        exported = true;
      } on Object {
        /* Expected browser rejection. */
      }
      _check(!exported, 'Raw key export must fail');
      final records =
          (await _request(
                db
                    .transaction('records'.toJS, 'readonly')
                    .objectStore('records')
                    .getAll(),
              ))
              as JSArray;
      final record = records.toDart.single as JSObject;
      final bytes =
          (record.getProperty('ciphertext'.toJS) as JSArrayBuffer).toDart;
      _check(
        !utf8
            .decode(bytes.asUint8List(), allowMalformed: true)
            .contains(secret),
        'Stored record must be encrypted',
      );
    } finally {
      db.close();
    }
    await first.close();
    _check(
      await second.read(key) == secret,
      'Reopening must restore the exact protected key',
    );
  } finally {
    await first.close();
    await _cleanup(second);
  }
}

Future<void> _lease() async {
  final first = ProtectedBrowserKeyValueStore(projectUrl: _project());
  final competing = ProtectedBrowserKeyValueStore(
    projectUrl: first.projectOrigin,
  );
  try {
    await first.write('jentra.desktop.test.pending', 'original-intent');
    await _failure(
      () => competing.write('jentra.desktop.test.pending', 'replacement'),
      'BROWSER_STORAGE_IN_USE',
    );
    _check(
      await first.read('jentra.desktop.test.pending') == 'original-intent',
      'A competing lease must preserve original recovery',
    );
  } finally {
    await competing.close();
    await _cleanup(first);
  }
}

Future<void> _missing() async {
  final first = ProtectedBrowserKeyValueStore(projectUrl: _project());
  final second = ProtectedBrowserKeyValueStore(projectUrl: first.projectOrigin);
  try {
    await first.write('jentra.desktop.test.pending', 'original-intent');
    final db = await _database(first.databaseName);
    final transaction = db.transaction('keys'.toJS, 'readwrite');
    final committed = Completer<void>();
    transaction.oncomplete = ((web.Event _) => committed.complete()).toJS;
    transaction.onabort = ((web.Event _) => committed.completeError(
      StateError('Fixture key removal aborted'),
    )).toJS;
    transaction.objectStore('keys').delete('primary'.toJS);
    await committed.future;
    db.close();
    await first.close();
    await _failure(
      () => second.read('jentra.desktop.test.pending'),
      'STORAGE_UNAVAILABLE',
    );
    final inspected = await _database(second.databaseName);
    try {
      final count =
          (await _request(
                inspected
                    .transaction('records'.toJS, 'readonly')
                    .objectStore('records')
                    .count(),
              ))
              as JSNumber;
      _check(
        count.toDartInt == 1,
        'Encrypted records must survive a missing key',
      );
    } finally {
      inspected.close();
    }
  } finally {
    await first.close();
    await _cleanup(second);
  }
}

Future<void> _sqlite() async {
  const scope = TenantContext(
    tenantId: '10000000-0000-0000-0000-000000000001',
    actorId: '10000000-0000-0000-0000-000000000002',
  );
  final project = _project();
  var keys = ProtectedBrowserKeyValueStore(projectUrl: project);
  var database = JentraLocalDatabase.open();
  EncryptedWorkspaceAdminRecovery recovery() => EncryptedWorkspaceAdminRecovery(
    EncryptedDraftRepository(
      database,
      DraftCipher(keyStore: BrowserDraftKeyStore(keys)),
    ),
  );
  final original = WorkspaceAdminPending(
    WorkspaceAdminAction.createEntity,
    CommandEnvelope(
      commandId: '10000000-0000-0000-0000-000000000003',
      idempotencyKey: '10000000-0000-0000-0000-000000000004',
      context: scope,
      payload: {
        'name': 'Synthetic browser company',
        'code': 'BC',
        'currency_code': 'LKR',
        'timezone': 'Asia/Colombo',
      },
    ),
  );
  try {
    await recovery().seal(original);
    final row = (await database.select(database.encryptedDrafts).get()).single;
    _check(
      !utf8
          .decode(row.encryptedPayload, allowMalformed: true)
          .contains('Synthetic browser company'),
      'SQLite draft must be encrypted',
    );
    await database.close();
    await keys.close();
    keys = ProtectedBrowserKeyValueStore(projectUrl: project);
    database = JentraLocalDatabase.open();
    final restored = await recovery().load(scope);
    _check(
      restored != null &&
          workspaceAdminCanonical(restored.json) ==
              workspaceAdminCanonical(original.json),
      'Restart must preserve the exact immutable command',
    );
    await recovery().complete(scope, original.command.commandId);
    _check(
      await recovery().load(scope) == null,
      'Confirmed command must be removed',
    );
  } finally {
    await database.close();
    await _cleanup(keys);
  }
}
