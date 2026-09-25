import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_people_platform.dart';
import 'package:jentra_platform/jentra_platform.dart';

final class _MemoryKeys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  const other = TenantContext(
    tenantId: 't',
    actorId: 'other',
    legalEntityId: 'e',
    branchId: 'b',
  );
  const payload = <String, Object?>{
    'id': 'employee',
    'code': 'EMP-01',
    'display_name': 'Synthetic Employee',
    'work_email': '',
    'start_date': '2026-09-20',
    'job_title': 'Engineer',
    'employment_type': 'permanent',
  };

  test(
    'AC-419 encrypted pending request survives SQLite restart exactly',
    () async {
      final scratch = await Directory.systemTemp.createTemp(
        'jentra-employee-recovery-',
      );
      final file = File(
        '${scratch.path}${Platform.pathSeparator}employee.sqlite',
      );
      final keys = _MemoryKeys();
      var database = JentraLocalDatabase(NativeDatabase(file));
      try {
        var store = EmployeeDraftStore(
          EncryptedDraftRepository(database, DraftCipher(keyStore: keys)),
        );
        await store.save(scope, 'employee-editor', payload, version: 0);
        final pending = await store.prepare(
          scope,
          'employee-editor',
          action: 'create',
          payload: payload,
          version: 0,
        );
        final first = pending.envelope;
        await database.close();
        expect(
          String.fromCharCodes(
            file.readAsBytesSync(),
          ).contains('Synthetic Employee'),
          isFalse,
        );

        database = JentraLocalDatabase(NativeDatabase(file));
        store = EmployeeDraftStore(
          EncryptedDraftRepository(database, DraftCipher(keyStore: keys)),
        );
        final recovered = await store.load(scope, 'employee-editor');
        expect(recovered!.pending!.envelope.commandId, first.commandId);
        expect(
          recovered.pending!.envelope.idempotencyKey,
          first.idempotencyKey,
        );
        expect(
          recovered.pending!.envelope.clientTimestamp,
          first.clientTimestamp,
        );
        expect(recovered.pending!.envelope.payload, payload);
        final replay = await store.prepare(
          scope,
          'employee-editor',
          action: 'create',
          payload: {...payload},
          version: 0,
        );
        expect(replay.envelope.commandId, first.commandId);
        await expectLater(
          store.prepare(
            scope,
            'employee-editor',
            action: 'create',
            payload: {...payload, 'code': 'EMP-02'},
            version: 0,
          ),
          throwsA(isA<DomainError>()),
        );
        expect(await store.load(other, 'employee-editor'), isNull);
        await store.recordFailure(
          scope,
          'employee-editor',
          const DomainError(code: 'UNCERTAIN_RESULT', message: 'Unknown'),
          commandId: first.commandId,
        );
        expect(
          (await store.load(
            scope,
            'employee-editor',
          ))!.pending!.envelope.commandId,
          first.commandId,
        );
        await store.complete(scope, 'employee-editor', first.commandId);
        expect(await store.load(scope, 'employee-editor'), isNull);
      } finally {
        await database.close();
        await scratch.delete(recursive: true);
      }
    },
  );
}
