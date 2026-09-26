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
    'id': '20000000-0000-0000-0000-000000000001',
    'code': 'HQ',
    'name': 'Synthetic Calendar',
    'version_id': '30000000-0000-0000-0000-000000000001',
    'start_date': '2026-09-01',
    'end_date_exclusive': '2027-01-01',
    'timezone': 'Asia/Colombo',
    'weekly_intervals': <Object?>[],
    'date_overrides': <Object?>[],
    'reason': 'Synthetic calendar setup',
  };
  test(
    'AC-419 encrypted pending request survives SQLite restart exactly',
    () async {
      final scratch = await Directory.systemTemp.createTemp(
        'jentra-calendar-recovery-',
      );
      final file = File(
        '${scratch.path}${Platform.pathSeparator}calendar.sqlite',
      );
      final keys = _MemoryKeys();
      var database = JentraLocalDatabase(NativeDatabase(file));
      try {
        var store = CalendarDraftStore(
          EncryptedDraftRepository(database, DraftCipher(keyStore: keys)),
        );
        await store.save(scope, 'calendar-editor', payload, version: 0);
        final pending = await store.prepare(
          scope,
          'calendar-editor',
          action: 'create',
          payload: payload,
          version: 0,
        );
        final first = pending.envelope;
        await database.close();
        expect(
          String.fromCharCodes(
            file.readAsBytesSync(),
          ).contains('Synthetic Calendar'),
          isFalse,
        );

        database = JentraLocalDatabase(NativeDatabase(file));
        store = CalendarDraftStore(
          EncryptedDraftRepository(database, DraftCipher(keyStore: keys)),
        );
        final recovered = await store.load(scope, 'calendar-editor');
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
          'calendar-editor',
          action: 'create',
          payload: {...payload},
          version: 0,
        );
        expect(replay.envelope.commandId, first.commandId);
        await expectLater(
          store.prepare(
            scope,
            'calendar-editor',
            action: 'create',
            payload: {...payload, 'code': 'EMP-02'},
            version: 0,
          ),
          throwsA(isA<DomainError>()),
        );
        expect(await store.load(other, 'calendar-editor'), isNull);
        await store.recordFailure(
          scope,
          'calendar-editor',
          const DomainError(code: 'UNCERTAIN_RESULT', message: 'Unknown'),
          commandId: first.commandId,
        );
        expect(
          (await store.load(
            scope,
            'calendar-editor',
          ))!.pending!.envelope.commandId,
          first.commandId,
        );
        await store.complete(scope, 'calendar-editor', first.commandId);
        expect(await store.load(scope, 'calendar-editor'), isNull);
      } finally {
        await database.close();
        await scratch.delete(recursive: true);
      }
    },
  );
  test(
    'concurrent prepare seals one intent and isolates actor/entity/branch/tenant namespaces',
    () async {
      final database = JentraLocalDatabase(NativeDatabase.memory());
      final store = CalendarDraftStore(
        EncryptedDraftRepository(
          database,
          DraftCipher(keyStore: _MemoryKeys()),
        ),
      );
      try {
        await store.save(scope, 'calendar-editor', payload, version: 0);
        final prepared = await Future.wait([
          for (var i = 0; i < 2; i++)
            store.prepare(
              scope,
              'calendar-editor',
              action: 'create',
              payload: payload,
              version: 0,
            ),
        ]);
        expect(prepared.first.toJson(), prepared.last.toJson());
        for (final foreign in [
          other,
          const TenantContext(
            tenantId: 'other',
            actorId: 'a',
            legalEntityId: 'e',
            branchId: 'b',
          ),
          const TenantContext(
            tenantId: 't',
            actorId: 'a',
            legalEntityId: 'other',
            branchId: 'b',
          ),
          const TenantContext(
            tenantId: 't',
            actorId: 'a',
            legalEntityId: 'e',
            branchId: 'other',
          ),
        ]) {
          expect(await store.load(foreign, 'calendar-editor'), isNull);
        }
        final id = prepared.first.envelope.commandId;
        await store.recordFailure(
          scope,
          'calendar-editor',
          const DomainError(code: 'PERMISSION_DENIED', message: 'Revoked'),
          commandId: id,
        );
        expect(
          (await store.load(
            scope,
            'calendar-editor',
          ))!.pending!.envelope.commandId,
          id,
        );
        await expectLater(
          store.discard(scope, 'calendar-editor'),
          throwsA(isA<DomainError>()),
        );
        await expectLater(
          store.complete(scope, 'calendar-editor', 'different-command'),
          throwsA(isA<DomainError>()),
        );
        await store.complete(scope, 'calendar-editor', id);
      } finally {
        await database.close();
      }
    },
  );
}
