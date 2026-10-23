import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'employee_gateway.dart';
import 'employee_storage.dart';

abstract interface class EmployeePushTransport {
  Stream<String> get registrations;
  Stream<void> get updates;
  Future<bool> permission({required bool request});
  Future<void> register();
  Future<void> unregister();
}

/// FCM only carries a generic update; payloads never choose private routes.
final class AndroidEmployeePushTransport implements EmployeePushTransport {
  AndroidEmployeePushTransport(this.messaging);
  final FirebaseMessaging messaging;
  static Future<AndroidEmployeePushTransport?> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    await Firebase.initializeApp();
    return AndroidEmployeePushTransport(FirebaseMessaging.instance);
  }

  @override
  Stream<String> get registrations => messaging.onRegistered;
  bool _isUpdate(RemoteMessage message) =>
      message.data['kind'] == 'employee_update' &&
      RegExp(
        r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
      ).hasMatch(message.data['event_id'] ?? '');
  @override
  Stream<void> get updates => Stream.multi((sink) {
    final foreground = FirebaseMessaging.onMessage.listen((m) {
      if (_isUpdate(m)) sink.add(null);
    });
    final opened = FirebaseMessaging.onMessageOpenedApp.listen((m) {
      if (_isUpdate(m)) sink.add(null);
    });
    messaging
        .getInitialMessage()
        .then((m) {
          if (m != null && _isUpdate(m)) sink.add(null);
        })
        .catchError((Object _) {});
    sink.onCancel = () async {
      await foreground.cancel();
      await opened.cancel();
    };
  });
  @override
  Future<bool> permission({required bool request}) async {
    final settings = request
        ? await messaging.requestPermission(
            alert: true,
            badge: false,
            sound: true,
          )
        : await messaging.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized;
  }

  @override
  Future<void> register() => messaging.register();
  @override
  Future<void> unregister() async {
    await messaging.setAutoInitEnabled(false);
    await messaging.unregister();
  }
}

abstract interface class EmployeePushRepository {
  Future<EmployeePushReceipt> register(
    EmployeeIdentity person,
    String installation,
    String target,
    String command,
  );
  Future<bool> remove(String installation, String command);
}

final class EmployeePushReceipt {
  const EmployeePushReceipt({required this.version, required this.expiresAt});
  final int version;
  final DateTime expiresAt;

  factory EmployeePushReceipt.fromWire(Object? result, String installation) {
    if (result is Map &&
        result['installation_id'] == installation &&
        result['status'] == 'active' &&
        result['version'] is int &&
        (result['version'] as int) > 0 &&
        result['expires_at'] is String) {
      final expiry = DateTime.tryParse(result['expires_at'] as String);
      if (expiry != null && expiry.isUtc) {
        return EmployeePushReceipt(
          version: result['version'] as int,
          expiresAt: expiry,
        );
      }
    }
    throw const EmployeeFailure(
      'INVALID_RESPONSE',
      'Notification registration could not be verified.',
    );
  }
}

