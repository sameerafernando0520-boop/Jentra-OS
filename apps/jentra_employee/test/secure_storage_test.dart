import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:jentra_employee/src/data/employee_gateway.dart';
import 'package:jentra_employee/src/data/employee_storage.dart';

import 'employee_gateway_test.dart' show person, ws, actor, employee, record;

class MemoryStore implements EmployeeKeyValueStore {
  final values = <String, String>{};
  bool fail = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (fail) throw StateError('native secret failure');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'draft expires at 24 hours and cannot restore under another employee',
    () async {
      var now = DateTime.utc(2026, 10, 9);
      final memory = MemoryStore();
      final store = EmployeeDraftStore(memory, now: () => now);
      final draft = EmployeeLeaveDraft(
        leaveType: 'Annual',
        reason: 'Family',
        startDate: DateTime(2026, 10, 12),
        endDate: DateTime(2026, 10, 13),
      );
      await store.saveDraft(person, draft);
      expect((await store.loadDraft(person))?.reason, 'Family');
      const other = EmployeeIdentity(
        workspace: ws,
        actorId: actor,
        employeeId: record,
        displayName: 'Other',
      );
      expect(await store.loadDraft(other), isNull);
      now = now.add(const Duration(hours: 24));
      expect(await store.loadDraft(person), isNull);
    },
  );
  test(
    'pending command freezes caller request and persists exact identity',
    () async {
      final store = EmployeeDraftStore(MemoryStore());
      final pending = EmployeePendingCommand.create(
        workspace: ws,
        actorId: actor,
        employeeId: employee,
        action: 'link_accept',
        targetId: record,
        expectedVersion: 1,
        now: DateTime.utc(2026, 10, 9),
      );
      await store.savePending(pending);
      final restored = await store.loadPending(ws, actor);
      expect(restored!.envelope.commandId, pending.envelope.commandId);
      expect(restored.envelope.idempotencyKey, pending.envelope.idempotencyKey);
      expect(await store.loadPending(ws, record), isNull);
    },
  );
  test('auth and PKCE use separate secure app namespaces', () async {
    final memory = MemoryStore();
    final auth = EmployeeAuthStorage(memory);
    final pkce = EmployeePkceStorage(memory);
    await auth.initialize();
    await auth.persistSession('encrypted-by-native');
    await pkce.setItem(key: 'verifier', value: 'pkce');
    expect(await auth.accessToken(), 'encrypted-by-native');
    expect(await pkce.getItem(key: 'verifier'), 'pkce');
    expect(
      memory.values.keys.every((k) => k.startsWith('jentra.employee.')),
      isTrue,
    );
    await auth.removePersistedSession();
    expect(await auth.hasAccessToken(), isFalse);
    expect(await pkce.getItem(key: 'verifier'), 'pkce');
  });
  test('native storage uses device-bound authenticated storage and no reset fallback', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final calls = <MethodCall>[];
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    try {
      await NativeEmployeeKeyValueStore().write(
        'jentra.employee.test',
        'secret',
      );
      final options = (calls.single.arguments as Map)['options'] as Map;
      expect(options['resetOnError'], 'false');
      expect(options['migrateWithBackup'], 'false');
      expect(options['storageNamespace'], 'jentra_employee_secure');
      expect(options['storageCipherAlgorithm'], 'AES_GCM_NoPadding');
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await NativeEmployeeKeyValueStore().write(
        'jentra.employee.test',
        'secret',
      );
      final ios = (calls.last.arguments as Map)['options'] as Map;
      expect(ios['accessibility'], 'unlocked_this_device');
      expect(ios['synchronizable'], 'false');
    } finally {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });
  test(
    'cross-identity injected payload and future lease are discarded',
    () async {
      final now = DateTime.utc(2026, 10, 9);
      final memory = MemoryStore();
      final store = EmployeeDraftStore(memory, now: () => now);
      await store.saveDraft(
        person,
        EmployeeLeaveDraft(
          leaveType: 'Annual',
          reason: 'Family',
          startDate: now,
          endDate: now,
        ),
      );
      final key = memory.values.keys.singleWhere(
        (key) => key.contains('.draft.'),
      );
      memory.values[key] = memory.values[key]!.replaceFirst(
        person.key,
        '${ws.key}/$actor/$record',
      );
      expect(await store.loadDraft(person), isNull);
      expect(memory.values.keys.any((key) => key.contains('.draft.')), isFalse);
    },
  );
  test('actor-wide cleanup removes drafts in every workspace but retains pending recovery', () async {
    final memory = MemoryStore();
    final store = EmployeeDraftStore(memory);
    final draft = EmployeeLeaveDraft(
      leaveType: 'Annual',
      reason: 'Family',
      startDate: DateTime(2026, 10, 12),
      endDate: DateTime(2026, 10, 13),
    );
    await store.saveDraft(person, draft);
    final second = EmployeeIdentity(
      workspace: EmployeeWorkspace(
        tenantId: record,
        legalEntityId: ws.legalEntityId,
        branchId: ws.branchId,
        tenantName: 'Second',
        entityName: 'Entity',
        branchName: 'Branch',
        timeZone: 'Asia/Colombo',
      ),
      actorId: actor,
      employeeId: employee,
      displayName: 'Employee',
    );
    await store.saveDraft(second, draft);
    final pending = EmployeePendingCommand.create(
      workspace: ws,
      actorId: actor,
      employeeId: employee,
      action: 'link_accept',
      targetId: record,
      expectedVersion: 1,
      now: DateTime.utc(2026, 10, 9),
    );
    await store.savePending(pending);
    await store.clearActorDrafts(actor);
    expect(await store.loadDraft(person), isNull);
    expect(await store.loadDraft(second), isNull);
    expect(
      (await store.loadPending(ws, actor))!.envelope.commandId,
      pending.envelope.commandId,
    );
  });
}
