import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'employee_gateway.dart';

abstract interface class EmployeeKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

final class NativeEmployeeKeyValueStore implements EmployeeKeyValueStore {
  NativeEmployeeKeyValueStore();
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: false,
      migrateWithBackup: false,
      storageNamespace: 'jentra_employee_secure',
      preferencesKeyPrefix: 'jentra.employee.',
    ),
    iOptions: IOSOptions(
      accountName: 'jentra.employee.secure',
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
    ),
  );
  void _requireNative() {
    if (kIsWeb ||
        !(defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      throw const EmployeeFailure(
        'STORAGE_UNAVAILABLE',
        'Secure employee storage requires Android or iPhone.',
      );
    }
  }

  @override
  Future<String?> read(String key) async {
    _requireNative();
    try {
      return await _storage.read(key: key);
    } on Object {
      throw _storageFailure;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    _requireNative();
    try {
      await _storage.write(key: key, value: value);
    } on Object {
      throw _storageFailure;
    }
  }

  @override
  Future<void> delete(String key) async {
    _requireNative();
    try {
      await _storage.delete(key: key);
    } on Object {
      throw _storageFailure;
    }
  }
}

const _storageFailure = EmployeeFailure(
  'STORAGE_UNAVAILABLE',
  'Secure storage is unavailable. Unlock your device and retry. Request recovery must remain available before dispatch.',
);

/// Internal store/controller lease; the UI receives only the bounded draft.
final class EmployeeDraftLease {
  const EmployeeDraftLease(this.draft, this.expiresAt);
  final EmployeeLeaveDraft draft;
  final DateTime expiresAt;
}

/// Sensitive draft bodies have a finite lease; pending requests contain only
/// command identifiers and retain their original identity until reconciled.
final class EmployeeDraftStore {
  EmployeeDraftStore(this.store, {DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final EmployeeKeyValueStore store;
  final DateTime Function() _now;
  Future<void> _tail = Future.value();
  static const _prefix = 'jentra.employee.v1';
  String _draftKey(EmployeeIdentity identity) =>
      '$_prefix.draft.${identity.key}';
  String _pendingKey(EmployeeWorkspace workspace, String actor) =>
      '$_prefix.pending.${workspace.key}/$actor';
  Future<T> _safe<T>(Future<T> Function() work) {
    final result = _tail.then((_) async {
      try {
        return await work();
      } on EmployeeFailure {
        rethrow;
      } on Object {
        throw _storageFailure;
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  String _ownerIndex(String actor) => '$_prefix.draft-index.$actor';
  bool _ownedDraftKey(String key, String actor) {
    const prefix = '$_prefix.draft.';
    if (!key.startsWith(prefix) || key.length > 300) return false;
    final parts = key.substring(prefix.length).split('/');
    final uuid = RegExp(
      r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
    );
    return parts.length == 5 && parts[3] == actor && parts.every(uuid.hasMatch);
  }

  Future<List<String>> _draftKeys(String actor) async {
    final wire = await store.read(_ownerIndex(actor));
    if (wire == null) return [];
    final json = jsonDecode(wire);
    if (json is! List ||
        json.length > 100 ||
        json.any((key) => key is! String || !_ownedDraftKey(key, actor))) {
      throw _storageFailure;
    }
    return json.cast<String>().toSet().toList();
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  DateTime _parseDate(Object? value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw const FormatException('Invalid date.');
    }
    final date = DateTime.parse(value);
    if (_date(date) != value) throw const FormatException('Invalid date.');
    return date;
  }

  Future<EmployeeDraftLease> saveDraft(
    EmployeeIdentity identity,
    EmployeeLeaveDraft draft,
  ) => _safe(() async {
    if (draft.validationError != null) {
      throw EmployeeFailure('VALIDATION_ERROR', draft.validationError!);
    }
    final created = _now().toUtc();
    final keys = await _draftKeys(identity.actorId);
    if (!keys.contains(_draftKey(identity))) keys.add(_draftKey(identity));
    if (keys.length > 100) throw _storageFailure;
    // Index first: interrupted writes remain eligible for actor-wide cleanup.
    await store.write(_ownerIndex(identity.actorId), jsonEncode(keys));
    await store.write(
      _draftKey(identity),
      jsonEncode({
        'schema': 1,
        'owner': identity.key,
        'saved_at': created.toIso8601String(),
        'expires_at': created.add(const Duration(hours: 24)).toIso8601String(),
        'leave_type': draft.leaveType,
        'reason': draft.reason,
        'start_date': _date(draft.startDate),
        'end_date': _date(draft.endDate),
      }),
    );
    return EmployeeDraftLease(draft, created.add(const Duration(hours: 24)));
  });
  Future<EmployeeLeaveDraft?> loadDraft(EmployeeIdentity identity) async =>
      (await loadDraftLease(identity))?.draft;
  Future<EmployeeDraftLease?> loadDraftLease(EmployeeIdentity identity) =>
      _safe(() async {
        final key = _draftKey(identity);
        final wire = await store.read(key);
        if (wire == null) return null;
        if (wire.length > 10000) {
          throw const FormatException('Oversized draft.');
        }
        try {
          final json = jsonDecode(wire) as Map<String, dynamic>;
          const fields = {
            'schema',
            'owner',
            'saved_at',
            'expires_at',
            'leave_type',
            'reason',
            'start_date',
            'end_date',
          };
          if (json.keys.toSet().difference(fields).isNotEmpty ||
              json.length != fields.length ||
              json['schema'] != 1 ||
              json['owner'] != identity.key) {
            throw const FormatException('Draft owner mismatch.');
          }
          final saved = DateTime.parse(json['saved_at'] as String).toUtc();
          final expires = DateTime.parse(json['expires_at'] as String).toUtc();
          final now = _now().toUtc();
          if (saved.isAfter(now) ||
              !expires.isAfter(now) ||
              expires.difference(saved) > const Duration(hours: 24) ||
              !expires.isAfter(saved)) {
            await store.delete(key);
            return null;
          }
          final draft = EmployeeLeaveDraft(
            leaveType: json['leave_type'] as String,
            reason: json['reason'] as String,
            startDate: _parseDate(json['start_date']),
            endDate: _parseDate(json['end_date']),
          );
          if (draft.validationError != null) {
            throw const FormatException('Invalid draft.');
          }
          return EmployeeDraftLease(draft, expires);
        } on FormatException {
          await store.delete(key);
          return null;
        } on TypeError {
          await store.delete(key);
          return null;
        }
      });
  Future<void> discardDraft(EmployeeIdentity identity) =>
      _safe(() => store.delete(_draftKey(identity)));
  Future<void> clearActorDrafts(String actor) => _safe(() async {
    final keys = await _draftKeys(actor);
    for (final key in keys) {
      await store.delete(key);
    }
    await store.delete(_ownerIndex(actor));
  });
  Future<void> savePending(EmployeePendingCommand pending) => _safe(() async {
    final c = pending.envelope.context;
    await store.write(
      '$_prefix.pending.${pending.ownerKey}',
      jsonEncode({
        'schema': 1,
        'owner': pending.ownerKey,
        'request': pending.toJson(),
      }),
    );
    // Read-after-write catches silent storage failures before dispatch.
    final wire = await store.read('$_prefix.pending.${pending.ownerKey}');
    if (wire == null) throw _storageFailure;
    final restored = EmployeePendingCommand.fromJson(
      (jsonDecode(wire) as Map)['request'].cast<String, Object?>(),
    );
    if (jsonEncode(restored.toJson()) != jsonEncode(pending.toJson()) ||
        c.actorId != restored.envelope.context.actorId) {
      throw _storageFailure;
    }
  });
  Future<EmployeePendingCommand?> loadPending(
    EmployeeWorkspace workspace,
    String actor,
  ) => _safe(() async {
    final wire = await store.read(_pendingKey(workspace, actor));
    if (wire == null) return null;
    if (wire.length > 10000) throw _storageFailure;
    final json = jsonDecode(wire) as Map;
    final owner = '${workspace.key}/$actor';
    if (json.length != 3 || json['schema'] != 1 || json['owner'] != owner) {
      throw _storageFailure;
    }
    final pending = EmployeePendingCommand.fromJson(
      (json['request'] as Map).cast<String, Object?>(),
    );
    if (pending.ownerKey != owner) throw _storageFailure;
    return pending;
  });
  Future<void> clearPending(EmployeeWorkspace workspace, String actor) =>
      _safe(() => store.delete(_pendingKey(workspace, actor)));
}

final class EmployeeAuthStorage extends LocalStorage {
  EmployeeAuthStorage(this.store);
  final EmployeeKeyValueStore store;
  static const _key = 'jentra.employee.auth.session.v1';
  Future<void> _tail = Future.value();
  bool _allowPersistence = true;
  int _epoch = 0;
  Future<T> _serialized<T>(Future<T> Function() work) {
    final result = _tail.then((_) async {
      try {
        return await work();
      } on Object {
        throw const EmployeeFailure(
          'DURABLE_LOGOUT_INCOMPLETE',
          'Protected account storage could not be verified. Keep the app locked and retry sign-out.',
        );
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void beginSignIn() {
    _epoch++;
    _allowPersistence = true;
  }

  void blockPersistenceForLogout() {
    _epoch++;
    _allowPersistence = false;
  }

  Future<void> clearForLogout() => removePersistedSession();
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => (await accessToken()) != null;
  @override
  Future<String?> accessToken() => _serialized(() => store.read(_key));
  @override
  Future<void> persistSession(String persistSessionString) {
    final epoch = _epoch;
    return _serialized(() async {
      if (!_allowPersistence || epoch != _epoch) return;
      await store.write(_key, persistSessionString);
    });
  }

  @override
  Future<void> removePersistedSession() {
    blockPersistenceForLogout();
    return _serialized(() async {
      await store.delete(_key);
      if (await store.read(_key) != null) {
        throw const EmployeeFailure(
          'DURABLE_LOGOUT_INCOMPLETE',
          'Protected session removal could not be verified.',
        );
      }
    });
  }
}

final class EmployeePkceStorage implements GotrueAsyncStorage {
  EmployeePkceStorage(this.store);
  final EmployeeKeyValueStore store;
  String _key(String key) => 'jentra.employee.auth.pkce.v1.$key';
  @override
  Future<String?> getItem({required String key}) => store.read(_key(key));
  @override
  Future<void> setItem({required String key, required String value}) =>
      store.write(_key(key), value);
  @override
  Future<void> removeItem({required String key}) => store.delete(_key(key));
}
