import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_employee/src/data/employee_gateway.dart';
import 'package:jentra_employee/src/data/employee_push.dart';

import 'employee_gateway_test.dart' show person;
import 'secure_storage_test.dart' show MemoryStore;

class Transport implements EmployeePushTransport {
  final targets = StreamController<String>.broadcast(sync: true);
  final notices = StreamController<void>.broadcast(sync: true);
  bool allowed = true, stopFails = false;
  int permissions = 0, starts = 0, stops = 0;
  Completer<bool>? permissionGate;
  @override
  Stream<String> get registrations => targets.stream;
  @override
  Stream<void> get updates => notices.stream;
  @override
  Future<bool> permission({required bool request}) async {
    permissions++;
    return permissionGate == null ? allowed : permissionGate!.future;
  }

  @override
  Future<void> register() async {
    starts++;
    targets.add('synthetic-firebase-installation');
  }

  @override
  Future<void> unregister() async {
    stops++;
    if (stopFails) throw StateError('unavailable');
  }

  Future<void> close() async {
    await targets.close();
    await notices.close();
  }
}

class Repository implements EmployeePushRepository {
  final commands = <String>[];
  final targets = <String>[];
  final events = <String>[];
  bool registerFails = false, removeFails = false, removeConfirmed = true;
  final receipts = <EmployeePushReceipt>[];
  Completer<void>? registerGate;
  @override
  Future<EmployeePushReceipt> register(
    EmployeeIdentity person,
    String installation,
    String target,
    String command,
  ) async {
    commands.add(command);
    targets.add(target);
    events.add('register');
    await registerGate?.future;
    if (registerFails) throw StateError('uncertain');
    events.add('registered');
    return receipts.isEmpty
        ? EmployeePushReceipt(
            version: 1,
            expiresAt: DateTime.now().toUtc().add(const Duration(hours: 24)),
          )
        : receipts.removeAt(0);
  }

  @override
  Future<bool> remove(String installation, String command) async {
    events.add('remove');
    if (removeFails) throw StateError('unavailable');
    return removeConfirmed;
  }
}

