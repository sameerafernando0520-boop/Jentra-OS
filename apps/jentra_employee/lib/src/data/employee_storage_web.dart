@JS()
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'employee_gateway.dart';
import 'employee_storage.dart';

const _unavailable = EmployeeFailure(
  'STORAGE_UNAVAILABLE',
  'Encrypted browser storage is unavailable. Use a supported browser over HTTPS and retry. Saved requests must remain recoverable before dispatch.',
);
const _inUse = EmployeeFailure(
  'BROWSER_STORAGE_IN_USE',
  'The employee app is already open in another tab. Close that tab and reload this app.',
);

EmployeeKeyValueStore createEmployeeKeyValueStore({
  required String projectUrl,
}) => WebEmployeeKeyValueStore(projectUrl: projectUrl);

/// Browser-origin encryption, not an OS keystore or protection from origin JS.
///
/// A non-extractable AES key is structured-cloned into IndexedDB. Logical keys
/// are hashed, and authenticated data binds ciphertext to its origin, backend
/// project and complete logical key (including existing actor/scope ownership).
/// One context holds a Web Lock for the store lifetime: per-operation locks
/// would still allow two tabs to overwrite one another's sealed pending intent.
final class WebEmployeeKeyValueStore implements EmployeeKeyValueStore {
  WebEmployeeKeyValueStore({required String projectUrl})
    : projectOrigin = _projectOrigin(projectUrl);

  static const maxValueBytes = 256 * 1024;
  final String projectOrigin;
  String get databaseName =>
      'jentra_employee_encrypted_v1_${base64Url.encode(utf8.encode(projectOrigin)).replaceAll('=', '')}';
  Future<void>? _ready;
  Future<void> _tail = Future.value();
  _Database? _database;
  late _CryptoKey _key;
  late String _origin;
  Completer<JSAny?>? _release;
  Future<JSAny?>? _lease;
  bool _closed = false;
  bool _invalidated = false;

