import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_platform/jentra_people_platform.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'support/wave4_gateway_harness.dart';

class _Keys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

ScopedCommandDraftStore _store(JentraLocalDatabase db, _Keys keys) =>
    ScopedCommandDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: keys)),
      entityType: 'people.organization',
      fields: organizationPayloadFields,
      validate: validateOrganizationPayload,
      definiteFailures: {'VERSION_CONFLICT', 'VALIDATION_ERROR'},
    );
Map<String, Object?> payload() => {
  'id': w4Id,
  'revision_id': w4Revision,
  'code': 'OPS',
  'name': 'Synthetic private-safe operations',
  'parent_id': null,
  'start_date': '2026-09-26',
  'end_date_exclusive': null,
  'reason': 'Synthetic setup',
};
void main() {
  test(
    'AC-419 a queued preparation snapshots caller-owned JSON before awaiting',
    () async {
      final db = JentraLocalDatabase(NativeDatabase.memory());
      final drafts = _store(db, _Keys());
      try {
        final input = payload();
        final pending = drafts.prepare(
          w4Scope,
          w4Id,
          'department_create',
          input,
          0,
        );
        input['name'] = 'A later unsaved edit';
        input['salary'] = 'Forbidden addition';
        final sealed = await pending;
        expect(sealed.envelope.payload['name'], payload()['name']);
        expect(sealed.envelope.payload.containsKey('salary'), isFalse);
      } finally {
        await db.close();
      }
    },
  );
  test(
    'AC-419 organization request survives encrypted database restart exactly',
    () async {
      final scratch = await Directory.systemTemp.createTemp(
        'jentra-w4-organization-',
      );
      final file = File('${scratch.path}/drafts.sqlite');
      final keys = _Keys();
      var db = JentraLocalDatabase(NativeDatabase(file));
      try {
        var drafts = _store(db, keys);
        await drafts.save(w4Scope, w4Id, 'department_create', payload(), 0);
        final pending = await drafts.prepare(
          w4Scope,
          w4Id,
          'department_create',
          payload(),
          0,
        );
        final wire = pending.toJson();
        await db.close();
        expect(
          String.fromCharCodes(
            file.readAsBytesSync(),
          ).contains('Synthetic private-safe operations'),
          isFalse,
        );
        db = JentraLocalDatabase(NativeDatabase(file));
        drafts = _store(db, keys);
        expect((await drafts.load(w4Scope, w4Id))!.pending!.toJson(), wire);
        expect(
          (await drafts.prepare(
            w4Scope,
            w4Id,
            'department_create',
            payload(),
            0,
          )).toJson(),
          wire,
        );
        await expectLater(
          drafts.prepare(w4Scope, w4Id, 'department_create', {
            ...payload(),
            'name': 'Changed',
          }, 0),
          throwsA(
            isA<DomainError>().having((e) => e.code, 'code', 'COMMAND_PENDING'),
          ),
        );
        await expectLater(
          drafts.discard(w4Scope, w4Id),
          throwsA(
            isA<DomainError>().having((e) => e.code, 'code', 'COMMAND_PENDING'),
          ),
        );
        await drafts.recordFailure(
          w4Scope,
          w4Id,
          pending.envelope.commandId,
          const DomainError(code: 'PERMISSION_DENIED', message: 'Revoked'),
        );
        expect((await drafts.load(w4Scope, w4Id))!.pending!.toJson(), wire);
        await drafts.complete(w4Scope, w4Id, pending.envelope.commandId);
        expect(await drafts.load(w4Scope, w4Id), isNull);
      } finally {
        await db.close();
        await scratch.delete(recursive: true);
      }
    },
  );
  test(
    'AC-401 recovery metadata checks actor and aggregate before decryption',
    () async {
      final db = JentraLocalDatabase(NativeDatabase.memory());
      final keys = _Keys();
      final drafts = _store(db, keys);
      try {
        await drafts.save(w4Scope, w4Id, 'department_create', payload(), 0);
        final other = TenantContext(
          tenantId: w4Scope.tenantId,
          legalEntityId: w4Scope.legalEntityId,
          branchId: w4Scope.branchId,
          actorId: w4Revision,
        );
        expect((await drafts.page(other)).items, isEmpty);
        expect(await drafts.load(other, w4Id), isNull);
        expect(await drafts.load(w4Scope, w4Revision), isNull);
        expect((await drafts.page(w4Scope)).items.single.aggregateId, w4Id);
        await expectLater(
          drafts.save(w4Scope, w4Id, 'department_create', {
            ...payload(),
            'salary': '10',
          }, 0),
          throwsFormatException,
        );
      } finally {
        await db.close();
      }
    },
  );
  test(
    'AC-419 competing local prepares seal one request and conflicts require replacement',
    () async {
      final db = JentraLocalDatabase(NativeDatabase.memory());
      final drafts = _store(db, _Keys());
      try {
        final commands = await Future.wait([
          drafts.prepare(w4Scope, w4Id, 'department_create', payload(), 0),
          drafts.prepare(w4Scope, w4Id, 'department_create', payload(), 0),
        ]);
        expect(commands[0].toJson(), commands[1].toJson());
        await drafts.recordFailure(
          w4Scope,
          w4Id,
          commands[0].envelope.commandId,
          const DomainError(code: 'VERSION_CONFLICT', message: 'Stale'),
        );
        expect((await drafts.load(w4Scope, w4Id))!.pending, isNull);
        await expectLater(
          drafts.prepare(w4Scope, w4Id, 'department_create', payload(), 0),
          throwsA(
            isA<DomainError>().having(
              (e) => e.code,
              'code',
              'VERSION_CONFLICT',
            ),
          ),
        );
        await drafts.save(
          w4Scope,
          w4Id,
          'department_create',
          payload(),
          0,
          resolveConflict: true,
        );
        final replacement = await drafts.prepare(
          w4Scope,
          w4Id,
          'department_create',
          payload(),
          0,
        );
        expect(
          replacement.envelope.idempotencyKey,
          isNot(commands[0].envelope.idempotencyKey),
        );
      } finally {
        await db.close();
      }
    },
  );
}
