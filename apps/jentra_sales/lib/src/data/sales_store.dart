import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models.dart';

abstract interface class SalesKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

final class NativeSalesKeyValueStore implements SalesKeyValueStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: false,
      migrateWithBackup: false,
      storageNamespace: 'jentra_sales_secure',
      preferencesKeyPrefix: 'jentra.sales.',
    ),
    iOptions: IOSOptions(
      accountName: 'jentra.sales.secure',
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
    ),
  );
  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } on Object {
      throw _failure;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on Object {
      throw _failure;
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } on Object {
      throw _failure;
    }
  }

  static const _failure = SalesFailure(
    'STORAGE_UNAVAILABLE',
    'Protected storage is unavailable. Unlock this device and try again.',
  );
}

/// Tests inject this store. Production factories never select it.
final class MemorySalesStore implements SalesKeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
