import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:jentra_domain/jentra_domain.dart';

import 'draft_cipher.dart';
import 'local_database.dart';

/// Tenant-scoped encrypted reference cache. Cached data is never authoritative.
final class EncryptedReferenceCacheRepository {
  EncryptedReferenceCacheRepository(this._database, this._cipher);

  final JentraLocalDatabase _database;
  final DraftCipher _cipher;

  Future<void> replaceResource({
    required String tenantId,
    required BusinessSetupResource resource,
    required Iterable<SetupRecord> records,
  }) async {
    final entries = <ReferenceCacheEntriesCompanion>[];
    final cachedAt = DateTime.now().toUtc();
    for (final record in records) {
      if (record.tenantId.isNotEmpty && record.tenantId != tenantId) {
        throw const DomainError(
          code: 'CACHE_TENANT_MISMATCH',
          message: 'A reference record belongs to a different tenant.',
        );
      }
      final encrypted = await _cipher.encrypt(jsonEncode(record.toJson()));
      entries.add(
        ReferenceCacheEntriesCompanion.insert(
          tenantId: tenantId,
          resource: resource.name,
          recordId: record.id,
          legalEntityId: Value(record.legalEntityId),
          encryptedPayload: Uint8List.fromList(encrypted),
          serverVersion: record.version,
          cachedAt: cachedAt,
        ),
      );
    }

    await _database.transaction(() async {
      await (_database.delete(_database.referenceCacheEntries)..where(
            (row) =>
                row.tenantId.equals(tenantId) &
                row.resource.equals(resource.name),
          ))
          .go();
      if (entries.isNotEmpty) {
        await _database.batch((batch) {
          batch.insertAll(_database.referenceCacheEntries, entries);
        });
      }
    });
  }

  Future<List<SetupRecord>> readResource({
    required String tenantId,
    required BusinessSetupResource resource,
    String? legalEntityId,
  }) async {
    final query = _database.select(_database.referenceCacheEntries)
      ..where(
        (row) =>
            row.tenantId.equals(tenantId) & row.resource.equals(resource.name),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.recordId)]);
    if (legalEntityId != null) {
      query.where((row) => row.legalEntityId.equals(legalEntityId));
    }
    final rows = await query.get();
    return Future.wait(rows.map((row) => _decode(resource, row)));
  }

  Future<void> clearTenant(String tenantId) => (_database.delete(
    _database.referenceCacheEntries,
  )..where((row) => row.tenantId.equals(tenantId))).go();

  Future<SetupRecord> _decode(
    BusinessSetupResource resource,
    ReferenceCacheEntry row,
  ) async {
    final cleartext = await _cipher.decrypt(row.encryptedPayload);
    return SetupRecord.fromJson(
      resource,
      (jsonDecode(cleartext) as Map).cast<String, Object?>(),
    );
  }
}
