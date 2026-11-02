import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:web/web.dart' as web;

import 'runtime_config.dart';

const _unavailable = DomainError(
  code: 'LOCAL_STORAGE_FULL',
  message:
      'Protected browser storage is unavailable. Use HTTPS, allow persistent storage and reload. No local save was confirmed.',
  fieldDetails: {'storage': 'unavailable'},
  retryable: true,
);
Future<void>? _readyLease;
Future<JSAny?>? _heldLease;
final _hold = Completer<JSAny?>();

String browserDatabaseName([RuntimeConfig? configuration]) {
  final config = configuration ?? RuntimeConfig.fromEnvironment();
  final project = config.isSupabaseConfigured
      ? config.supabaseOrigin
      : 'preview';
  final encoded = utf8
      .encode(project)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return 'jentra_os_$encoded';
}

Future<void> _claimLease(String name) async {
  if (!web.window.isSecureContext) throw _unavailable;
  final claimed = Completer<void>();
  try {
    _heldLease = web.window.navigator.locks
        .request(
          '$name.recovery',
          web.LockOptions(mode: 'exclusive', ifAvailable: true),
          ((web.Lock? lock) {
            if (lock == null) {
              claimed.completeError(
                const DomainError(
                  code: 'LOCAL_STORAGE_FULL',
                  message:
                      'Jentra OS is open in another browser tab. Close that tab and reload before changing records.',
                  fieldDetails: {'storage': 'unavailable'},
                  retryable: true,
                ),
              );
              return Future<JSAny?>.value(null).toJS;
            }
            claimed.complete();
            // This origin/project lease lasts for the page lifetime. The browser
            // releases it automatically on page close, including process failure.
            return _hold.future.toJS;
          }).toJS,
        )
        .toDart;
    unawaited(
      _heldLease!.catchError((Object _) {
        if (!claimed.isCompleted) claimed.completeError(_unavailable);
        return null;
      }),
    );
    await claimed.future.timeout(const Duration(seconds: 15));
  } on DomainError {
    rethrow;
  } on Object {
    throw _unavailable;
  }
}

QueryExecutor openLocalDatabase() => DatabaseConnection.delayed(
  Future(() async {
    final name = browserDatabaseName();
    await (_readyLease ??= _claimLease(name));
    final result = await WasmDatabase.open(
      databaseName: name,
      sqlite3Uri: Uri.parse(
        web.document.baseURI,
      ).resolve('assets/packages/jentra_platform/assets/web/sqlite3.wasm'),
      driftWorkerUri: Uri.parse(
        web.document.baseURI,
      ).resolve('assets/packages/jentra_platform/assets/web/drift_worker.js'),
    );
    if ({
      WasmStorageImplementation.inMemory,
      WasmStorageImplementation.unsafeIndexedDb,
    }.contains(result.chosenImplementation)) {
      await result.resolvedExecutor.executor.close();
      throw _unavailable;
    }
    return result.resolvedExecutor;
  }),
);
