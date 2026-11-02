import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_workspace_admin.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_workspace_admin_platform.dart';

class _Keys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

const scope = TenantContext(
  tenantId: '10000000-0000-0000-0000-000000000001',
  actorId: '10000000-0000-0000-0000-000000000002',
);
WorkspaceAdminPending request([String name = 'Private company name']) =>
    WorkspaceAdminPending(
      WorkspaceAdminAction.createEntity,
      CommandEnvelope(
        commandId: '10000000-0000-0000-0000-000000000003',
        idempotencyKey: '10000000-0000-0000-0000-000000000004',
        context: scope,
        clientTimestamp: DateTime.utc(2026, 10, 28),
        payload: {
          'name': name,
          'code': 'PC',
          'currency_code': 'LKR',
          'timezone': 'Asia/Colombo',
        },
      ),
    );
void main() {
  test(
    'CA-A7 encrypted pending request survives a real SQLite restart with exact identities',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'jentra-admin-recovery-',
      );
      final file = File('${directory.path}/recovery.sqlite'), keys = _Keys();
      var db = JentraLocalDatabase(NativeDatabase(file));
      var open = true;
      try {
        var store = EncryptedWorkspaceAdminRecovery(
          EncryptedDraftRepository(db, DraftCipher(keyStore: keys)),
        );
        final original = request();
        await store.seal(original);
        await db.close();
        open = false;
        final bytes = await file.readAsBytes();
        expect(
          String.fromCharCodes(bytes),
          isNot(contains('Private company name')),
        );
        db = JentraLocalDatabase(NativeDatabase(file));
        open = true;
        store = EncryptedWorkspaceAdminRecovery(
          EncryptedDraftRepository(db, DraftCipher(keyStore: keys)),
        );
        final loaded = await store.load(scope);
        expect(
          workspaceAdminCanonical(loaded!.json),
          workspaceAdminCanonical(original.json),
        );
        expect(
          await store.load(
            scope.copyWith(actorId: '10000000-0000-0000-0000-000000000009'),
          ),
          isNull,
        );
        await expectLater(
          store.complete(scope, 'wrong'),
          throwsFormatException,
        );
        expect(await store.load(scope), isNotNull);
        await store.complete(scope, original.command.commandId);
        expect(await store.load(scope), isNull);
      } finally {
        if (open) await db.close();
        final target = directory.absolute.resolveSymbolicLinksSync(),
            root = Directory.systemTemp.absolute.resolveSymbolicLinksSync();
        if (!target.startsWith(
          '$root${Platform.pathSeparator}jentra-admin-recovery-',
        )) {
          throw StateError('Unexpected cleanup target.');
        }
        await Directory(target).delete(recursive: true);
      }
    },
  );
  test(
    'CA-E6 concurrent changed envelopes cannot overwrite pending work',
    () async {
      final db = JentraLocalDatabase(NativeDatabase.memory());
      try {
        final store = EncryptedWorkspaceAdminRecovery(
          EncryptedDraftRepository(db, DraftCipher(keyStore: _Keys())),
        );
        final results = await Future.wait([
          store
              .seal(request())
              .then<Object>((v) => v, onError: (Object e) => e),
          store
              .seal(request('Changed company'))
              .then<Object>((v) => v, onError: (Object e) => e),
        ]);
        expect(results.whereType<WorkspaceAdminPending>().length, 1);
        expect(results.whereType<DomainError>().single.code, 'COMMAND_PENDING');
        expect(
          (await store.load(scope))!.command.payload['name'],
          'Private company name',
        );
      } finally {
        await db.close();
      }
    },
  );
}
