import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'local_database.g.dart';

class EncryptedDrafts extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get entityType => text()();
  BlobColumn get encryptedPayload => blob()();
  IntColumn get localVersion => integer().withDefault(const Constant(1))();
  IntColumn get serverVersion => integer().nullable()();
  TextColumn get syncState => text()();
  TextColumn get lastErrorCode => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Encrypted, tenant-scoped snapshots used for read-only offline setup pages.
class ReferenceCacheEntries extends Table {
  TextColumn get tenantId => text()();
  TextColumn get resource => text()();
  TextColumn get recordId => text()();
  TextColumn get legalEntityId => text().nullable()();
  BlobColumn get encryptedPayload => blob()();
  IntColumn get serverVersion => integer()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {tenantId, resource, recordId};
}

@DriftDatabase(tables: [EncryptedDrafts, ReferenceCacheEntries])
class JentraLocalDatabase extends _$JentraLocalDatabase {
  JentraLocalDatabase(super.executor);

  factory JentraLocalDatabase.open() => JentraLocalDatabase(
    LazyDatabase(() async {
      final directory = await getApplicationSupportDirectory();
      final file = File(p.join(directory.path, 'jentra', 'drafts.sqlite'));
      await file.parent.create(recursive: true);
      return NativeDatabase.createInBackground(file);
    }),
  );

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.createTable(referenceCacheEntries);
      }
    },
  );
}
