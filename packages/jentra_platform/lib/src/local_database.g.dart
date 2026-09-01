// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_database.dart';

// ignore_for_file: type=lint
class $EncryptedDraftsTable extends EncryptedDrafts
    with TableInfo<$EncryptedDraftsTable, EncryptedDraft> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EncryptedDraftsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tenantIdMeta = const VerificationMeta(
    'tenantId',
  );
  @override
  late final GeneratedColumn<String> tenantId = GeneratedColumn<String>(
    'tenant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _encryptedPayloadMeta = const VerificationMeta(
    'encryptedPayload',
  );
  @override
  late final GeneratedColumn<Uint8List> encryptedPayload =
      GeneratedColumn<Uint8List>(
        'encrypted_payload',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _localVersionMeta = const VerificationMeta(
    'localVersion',
  );
  @override
  late final GeneratedColumn<int> localVersion = GeneratedColumn<int>(
    'local_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _serverVersionMeta = const VerificationMeta(
    'serverVersion',
  );
  @override
  late final GeneratedColumn<int> serverVersion = GeneratedColumn<int>(
    'server_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastErrorCodeMeta = const VerificationMeta(
    'lastErrorCode',
  );
  @override
  late final GeneratedColumn<String> lastErrorCode = GeneratedColumn<String>(
    'last_error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    tenantId,
    entityType,
    encryptedPayload,
    localVersion,
    serverVersion,
    syncState,
    lastErrorCode,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'encrypted_drafts';
  @override
  VerificationContext validateIntegrity(
    Insertable<EncryptedDraft> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('tenant_id')) {
      context.handle(
        _tenantIdMeta,
        tenantId.isAcceptableOrUnknown(data['tenant_id']!, _tenantIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tenantIdMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('encrypted_payload')) {
      context.handle(
        _encryptedPayloadMeta,
        encryptedPayload.isAcceptableOrUnknown(
          data['encrypted_payload']!,
          _encryptedPayloadMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_encryptedPayloadMeta);
    }
    if (data.containsKey('local_version')) {
      context.handle(
        _localVersionMeta,
        localVersion.isAcceptableOrUnknown(
          data['local_version']!,
          _localVersionMeta,
        ),
      );
    }
    if (data.containsKey('server_version')) {
      context.handle(
        _serverVersionMeta,
        serverVersion.isAcceptableOrUnknown(
          data['server_version']!,
          _serverVersionMeta,
        ),
      );
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    } else if (isInserting) {
      context.missing(_syncStateMeta);
    }
    if (data.containsKey('last_error_code')) {
      context.handle(
        _lastErrorCodeMeta,
        lastErrorCode.isAcceptableOrUnknown(
          data['last_error_code']!,
          _lastErrorCodeMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EncryptedDraft map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EncryptedDraft(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      tenantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tenant_id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      encryptedPayload: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}encrypted_payload'],
      )!,
      localVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_version'],
      )!,
      serverVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_version'],
      ),
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
      )!,
      lastErrorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error_code'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $EncryptedDraftsTable createAlias(String alias) {
    return $EncryptedDraftsTable(attachedDatabase, alias);
  }
}

class EncryptedDraft extends DataClass implements Insertable<EncryptedDraft> {
  final String id;
  final String tenantId;
  final String entityType;
  final Uint8List encryptedPayload;
  final int localVersion;
  final int? serverVersion;
  final String syncState;
  final String? lastErrorCode;
  final DateTime updatedAt;
  const EncryptedDraft({
    required this.id,
    required this.tenantId,
    required this.entityType,
    required this.encryptedPayload,
    required this.localVersion,
    this.serverVersion,
    required this.syncState,
    this.lastErrorCode,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['tenant_id'] = Variable<String>(tenantId);
    map['entity_type'] = Variable<String>(entityType);
    map['encrypted_payload'] = Variable<Uint8List>(encryptedPayload);
    map['local_version'] = Variable<int>(localVersion);
    if (!nullToAbsent || serverVersion != null) {
      map['server_version'] = Variable<int>(serverVersion);
    }
    map['sync_state'] = Variable<String>(syncState);
    if (!nullToAbsent || lastErrorCode != null) {
      map['last_error_code'] = Variable<String>(lastErrorCode);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  EncryptedDraftsCompanion toCompanion(bool nullToAbsent) {
    return EncryptedDraftsCompanion(
      id: Value(id),
      tenantId: Value(tenantId),
      entityType: Value(entityType),
      encryptedPayload: Value(encryptedPayload),
      localVersion: Value(localVersion),
      serverVersion: serverVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(serverVersion),
      syncState: Value(syncState),
      lastErrorCode: lastErrorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(lastErrorCode),
      updatedAt: Value(updatedAt),
    );
  }

  factory EncryptedDraft.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EncryptedDraft(
      id: serializer.fromJson<String>(json['id']),
      tenantId: serializer.fromJson<String>(json['tenantId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      encryptedPayload: serializer.fromJson<Uint8List>(
        json['encryptedPayload'],
      ),
      localVersion: serializer.fromJson<int>(json['localVersion']),
      serverVersion: serializer.fromJson<int?>(json['serverVersion']),
      syncState: serializer.fromJson<String>(json['syncState']),
      lastErrorCode: serializer.fromJson<String?>(json['lastErrorCode']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'tenantId': serializer.toJson<String>(tenantId),
      'entityType': serializer.toJson<String>(entityType),
      'encryptedPayload': serializer.toJson<Uint8List>(encryptedPayload),
      'localVersion': serializer.toJson<int>(localVersion),
      'serverVersion': serializer.toJson<int?>(serverVersion),
      'syncState': serializer.toJson<String>(syncState),
      'lastErrorCode': serializer.toJson<String?>(lastErrorCode),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  EncryptedDraft copyWith({
    String? id,
    String? tenantId,
    String? entityType,
    Uint8List? encryptedPayload,
    int? localVersion,
    Value<int?> serverVersion = const Value.absent(),
    String? syncState,
    Value<String?> lastErrorCode = const Value.absent(),
    DateTime? updatedAt,
  }) => EncryptedDraft(
    id: id ?? this.id,
    tenantId: tenantId ?? this.tenantId,
    entityType: entityType ?? this.entityType,
    encryptedPayload: encryptedPayload ?? this.encryptedPayload,
    localVersion: localVersion ?? this.localVersion,
    serverVersion: serverVersion.present
        ? serverVersion.value
        : this.serverVersion,
    syncState: syncState ?? this.syncState,
    lastErrorCode: lastErrorCode.present
        ? lastErrorCode.value
        : this.lastErrorCode,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  EncryptedDraft copyWithCompanion(EncryptedDraftsCompanion data) {
    return EncryptedDraft(
      id: data.id.present ? data.id.value : this.id,
      tenantId: data.tenantId.present ? data.tenantId.value : this.tenantId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      encryptedPayload: data.encryptedPayload.present
          ? data.encryptedPayload.value
          : this.encryptedPayload,
      localVersion: data.localVersion.present
          ? data.localVersion.value
          : this.localVersion,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
      lastErrorCode: data.lastErrorCode.present
          ? data.lastErrorCode.value
          : this.lastErrorCode,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EncryptedDraft(')
          ..write('id: $id, ')
          ..write('tenantId: $tenantId, ')
          ..write('entityType: $entityType, ')
          ..write('encryptedPayload: $encryptedPayload, ')
          ..write('localVersion: $localVersion, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('syncState: $syncState, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    tenantId,
    entityType,
    $driftBlobEquality.hash(encryptedPayload),
    localVersion,
    serverVersion,
    syncState,
    lastErrorCode,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EncryptedDraft &&
          other.id == this.id &&
          other.tenantId == this.tenantId &&
          other.entityType == this.entityType &&
          $driftBlobEquality.equals(
            other.encryptedPayload,
            this.encryptedPayload,
          ) &&
          other.localVersion == this.localVersion &&
          other.serverVersion == this.serverVersion &&
          other.syncState == this.syncState &&
          other.lastErrorCode == this.lastErrorCode &&
          other.updatedAt == this.updatedAt);
}

class EncryptedDraftsCompanion extends UpdateCompanion<EncryptedDraft> {
  final Value<String> id;
  final Value<String> tenantId;
  final Value<String> entityType;
  final Value<Uint8List> encryptedPayload;
  final Value<int> localVersion;
  final Value<int?> serverVersion;
  final Value<String> syncState;
  final Value<String?> lastErrorCode;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const EncryptedDraftsCompanion({
    this.id = const Value.absent(),
    this.tenantId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.encryptedPayload = const Value.absent(),
    this.localVersion = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.syncState = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EncryptedDraftsCompanion.insert({
    required String id,
    required String tenantId,
    required String entityType,
    required Uint8List encryptedPayload,
    this.localVersion = const Value.absent(),
    this.serverVersion = const Value.absent(),
    required String syncState,
    this.lastErrorCode = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       tenantId = Value(tenantId),
       entityType = Value(entityType),
       encryptedPayload = Value(encryptedPayload),
       syncState = Value(syncState),
       updatedAt = Value(updatedAt);
  static Insertable<EncryptedDraft> custom({
    Expression<String>? id,
    Expression<String>? tenantId,
    Expression<String>? entityType,
    Expression<Uint8List>? encryptedPayload,
    Expression<int>? localVersion,
    Expression<int>? serverVersion,
    Expression<String>? syncState,
    Expression<String>? lastErrorCode,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (tenantId != null) 'tenant_id': tenantId,
      if (entityType != null) 'entity_type': entityType,
      if (encryptedPayload != null) 'encrypted_payload': encryptedPayload,
      if (localVersion != null) 'local_version': localVersion,
      if (serverVersion != null) 'server_version': serverVersion,
      if (syncState != null) 'sync_state': syncState,
      if (lastErrorCode != null) 'last_error_code': lastErrorCode,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EncryptedDraftsCompanion copyWith({
    Value<String>? id,
    Value<String>? tenantId,
    Value<String>? entityType,
    Value<Uint8List>? encryptedPayload,
    Value<int>? localVersion,
    Value<int?>? serverVersion,
    Value<String>? syncState,
    Value<String?>? lastErrorCode,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return EncryptedDraftsCompanion(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      entityType: entityType ?? this.entityType,
      encryptedPayload: encryptedPayload ?? this.encryptedPayload,
      localVersion: localVersion ?? this.localVersion,
      serverVersion: serverVersion ?? this.serverVersion,
      syncState: syncState ?? this.syncState,
      lastErrorCode: lastErrorCode ?? this.lastErrorCode,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (tenantId.present) {
      map['tenant_id'] = Variable<String>(tenantId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (encryptedPayload.present) {
      map['encrypted_payload'] = Variable<Uint8List>(encryptedPayload.value);
    }
    if (localVersion.present) {
      map['local_version'] = Variable<int>(localVersion.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<int>(serverVersion.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
    }
    if (lastErrorCode.present) {
      map['last_error_code'] = Variable<String>(lastErrorCode.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EncryptedDraftsCompanion(')
          ..write('id: $id, ')
          ..write('tenantId: $tenantId, ')
          ..write('entityType: $entityType, ')
          ..write('encryptedPayload: $encryptedPayload, ')
          ..write('localVersion: $localVersion, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('syncState: $syncState, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$JentraLocalDatabase extends GeneratedDatabase {
  _$JentraLocalDatabase(QueryExecutor e) : super(e);
  $JentraLocalDatabaseManager get managers => $JentraLocalDatabaseManager(this);
  late final $EncryptedDraftsTable encryptedDrafts = $EncryptedDraftsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [encryptedDrafts];
}

typedef $$EncryptedDraftsTableCreateCompanionBuilder =
    EncryptedDraftsCompanion Function({
      required String id,
      required String tenantId,
      required String entityType,
      required Uint8List encryptedPayload,
      Value<int> localVersion,
      Value<int?> serverVersion,
      required String syncState,
      Value<String?> lastErrorCode,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$EncryptedDraftsTableUpdateCompanionBuilder =
    EncryptedDraftsCompanion Function({
      Value<String> id,
      Value<String> tenantId,
      Value<String> entityType,
      Value<Uint8List> encryptedPayload,
      Value<int> localVersion,
      Value<int?> serverVersion,
      Value<String> syncState,
      Value<String?> lastErrorCode,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$EncryptedDraftsTableFilterComposer
    extends Composer<_$JentraLocalDatabase, $EncryptedDraftsTable> {
  $$EncryptedDraftsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get encryptedPayload => $composableBuilder(
    column: $table.encryptedPayload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localVersion => $composableBuilder(
    column: $table.localVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EncryptedDraftsTableOrderingComposer
    extends Composer<_$JentraLocalDatabase, $EncryptedDraftsTable> {
  $$EncryptedDraftsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get encryptedPayload => $composableBuilder(
    column: $table.encryptedPayload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localVersion => $composableBuilder(
    column: $table.localVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EncryptedDraftsTableAnnotationComposer
    extends Composer<_$JentraLocalDatabase, $EncryptedDraftsTable> {
  $$EncryptedDraftsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get tenantId =>
      $composableBuilder(column: $table.tenantId, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get encryptedPayload => $composableBuilder(
    column: $table.encryptedPayload,
    builder: (column) => column,
  );

  GeneratedColumn<int> get localVersion => $composableBuilder(
    column: $table.localVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);

  GeneratedColumn<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$EncryptedDraftsTableTableManager
    extends
        RootTableManager<
          _$JentraLocalDatabase,
          $EncryptedDraftsTable,
          EncryptedDraft,
          $$EncryptedDraftsTableFilterComposer,
          $$EncryptedDraftsTableOrderingComposer,
          $$EncryptedDraftsTableAnnotationComposer,
          $$EncryptedDraftsTableCreateCompanionBuilder,
          $$EncryptedDraftsTableUpdateCompanionBuilder,
          (
            EncryptedDraft,
            BaseReferences<
              _$JentraLocalDatabase,
              $EncryptedDraftsTable,
              EncryptedDraft
            >,
          ),
          EncryptedDraft,
          PrefetchHooks Function()
        > {
  $$EncryptedDraftsTableTableManager(
    _$JentraLocalDatabase db,
    $EncryptedDraftsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EncryptedDraftsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EncryptedDraftsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EncryptedDraftsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> tenantId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<Uint8List> encryptedPayload = const Value.absent(),
                Value<int> localVersion = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EncryptedDraftsCompanion(
                id: id,
                tenantId: tenantId,
                entityType: entityType,
                encryptedPayload: encryptedPayload,
                localVersion: localVersion,
                serverVersion: serverVersion,
                syncState: syncState,
                lastErrorCode: lastErrorCode,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String tenantId,
                required String entityType,
                required Uint8List encryptedPayload,
                Value<int> localVersion = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                required String syncState,
                Value<String?> lastErrorCode = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => EncryptedDraftsCompanion.insert(
                id: id,
                tenantId: tenantId,
                entityType: entityType,
                encryptedPayload: encryptedPayload,
                localVersion: localVersion,
                serverVersion: serverVersion,
                syncState: syncState,
                lastErrorCode: lastErrorCode,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EncryptedDraftsTableProcessedTableManager =
    ProcessedTableManager<
      _$JentraLocalDatabase,
      $EncryptedDraftsTable,
      EncryptedDraft,
      $$EncryptedDraftsTableFilterComposer,
      $$EncryptedDraftsTableOrderingComposer,
      $$EncryptedDraftsTableAnnotationComposer,
      $$EncryptedDraftsTableCreateCompanionBuilder,
      $$EncryptedDraftsTableUpdateCompanionBuilder,
      (
        EncryptedDraft,
        BaseReferences<
          _$JentraLocalDatabase,
          $EncryptedDraftsTable,
          EncryptedDraft
        >,
      ),
      EncryptedDraft,
      PrefetchHooks Function()
    >;

class $JentraLocalDatabaseManager {
  final _$JentraLocalDatabase _db;
  $JentraLocalDatabaseManager(this._db);
  $$EncryptedDraftsTableTableManager get encryptedDrafts =>
      $$EncryptedDraftsTableTableManager(_db, _db.encryptedDrafts);
}