  static String _projectOrigin(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        value.length > 2048) {
      throw _unavailable;
    }
    return uri.origin;
  }

  void _validateKey(String key) {
    if (!key.startsWith('jentra.employee.') ||
        key.length > 1024 ||
        key.contains('\u0000')) {
      throw _unavailable;
    }
  }

  Future<T> _serial<T>(Future<T> Function() work) {
    if (_closed) return Future.error(_unavailable);
    final result = _tail.then((_) async {
      if (_closed || _invalidated) throw _unavailable;
      try {
        await (_ready ??= _initialize());
        if (_closed || _invalidated) throw _unavailable;
        return await work();
      } on EmployeeFailure {
        rethrow;
      } on Object {
        throw _unavailable;
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _initialize() async {
    try {
      if (!_secureContext || _indexedDB == null || _locks == null) {
        throw _unavailable;
      }
      _origin = _browserOrigin;
      if (_origin == 'null' || _origin.isEmpty) throw _unavailable;
      await _acquireLease();
      _database = await _openDatabase();
      // Generate outside an IDB transaction: crypto awaits would let it commit.
      final candidate = await _crypto.subtle
          .generateKey(
            _KeyParameters(name: 'AES-GCM', length: 256),
            false,
            ['encrypt'.toJS, 'decrypt'.toJS].toJS,
          )
          .toDart;
      _key = await _loadOrCreateKey(candidate);
      _validateCryptoKey(_key);
      final probe = await _encrypt('jentra.employee.storage.probe', 'probe');
      // Exercise the persisted structured clone before any session or recovery
      // record can be written, rather than relying only on an in-memory key.
      final persisted = await _get('keys', 'primary');
      if (persisted == null || !persisted.isA<JSObject>()) throw _unavailable;
      final metadata = _KeyRecord._(persisted as JSObject);
      if (_objectKeys(metadata).toDart.length != 2 || metadata.schema != 1) {
        throw _unavailable;
      }
      _validateCryptoKey(metadata.key);
      _key = metadata.key;
      if (await _decrypt('jentra.employee.storage.probe', probe) != 'probe') {
        throw _unavailable;
      }
    } on Object {
      _database?.close();
      _database = null;
      await _releaseLease();
      rethrow;
    }
  }

  Future<void> _acquireLease() async {
    final acquired = Completer<void>();
    _release = Completer<JSAny?>();
    _lease = _locks!
        .request(
          databaseName,
          _LockOptions(mode: 'exclusive', ifAvailable: true),
          ((JSAny? lock) {
            if (lock == null) {
              if (!acquired.isCompleted) acquired.completeError(_inUse);
              return null;
            }
            if (!acquired.isCompleted) acquired.complete();
            return _release!.future.toJS;
          }).toJS,
        )
        .toDart;
    unawaited(
      _lease!.then<void>(
        (_) {
          if (!acquired.isCompleted) acquired.completeError(_unavailable);
        },
        onError: (Object _, StackTrace _) {
          if (!acquired.isCompleted) acquired.completeError(_unavailable);
        },
      ),
    );
    await acquired.future.timeout(const Duration(seconds: 15));
  }

  Future<void> _releaseLease() async {
    if (_release != null && !_release!.isCompleted) _release!.complete(null);
    try {
      await _lease;
    } on Object {
      // Capability failures still fail initialization; releasing has no fallback.
    }
  }

  Future<_Database> _openDatabase() {
    final complete = Completer<_Database>();
    final request = _indexedDB!.open(databaseName, 1);
    final timeout = Timer(const Duration(seconds: 15), () {
      if (!complete.isCompleted) complete.completeError(_unavailable);
    });
    void fail() {
      timeout.cancel();
      if (!complete.isCompleted) complete.completeError(_unavailable);
    }

    _listen(request, 'blocked', fail);
    _listen(request, 'error', fail);
    _listen(request, 'upgradeneeded', () {
      if (complete.isCompleted) {
        request.transaction?.abort();
        return;
      }
      try {
        final database = _Database(request.result as JSObject);
        if (!database.objectStoreNames.contains('keys')) {
          database.createObjectStore('keys');
        }
        if (!database.objectStoreNames.contains('records')) {
          database.createObjectStore('records');
        }
      } on Object {
        request.transaction?.abort();
        fail();
      }
    });
    _listen(request, 'success', () {
      final database = _Database(request.result as JSObject);
      timeout.cancel();
      if (complete.isCompleted) {
        database.close();
        return;
      }
      _listen(database, 'versionchange', () {
        _invalidated = true;
        database.close();
      });
      complete.complete(database);
    });
    return complete.future;
  }

  Future<_CryptoKey> _loadOrCreateKey(_CryptoKey candidate) {
    final database = _database!;
    final transaction = database.transaction(
      ['keys'.toJS, 'records'.toJS].toJS,
      'readwrite',
      _TransactionOptions(durability: 'strict'),
    );
    final complete = Completer<_CryptoKey>();
    _CryptoKey? selected;
    var keyRead = false, countRead = false;
    JSAny? metadata;
    var count = 0;
    void fail() {
      if (!complete.isCompleted) complete.completeError(_unavailable);
    }

    void decide() {
      if (!keyRead || !countRead || complete.isCompleted) return;
      try {
        if (metadata == null) {
          // Never replace a missing key while encrypted recovery data exists.
          if (count != 0) throw _unavailable;
          _validateCryptoKey(candidate);
          selected = candidate;
          transaction
              .objectStore('keys')
              .put(_KeyRecord(schema: 1, key: candidate), 'primary'.toJS);
        } else {
          if (!metadata.isA<JSObject>()) throw _unavailable;
          final record = _KeyRecord._(metadata as JSObject);
          if (_objectKeys(record).toDart.length != 2 || record.schema != 1) {
            throw _unavailable;
          }
          selected = record.key;
          _validateCryptoKey(selected!);
        }
      } on Object {
        transaction.abort();
        fail();
      }
    }

    final keyRequest = transaction.objectStore('keys').get('primary'.toJS);
    final countRequest = transaction.objectStore('records').count();
    _listen(keyRequest, 'success', () {
      metadata = keyRequest.result;
      keyRead = true;
      decide();
    });
    _listen(countRequest, 'success', () {
      count = (countRequest.result as JSNumber).toDartInt;
      countRead = true;
      decide();
    });
    _listen(transaction, 'abort', fail);
    _listen(transaction, 'error', fail);
    _listen(transaction, 'complete', () {
      if (selected == null) {
        fail();
      } else if (!complete.isCompleted) {
        complete.complete(selected);
      }
    });
    return complete.future;
  }

  void _validateCryptoKey(_CryptoKey key) {
    final usages = key.usages.toDart.map((value) => value.toDart).toSet();
    if (key.extractable ||
        key.type != 'secret' ||
        key.algorithm.name != 'AES-GCM' ||
        key.algorithm.length != 256 ||
        usages.length != 2 ||
        !usages.containsAll(['encrypt', 'decrypt'])) {
      throw _unavailable;
    }
  }

  Uint8List _associatedData(String key) => Uint8List.fromList(
    utf8.encode(
      jsonEncode(['jentra.employee.encrypted.v1', _origin, projectOrigin, key]),
    ),
  );

  Future<String> _recordId(String key) async {
    final digest = await _crypto.subtle
        .digest('SHA-256'.toJS, _associatedData(key).toJS)
        .toDart;
    return Uint8List.view(digest.toDart)
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<_CipherRecord> _encrypt(String key, String value) async {
    final bytes = Uint8List.fromList(utf8.encode(value));
    if (bytes.length > maxValueBytes) throw _unavailable;
    final iv = _crypto.getRandomValues(Uint8List(12).toJS);
    final ciphertext = await _crypto.subtle
        .encrypt(
          _CipherParameters(
            name: 'AES-GCM',
            iv: iv,
            additionalData: _associatedData(key).toJS,
            tagLength: 128,
          ),
          _key,
          bytes.toJS,
        )
        .toDart;
    return _CipherRecord(schema: 1, iv: iv, ciphertext: ciphertext);
  }

  Future<String> _decrypt(String key, _CipherRecord record) async {
    if (_objectKeys(record).toDart.length != 3 ||
        record.schema != 1 ||
        record.iv.toDart.length != 12 ||
        record.ciphertext.toDart.lengthInBytes < 16 ||
        record.ciphertext.toDart.lengthInBytes > maxValueBytes + 16) {
      throw _unavailable;
    }
    final cleartext = await _crypto.subtle
        .decrypt(
          _CipherParameters(
            name: 'AES-GCM',
            iv: record.iv,
            additionalData: _associatedData(key).toJS,
            tagLength: 128,
          ),
          _key,
          record.ciphertext,
        )
        .toDart;
    return utf8.decode(Uint8List.view(cleartext.toDart), allowMalformed: false);
  }

  Future<JSAny?> _get(String store, String key) async {
    final transaction = _database!.transaction([store.toJS].toJS, 'readonly');
    final completed = _transactionComplete(transaction);
    final request = transaction.objectStore(store).get(key.toJS);
    JSAny? result;
    _listen(request, 'success', () => result = request.result);
    await completed;
    return result;
  }

  Future<void> _put(String recordId, _CipherRecord value) {
    final transaction = _database!.transaction(
      ['records'.toJS].toJS,
      'readwrite',
      _TransactionOptions(durability: 'strict'),
    );
    final completed = _transactionComplete(transaction);
    transaction.objectStore('records').put(value, recordId.toJS);
    return completed;
  }

  Future<void> _delete(String recordId) {
    final transaction = _database!.transaction(
      ['records'.toJS].toJS,
      'readwrite',
      _TransactionOptions(durability: 'strict'),
    );
    final completed = _transactionComplete(transaction);
    transaction.objectStore('records').delete(recordId.toJS);
    return completed;
  }

  @override
  Future<String?> read(String key) => _serial(() async {
    _validateKey(key);
    final value = await _get('records', await _recordId(key));
    if (value == null) return null;
    if (!value.isA<JSObject>()) throw _unavailable;
    return _decrypt(key, _CipherRecord._(value as JSObject));
  });

  @override
  Future<void> write(String key, String value) => _serial(() async {
    _validateKey(key);
    final recordId = await _recordId(key);
    await _put(recordId, await _encrypt(key, value));
    final stored = await _get('records', recordId);
    if (stored == null ||
        !stored.isA<JSObject>() ||
        await _decrypt(key, _CipherRecord._(stored as JSObject)) != value) {
      throw _unavailable;
    }
  });

  @override
  Future<void> delete(String key) => _serial(() async {
    _validateKey(key);
    final recordId = await _recordId(key);
    await _delete(recordId);
    if (await _get('records', recordId) != null) throw _unavailable;
  });

  /// Release after outstanding writes settle; never call merely on background.
  Future<void> close() async {
    _closed = true;
    await _tail;
    _database?.close();
    _database = null;
    await _releaseLease();
  }
}

void _listen(_EventTarget target, String event, void Function() action) {
  target.addEventListener(event, ((JSAny? _) => action()).toJS);
}

Future<void> _transactionComplete(_Transaction transaction) {
  final completed = Completer<void>();
  void fail() {
    if (!completed.isCompleted) completed.completeError(_unavailable);
  }

  _listen(transaction, 'abort', fail);
  _listen(transaction, 'error', fail);
  _listen(transaction, 'complete', () {
    if (!completed.isCompleted) completed.complete();
  });
  return completed.future;
}

@JS('isSecureContext')
external bool get _secureContext;
@JS('location.origin')
external String get _browserOrigin;
@JS('indexedDB')
external _Factory? get _indexedDB;
@JS('navigator.locks')
external _Locks? get _locks;
@JS('crypto')
external _Crypto get _crypto;
@JS('Object.keys')
external JSArray<JSString> _objectKeys(JSObject object);

extension type _EventTarget(JSObject _) implements JSObject {
  external void addEventListener(String type, JSFunction listener);
}

extension type _Factory(JSObject _) implements JSObject {
  external _OpenRequest open(String name, int version);
}

extension type _Request(JSObject _) implements _EventTarget {
  external JSAny? get result;
}

extension type _OpenRequest(JSObject _) implements _Request {
  external _Transaction? get transaction;
}

extension type _Database(JSObject _) implements _EventTarget {
  external _NameList get objectStoreNames;
  external _ObjectStore createObjectStore(String name);
  external _Transaction transaction(
    JSArray<JSString> stores,
    String mode, [
    _TransactionOptions options,
  ]);
  external void close();
}

extension type _NameList(JSObject _) implements JSObject {
  external bool contains(String name);
}

extension type _Transaction(JSObject _) implements _EventTarget {
  external _ObjectStore objectStore(String name);
  external void abort();
}

extension type _ObjectStore(JSObject _) implements JSObject {
  external _Request get(JSAny key);
  external _Request put(JSAny value, JSAny key);
  external _Request delete(JSAny key);
  external _Request count();
}

extension type _TransactionOptions._(JSObject _) implements JSObject {
  external factory _TransactionOptions({String durability});
}

extension type _Locks(JSObject _) implements JSObject {
  external JSPromise<JSAny?> request(
    String name,
    _LockOptions options,
    JSFunction callback,
  );
}

extension type _LockOptions._(JSObject _) implements JSObject {
  external factory _LockOptions({String mode, bool ifAvailable});
}

extension type _Crypto(JSObject _) implements JSObject {
  external _Subtle get subtle;
  external JSUint8Array getRandomValues(JSUint8Array array);
}

extension type _Subtle(JSObject _) implements JSObject {
  external JSPromise<_CryptoKey> generateKey(
    _KeyParameters algorithm,
    bool extractable,
    JSArray<JSString> usages,
  );
  external JSPromise<JSArrayBuffer> digest(
    JSString algorithm,
    JSUint8Array data,
  );
  external JSPromise<JSArrayBuffer> encrypt(
    _CipherParameters algorithm,
    _CryptoKey key,
    JSUint8Array data,
  );
  external JSPromise<JSArrayBuffer> decrypt(
    _CipherParameters algorithm,
    _CryptoKey key,
    JSArrayBuffer data,
  );
}

extension type _KeyParameters._(JSObject _) implements JSObject {
  external factory _KeyParameters({String name, int length});
}

extension type _CipherParameters._(JSObject _) implements JSObject {
  external factory _CipherParameters({
    String name,
    JSUint8Array iv,
    JSUint8Array additionalData,
    int tagLength,
  });
}

extension type _CryptoKey(JSObject _) implements JSObject {
  external bool get extractable;
  external String get type;
  external _KeyAlgorithm get algorithm;
  external JSArray<JSString> get usages;
}

extension type _KeyAlgorithm(JSObject _) implements JSObject {
  external String get name;
  external int get length;
}

extension type _KeyRecord._(JSObject _) implements JSObject {
  external factory _KeyRecord({int schema, _CryptoKey key});
  external int get schema;
  external _CryptoKey get key;
}

extension type _CipherRecord._(JSObject _) implements JSObject {
  external factory _CipherRecord({
    int schema,
    JSUint8Array iv,
    JSArrayBuffer ciphertext,
  });
  external int get schema;
  external JSUint8Array get iv;
  external JSArrayBuffer get ciphertext;
}
