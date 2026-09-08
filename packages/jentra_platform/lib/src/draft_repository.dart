import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:jentra_domain/jentra_domain.dart';

import 'draft_cipher.dart';
import 'local_database.dart';

final class LocalDraft {
  const LocalDraft({
    required this.id,
    required this.tenantId,
    required this.entityType,
    required this.payload,
    required this.localVersion,
    required this.serverVersion,
    required this.syncState,
    required this.updatedAt,
    this.lastErrorCode,
  });

  final String id;
  final String tenantId;
  final String entityType;
  final Map<String, Object?> payload;
  final int localVersion;
  final int? serverVersion;
  final DraftSyncState syncState;
  final DateTime updatedAt;
  final String? lastErrorCode;
}

final class EncryptedDraftRepository {
  EncryptedDraftRepository(this._database, this._cipher);

  final JentraLocalDatabase _database;
  final DraftCipher _cipher;

  Future<void> save({
    required String id,
    required String tenantId,
    required String entityType,
    required Map<String, Object?> payload,
    required int localVersion,
    int? serverVersion,
    DraftSyncState syncState = DraftSyncState.localOnly,
  }) async {
    final encrypted = await _cipher.encrypt(jsonEncode(payload));
    await _database
        .into(_database.encryptedDrafts)
        .insertOnConflictUpdate(
          EncryptedDraftsCompanion.insert(
            id: id,
            tenantId: tenantId,
            entityType: entityType,
            encryptedPayload: Uint8List.fromList(encrypted),
            localVersion: Value(localVersion),
            serverVersion: Value(serverVersion),
            syncState: syncState.name,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
  }

  Stream<List<LocalDraft>> watchTenant(String tenantId) =>
      (_database.select(_database.encryptedDrafts)
            ..where((row) => row.tenantId.equals(tenantId))
            ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
          .watch()
          .asyncMap((rows) => Future.wait(rows.map(_decode)));

  Future<LocalDraft?> find(String id) async {
    final row = await (_database.select(
      _database.encryptedDrafts,
    )..where((item) => item.id.equals(id))).getSingleOrNull();
    return row == null ? null : _decode(row);
  }

  /// Bounded metadata page. Callers can verify scope before decrypting a row.
  Future<List<String>> pageIds({
    required String tenantId,
    required String entityType,
    String? afterId,
    int limit = 100,
  }) async {
    if (limit < 1 || limit > 200) {
      throw RangeError.range(limit, 1, 200, 'limit');
    }
    final query = _database.selectOnly(_database.encryptedDrafts)
      ..addColumns([_database.encryptedDrafts.id])
      ..where(
        _database.encryptedDrafts.tenantId.equals(tenantId) &
            _database.encryptedDrafts.entityType.equals(entityType),
      );
    if (afterId != null) {
      query.where(_database.encryptedDrafts.id.isBiggerThanValue(afterId));
    }
    query
      ..orderBy([OrderingTerm.asc(_database.encryptedDrafts.id)])
      ..limit(limit);
    return (await query.get())
        .map((row) => row.read(_database.encryptedDrafts.id)!)
        .toList();
  }

  Future<void> markConflict({required String id, required int serverVersion}) =>
      (_database.update(
        _database.encryptedDrafts,
      )..where((item) => item.id.equals(id))).write(
        EncryptedDraftsCompanion(
          serverVersion: Value(serverVersion),
          syncState: Value(DraftSyncState.conflicted.name),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

  Future<void> delete(String id) => (_database.delete(
    _database.encryptedDrafts,
  )..where((item) => item.id.equals(id))).go();

  Future<LocalDraft> _decode(EncryptedDraft row) async {
    final cleartext = await _cipher.decrypt(row.encryptedPayload);
    return LocalDraft(
      id: row.id,
      tenantId: row.tenantId,
      entityType: row.entityType,
      payload: (jsonDecode(cleartext) as Map).cast<String, Object?>(),
      localVersion: row.localVersion,
      serverVersion: row.serverVersion,
      syncState: DraftSyncState.values.byName(row.syncState),
      updatedAt: row.updatedAt.toUtc(),
      lastErrorCode: row.lastErrorCode,
    );
  }
}