void main() {
  late Transport transport;
  late Repository repository;
  late MemoryStore store;
  late EmployeePushCoordinator push;
  EmployeeIdentity? current;
  setUp(() {
    transport = Transport();
    repository = Repository();
    store = MemoryStore();
    current = person;
    push = EmployeePushCoordinator(
      transport: transport,
      repository: repository,
      store: store,
      currentIdentity: () => current,
    );
  });
  tearDown(() async {
    push.dispose();
    await transport.close();
  });
  test(
    'requires a currently accepted employee before permission or registration',
    () async {
      current = null;
      await push.enable();
      expect(transport.permissions, 0);
      expect(repository.commands, isEmpty);
    },
  );
  test(
    'denied permission never registers or sends a device identifier',
    () async {
      transport.allowed = false;
      await push.enable();
      expect(push.enabled, isFalse);
      expect(push.error, isTrue);
      expect(transport.starts, 0);
      expect(repository.commands, isEmpty);
    },
  );
  test(
    'registers only after permission and verified backend completion',
    () async {
      await push.enable();
      expect(push.enabled, isTrue);
      expect(push.error, isFalse);
      expect(repository.events, ['register', 'registered']);
    },
  );
  test(
    'a permission dialog cannot transfer intent to another identity',
    () async {
      transport.permissionGate = Completer<bool>();
      final enabled = push.enable();
      await Future<void>.delayed(Duration.zero);
      current = null;
      transport.permissionGate!.complete(true);
      await enabled;
      expect(repository.commands, isEmpty);
      expect(transport.starts, 0);
    },
  );
  test(
    'uncertain registration retries the original command identity',
    () async {
      repository.registerFails = true;
      await push.enable();
      expect(push.error, isTrue);
      expect(push.enabled, isFalse);
      repository.registerFails = false;
      await push.enable();
      expect(repository.commands, hasLength(2));
      expect(repository.commands[0], repository.commands[1]);
      expect(push.enabled, isTrue);
    },
  );
  test('removal follows an already dispatched uncertain register', () async {
    repository.registerGate = Completer<void>();
    final enabled = push.enable();
    while (repository.commands.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    final removed = push.disconnect();
    current = null;
    repository.registerGate!.complete();
    await enabled;
    await removed;
    expect(repository.events, ['register', 'registered', 'remove']);
    expect(push.enabled, isFalse);
    expect(transport.stops, 1);
  });
  test(
    'confirmed SDK unregister independently removes a revoked backend binding',
    () async {
      await push.enable();
      repository.removeFails = true;
      await push.disconnect();
      expect(push.enabled, isFalse);
      expect(transport.stops, 1);
      expect(await store.read('jentra.employee.push.binding.v1'), isNull);
    },
  );
  test(
    'confirmed server removal is safe when device unregister is unavailable',
    () async {
      await push.enable();
      transport.stopFails = true;
      await push.disconnect();
      expect(await store.read('jentra.employee.push.binding.v1'), isNull);
    },
  );
  test('both removal failures retain recovery and fail closed', () async {
    await push.enable();
    transport.stopFails = true;
    repository.removeFails = true;
    await expectLater(push.disconnect(), throwsA(isA<EmployeeFailure>()));
    expect(await store.read('jentra.employee.push.binding.v1'), isNotNull);
  });
  test('a foreign-session no-op is not proof of removal', () async {
    await push.enable();
    repository.removeConfirmed = false;
    transport.stopFails = true;
    await expectLater(push.disconnect(), throwsA(isA<EmployeeFailure>()));
    expect(await store.read('jentra.employee.push.binding.v1'), isNotNull);
  });
  test(
    'missing recovery still attempts to invalidate the local SDK target',
    () async {
      await push.enable();
      await store.delete('jentra.employee.push.binding.v1');
      await push.disconnect();
      expect(transport.stops, 1);
      expect(push.enabled, isFalse);
    },
  );
  test(
    'FID refreshed during initial RPC is saved after the first response',
    () async {
      repository.registerGate = Completer<void>();
      final enabling = push.enable();
      while (repository.commands.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      transport.targets.add('newest-synthetic-installation');
      repository.registerGate!.complete();
      await enabling;
      expect(repository.targets, [
        'synthetic-firebase-installation',
        'newest-synthetic-installation',
      ]);
      expect(repository.commands.toSet(), hasLength(2));
      expect(push.enabled, isTrue);
    },
  );
  test(
    'an expired replay is renewed with a new command before enabling',
    () async {
      repository.registerFails = true;
      await push.enable();
      final original = repository.commands.single;
      repository.registerFails = false;
      repository.receipts.add(
        EmployeePushReceipt(
          version: 1,
          expiresAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
        ),
      );
      await push.enable();
      expect(repository.commands[1], original);
      expect(repository.commands[2], isNot(original));
      expect(push.enabled, isTrue);
    },
  );
  test(
    'an old pending intent renews instead of replaying an expired command',
    () async {
      repository.registerFails = true;
      await push.enable();
      final binding = jsonDecode(
        (await store.read('jentra.employee.push.binding.v1'))!,
      ) as Map<String, dynamic>;
      binding['pending_at'] = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 2))
          .toIso8601String();
      await store.write('jentra.employee.push.binding.v1', jsonEncode(binding));
      repository.registerFails = false;
      await push.enable();
      expect(repository.commands[1], isNot(repository.commands[0]));
      expect(push.enabled, isTrue);
    },
  );
  test(
    'repeated expired acknowledgements cannot enable notifications',
    () async {
      final old = EmployeePushReceipt(
        version: 1,
        expiresAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      );
      repository.receipts.addAll([old, old]);
      await push.enable();
      expect(push.enabled, isFalse);
      expect(push.error, isTrue);
      expect(await store.read('jentra.employee.push.binding.v1'), isNotNull);
    },
  );
  test(
    'receipt rejects missing expiry, invalid version and another installation',
    () {
      final wire = {
        'installation_id': 'test-id',
        'status': 'active',
        'version': 1,
        'expires_at': '2026-10-24T00:00:00Z',
      };
      expect(EmployeePushReceipt.fromWire(wire, 'test-id').version, 1);
      for (final invalid in [
        {...wire, 'expires_at': null},
        {...wire, 'version': 0},
        {...wire, 'installation_id': 'different-id'},
      ]) {
        expect(
          () => EmployeePushReceipt.fromWire(invalid, 'test-id'),
          throwsA(isA<EmployeeFailure>()),
        );
      }
    },
  );
  test(
    'a late registration event cannot re-enable a disconnected employee',
    () async {
      await push.enable();
      await push.disconnect();
      transport.targets.add('new-synthetic-installation');
      await Future<void>.delayed(Duration.zero);
      expect(repository.commands, hasLength(1));
      expect(push.enabled, isFalse);
    },
  );
  test(
    'background or locked identities receive no private update presentation',
    () async {
      await push.enable();
      current = null;
      transport.notices.add(null);
      expect(push.updateAvailable, isFalse);
      current = person;
      transport.notices.add(null);
      expect(push.updateAvailable, isTrue);
    },
  );
  test(
    'restored registrations renew without requesting permission again',
    () async {
      await push.enable();
      push.dispose();
      push = EmployeePushCoordinator(
        transport: transport,
        repository: repository,
        store: store,
        currentIdentity: () => current,
      );
      await push.reconcile();
      expect(push.enabled, isTrue);
      expect(repository.commands, hasLength(2));
    },
  );
}
