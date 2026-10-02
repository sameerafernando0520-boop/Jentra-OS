import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show CouldNotRollBackException, DriftWrappedException;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

final class _Keys implements SecretKeyStore {
  final values = <String, String>{};
  String? fail;

  @override
  Future<String?> read(String key) async {
    if (fail == 'read') throw StateError('private credential diagnostic token');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (fail == 'write')
      throw StateError('private credential diagnostic token');
    values[key] = value;
  }
}

void main() {
  late JentraLocalDatabase db;
  late _Keys keys;
  late EncryptedDraftRepository drafts;

  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    keys = _Keys();
    drafts = EncryptedDraftRepository(db, DraftCipher(keyStore: keys));
  });
  tearDown(() => db.close());

  Future<void> save(
    EncryptedDraftRepository store,
    Map<String, Object?> input,
  ) => store.save(
    id: 'input',
    tenantId: 'tenant',
    entityType: 'procurement.requisition',
    payload: input,
    localVersion: 7,
    serverVersion: 4,
  );

  Matcher failure(String kind) => isA<DomainError>()
      .having((e) => e.code, 'required code', 'LOCAL_STORAGE_FULL')
      .having((e) => e.retryable, 'retryable', isTrue)
      .having((e) => e.fieldDetails, 'safe kind', {'storage': kind})
      .having((e) => e.message, 'visible code', contains('LOCAL_STORAGE_FULL'))
      .having(
        (e) => e.message,
        'retain editor',
        contains('Keep this editor open'),
      )
      .having(
        (e) => jsonEncode(e.toJson()),
        'redaction',
        isNot(contains('private credential diagnostic token')),
      );

  for (final stage in ['read', 'write']) {
    test(
      'EC-340 credential $stage failure is redacted and retryable',
      () async {
        keys.fail = stage;
        const input = {'quantity': '9007199254.740993', 'notes': 'local edits'};
        await expectLater(save(drafts, input), throwsA(failure('unavailable')));
        expect(input['quantity'], '9007199254.740993');
        expect(await db.select(db.encryptedDrafts).get(), isEmpty);
        expect(keys.values, isEmpty);
        keys.fail = null;
        await save(drafts, input);
        expect((await drafts.find('input'))!.payload, input);
      },
    );
  }

  test('EC-340 actual SQLite FULL preserves the last durable draft', () async {
    const original = {
      'quantity': '9007199254.740993',
      'notes': 'durable input',
    };
    await save(drafts, original);
    final pages = (await db.customSelect('PRAGMA page_count').getSingle())
        .read<int>('page_count');
    await db.customStatement('PRAGMA max_page_count=$pages');
    final edited = {...original, 'notes': 'x' * 500000};
    await expectLater(save(drafts, edited), throwsA(failure('full')));
    expect(edited['notes'], hasLength(500000));
    expect((await drafts.find('input'))!.payload, original);
    await db.customStatement('PRAGMA max_page_count=10000');
    await save(drafts, edited);
    expect((await drafts.find('input'))!.payload, edited);
  });

  test(
    'EC-340 failed local acknowledgement restores original sealed state',
    () async {
      const original = {
        'command_id': 'original-command',
        'quantity': '9007199254.740993',
        'state': 'pending',
      };
      await save(drafts, original);
      final failingKeys = _Keys()..fail = 'read';
      final failing = EncryptedDraftRepository(
        db,
        DraftCipher(keyStore: failingKeys),
      );
      await expectLater(
        failing.transaction(() async {
          await failing.delete('input');
          await save(failing, {
            'state': 'confirmed',
            'command_id': 'original-command',
          });
        }),
        throwsA(failure('unavailable')),
      );
      expect((await drafts.find('input'))!.payload, original);
      expect((await drafts.find('input'))!.serverVersion, 4);
    },
  );

  test('invalid caller JSON is not classified as a storage failure', () async {
    await expectLater(
      save(drafts, {'invalid': Object()}),
      throwsA(isA<JsonUnsupportedObjectError>()),
    );
    expect(keys.values, isEmpty);
  });

  test(
    'transaction preserves the original domain conflict and local state',
    () async {
      const original = {'state': 'pending', 'command_id': 'original-command'};
      await save(drafts, original);
      const conflict = DomainError(
        code: 'VERSION_CONFLICT',
        message: 'review version',
      );
      await expectLater(
        drafts.transaction(() async {
          await drafts.delete('input');
          throw conflict;
        }),
        throwsA(same(conflict)),
      );
      expect((await drafts.find('input'))!.payload, original);
    },
  );

  for (final code in Platform.isWindows ? [112, 39, 28] : [28, 39, 112]) {
    test('structured OS storage error $code omits native diagnostics', () {
      final expected = Platform.isWindows
          ? code == 112 || code == 39
          : code == 28;
      final raw = FileSystemException(
        'private credential diagnostic token',
        'private/object/path',
        OSError('private native message', code),
      );
      expect(localDraftStorageFailure(raw), failure(expected ? 'full' : 'unavailable'));
      expect(jsonEncode(localDraftStorageFailure(raw).toJson()),
          isNot(contains('private/object/path')));
    });
  }

  test('structured SQLite FULL omits SQL, parameters and diagnostic text', () {
    final raw = SqliteException(
      extendedResultCode: 13,
      message: 'private credential diagnostic token',
      causingStatement: 'private SQL text',
      parametersToStatement: ['private source payload'],
    );
    final safe = localDraftStorageFailure(raw);
    expect(safe, failure('full'));
    expect(jsonEncode(safe.toJson()), isNot(contains('private SQL text')));
    expect(jsonEncode(safe.toJson()), isNot(contains('private source payload')));
  });

  test('Drift wrapper retains structured FULL without wrapper text', () {
    expect(
      localDraftStorageFailure(DriftWrappedException(
        message: 'private credential diagnostic token',
        cause: SqliteException(extendedResultCode: 13, message: 'private SQL text'),
      )),
      failure('full'),
    );
  });

  test('automatic rollback wrapper reports FULL without confirmation', () {
    expect(
      localDraftStorageFailure(CouldNotRollBackException(
        SqliteException(extendedResultCode: 13, message: 'private source payload'),
        StackTrace.current,
        StateError('private credential diagnostic token'),
      )),
      failure('full'),
    );
  });

  test('storage classifier preserves distinct domain rejection', () {
    for (final code in ['VERSION_CONFLICT', 'DRAFT_SCOPE_MISMATCH', 'COMMAND_PENDING']) {
      final original = DomainError(code: code, message: 'Existing safe error');
      expect(localDraftStorageFailure(original), same(original));
      expect(isLocalDraftStorageFailure(original), isFalse);
    }
    expect(isLocalDraftStorageFailure(localDraftStorageFailure(StateError('closed'))), isTrue);
  });
}