final class SupabaseEmployeePushRepository implements EmployeePushRepository {
  SupabaseEmployeePushRepository(this.client);
  final SupabaseClient client;
  String? get _sessionId {
    final token = client.auth.currentSession?.accessToken;
    if (token == null) return null;
    try {
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
      );
      return claims is Map && claims['session_id'] is String
          ? claims['session_id'] as String
          : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<EmployeePushReceipt> register(
    EmployeeIdentity person,
    String installation,
    String target,
    String command,
  ) async {
    final session = _sessionId;
    if (session == null || client.auth.currentUser?.id != person.actorId) {
      throw const EmployeeFailure(
        'SESSION_CHANGED',
        'Sign in again before enabling notifications.',
      );
    }
    final scope = person.workspace;
    final result = await client
        .schema('api')
        .rpc(
          'employee_push_register',
          params: {
            'p_tenant_id': scope.tenantId,
            'p_legal_entity_id': scope.legalEntityId,
            'p_branch_id': scope.branchId,
            'p_installation_id': installation,
            'p_token': target,
            'p_platform': 'android',
            'p_command_id': command,
          },
        );
    if (_sessionId != session ||
        client.auth.currentUser?.id != person.actorId) {
      throw const EmployeeFailure(
        'INVALID_RESPONSE',
        'Notification registration could not be verified.',
      );
    }
    return EmployeePushReceipt.fromWire(result, installation);
  }

  @override
  Future<bool> remove(String installation, String command) async {
    final actor = client.auth.currentUser?.id;
    final session = _sessionId;
    if (actor == null || session == null) {
      throw const EmployeeFailure('AUTHENTICATION_REQUIRED', 'Sign in again.');
    }
    final result = await client
        .schema('api')
        .rpc(
          'employee_push_remove',
          params: {'p_installation_id': installation, 'p_command_id': command},
        );
    if (_sessionId != session ||
        client.auth.currentUser?.id != actor ||
        result is! Map ||
        result['installation_id'] != installation ||
        result['status'] != 'removed') {
      throw const EmployeeFailure(
        'INVALID_RESPONSE',
        'Notification removal could not be verified.',
      );
    }
    // A foreign/expired session receives an idempotent no-op, not removal proof.
    return result['removed'] == true;
  }
}

/// Serialized registration/removal keeps a late SDK or RPC completion from
/// enrolling a new employee under an earlier employee's permission intent.
final class EmployeePushCoordinator extends ChangeNotifier {
  EmployeePushCoordinator({
    required this.transport,
    required this.repository,
    required this.store,
    required this.currentIdentity,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _registrations = transport.registrations.listen(
      _registered,
      onError: (Object _) {
        error = true;
        _notify();
      },
    );
    _updates = transport.updates.listen((_) {
      if (currentIdentity() != null) {
        updateAvailable = true;
        _notify();
      }
    });
  }
  final EmployeePushTransport transport;
  final EmployeePushRepository repository;
  final EmployeeKeyValueStore store;
  final EmployeeIdentity? Function() currentIdentity;
  final DateTime Function() _now;
  static const _key = 'jentra.employee.push.binding.v1';
  final _uuid = const Uuid();
  late final StreamSubscription<String> _registrations;
  late final StreamSubscription<void> _updates;
  Future<void> _tail = Future.value();
  Completer<String>? _target;
  String? _latestTarget;
  int _generation = 0;
  bool _disposed = false;
  bool busy = false, enabled = false, error = false, updateAvailable = false;
  String? _owner;
  DateTime? _renewedAt, _lastAttempt;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _owns(EmployeeIdentity person, int generation) =>
      !_disposed &&
      generation == _generation &&
      currentIdentity()?.key == person.key;
  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _registered(String target) {
    if (target.isEmpty ||
        target.length > 4096 ||
        RegExp(r'\s').hasMatch(target)) {
      return;
    }
    final pending = _target;
    if (pending != null) {
      _latestTarget = target;
      if (!pending.isCompleted) pending.complete(target);
      return;
    }
    final person = currentIdentity();
    final generation = _generation;
    if (enabled && person != null && person.key == _owner) {
      unawaited(
        _serialize(() => _saveTarget(person, target, generation))
            .catchError((Object _) {
              error = true;
              _notify();
            }),
      );
    }
  }

  Future<Map<String, dynamic>?> _binding() async {
    final wire = await store.read(_key);
    if (wire == null) return null;
    final data = jsonDecode(wire);
    if (data is! Map<String, dynamic> ||
        data['schema'] != 1 ||
        data['owner'] is! String ||
        data['installation'] is! String ||
        !RegExp(
          r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
        ).hasMatch(data['installation'] as String)) {
      throw const EmployeeFailure(
        'STORAGE_UNAVAILABLE',
        'Notification ownership could not be verified.',
      );
    }
    return data;
  }

  Future<void> _saveTarget(
    EmployeeIdentity person,
    String target,
    int generation,
  ) async {
    if (!_owns(person, generation)) return;
    final previous = await _binding();
    if (!_owns(person, generation)) return;
    if (previous != null && previous['owner'] != person.key) {
      throw const EmployeeFailure(
        'SESSION_CHANGED',
        'Turn off the previous employee notification registration first.',
      );
    }
    final id = previous?['installation'] as String? ?? _uuid.v4();
    final pendingAt = DateTime.tryParse(
      previous?['pending_at'] as String? ?? '',
    );
    final reuseCommand =
        previous?['pending_target'] == target &&
        previous?['pending_command'] is String &&
        (pendingAt == null ||
            _now().difference(pendingAt) < const Duration(hours: 23));
    var command = reuseCommand
        ? previous!['pending_command'] as String
        : _uuid.v4();
    var binding = {
      'schema': 1,
      'owner': person.key,
      'installation': id,
      'pending_command': command,
      'pending_target': target,
      'pending_at': ((reuseCommand ? pendingAt : null) ?? _now())
          .toUtc()
          .toIso8601String(),
    };
    for (var attempt = 0; attempt < 2; attempt++) {
      // Persist intent before sending; retry can remove an uncertain register.
      final wire = jsonEncode(binding);
      await store.write(_key, wire);
      if (await store.read(_key) != wire) {
        throw const EmployeeFailure(
          'STORAGE_UNAVAILABLE',
          'Notification recovery could not be saved.',
        );
      }
      if (!_owns(person, generation)) return;
      final receipt = await repository.register(person, id, target, command);
      if (!_owns(person, generation)) return;
      if (receipt.version > 0 && receipt.expiresAt.isAfter(_now().toUtc())) {
        break;
      }
      if (attempt == 1) {
        throw const EmployeeFailure(
          'INVALID_RESPONSE',
          'Notification registration has expired. Retry to renew it.',
        );
      }
      // A replay can return an expired original ACK. Renew with a fresh command.
      command = _uuid.v4();
      binding = {
        ...binding,
        'pending_command': command,
        'pending_at': _now().toUtc().toIso8601String(),
      };
    }
    if (!_owns(person, generation)) return;
    final committed = jsonEncode({
      'schema': 1,
      'owner': person.key,
      'installation': id,
    });
    await store.write(_key, committed);
    if (await store.read(_key) != committed) {
      throw const EmployeeFailure(
        'STORAGE_UNAVAILABLE',
        'Notification ownership could not be saved.',
      );
    }
    if (!_owns(person, generation)) return;
    _owner = person.key;
    enabled = true;
    error = false;
    _renewedAt = _now();
    _notify();
  }

  Future<void> enable({bool requestPermission = true}) => _serialize(() async {
    final person = currentIdentity();
    if (person == null || _disposed) return;
    final generation = _generation;
    busy = true;
    error = false;
    _lastAttempt = _now();
    _notify();
    try {
      if (!await transport.permission(request: requestPermission) ||
          !_owns(person, generation)) {
        error = true;
        return;
      }
      final target = Completer<String>();
      _target = target;
      _latestTarget = null;
      await transport.register();
      var value = await target.future.timeout(const Duration(seconds: 20));
      while (_owns(person, generation)) {
        await _saveTarget(person, value, generation);
        if (_latestTarget == null || _latestTarget == value) break;
        value = _latestTarget!;
      }
    } on Object {
      error = true;
    } finally {
      _target = null;
      _latestTarget = null;
      busy = false;
      _notify();
    }
  });
  Future<void> reconcile() async {
    final person = currentIdentity();
    if (person == null || _disposed || busy) return;
    if (_owner == person.key &&
        _renewedAt != null &&
        _now().difference(_renewedAt!) < const Duration(hours: 6)) {
      return;
    }
    if (_lastAttempt != null &&
        _now().difference(_lastAttempt!) < const Duration(minutes: 5)) {
      return;
    }
    _lastAttempt = _now();
    try {
      final binding = await _binding();
      if (currentIdentity()?.key != person.key ||
          binding?['owner'] != person.key) {
        return;
      }
      await enable(requestPermission: false);
    } on Object {
      error = true;
      _notify();
    }
  }

  Future<void> disconnect() {
    _generation++;
    enabled = false;
    updateAvailable = false;
    _owner = null;
    _renewedAt = null;
    return _serialize(() async {
      busy = true;
      _notify();
      try {
        final binding = await _binding();
        if (binding == null) {
          // Storage eviction must not leave a previously registered SDK target on.
          // With no local binding there is no server ownership claim to discard.
          try {
            await transport.unregister();
          } on Object {
            /* No server-bound registration is acknowledged by this instance. */
          }
          return;
        }
        bool removed = false, stopped = false;
        try {
          removed = await repository.remove(
            binding['installation'] as String,
            _uuid.v4(),
          );
        } on Object {
          /* SDK unregister can independently invalidate this target. */
        }
        try {
          await transport.unregister();
          stopped = true;
        } on Object {
          /* Confirmed server removal also prevents future delivery. */
        }
        if (!removed && !stopped) {
          throw const EmployeeFailure(
            'PUSH_DISCONNECT_INCOMPLETE',
            'Notifications could not be disconnected. Reconnect and retry sign-out.',
          );
        }
        await store.delete(_key);
        if (await store.read(_key) != null) {
          throw const EmployeeFailure(
            'STORAGE_UNAVAILABLE',
            'Notification ownership removal could not be verified.',
          );
        }
        error = false;
      } finally {
        busy = false;
        _notify();
      }
    });
  }

  void clearUpdate() {
    updateAvailable = false;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_registrations.cancel());
    unawaited(_updates.cancel());
    super.dispose();
  }
}
