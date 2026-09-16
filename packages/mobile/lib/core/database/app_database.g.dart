// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $DesktopsTable extends Desktops
    with TableInfo<$DesktopsTable, DesktopEntity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DesktopsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostMeta = const VerificationMeta('host');
  @override
  late final GeneratedColumn<String> host = GeneratedColumn<String>(
    'host',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _portMeta = const VerificationMeta('port');
  @override
  late final GeneratedColumn<String> port = GeneratedColumn<String>(
    'port',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _secureMeta = const VerificationMeta('secure');
  @override
  late final GeneratedColumn<bool> secure = GeneratedColumn<bool>(
    'secure',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("secure" IN (0, 1))',
    ),
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _renamedMeta = const VerificationMeta(
    'renamed',
  );
  @override
  late final GeneratedColumn<bool> renamed = GeneratedColumn<bool>(
    'renamed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("renamed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _lastConnectedAtMeta = const VerificationMeta(
    'lastConnectedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastConnectedAt =
      GeneratedColumn<DateTime>(
        'last_connected_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: DateTime.now,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    host,
    port,
    secure,
    isActive,
    renamed,
    lastConnectedAt,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'desktops';
  @override
  VerificationContext validateIntegrity(
    Insertable<DesktopEntity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('host')) {
      context.handle(
        _hostMeta,
        host.isAcceptableOrUnknown(data['host']!, _hostMeta),
      );
    } else if (isInserting) {
      context.missing(_hostMeta);
    }
    if (data.containsKey('port')) {
      context.handle(
        _portMeta,
        port.isAcceptableOrUnknown(data['port']!, _portMeta),
      );
    } else if (isInserting) {
      context.missing(_portMeta);
    }
    if (data.containsKey('secure')) {
      context.handle(
        _secureMeta,
        secure.isAcceptableOrUnknown(data['secure']!, _secureMeta),
      );
    } else if (isInserting) {
      context.missing(_secureMeta);
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('renamed')) {
      context.handle(
        _renamedMeta,
        renamed.isAcceptableOrUnknown(data['renamed']!, _renamedMeta),
      );
    }
    if (data.containsKey('last_connected_at')) {
      context.handle(
        _lastConnectedAtMeta,
        lastConnectedAt.isAcceptableOrUnknown(
          data['last_connected_at']!,
          _lastConnectedAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {host, port, secure},
  ];
  @override
  DesktopEntity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DesktopEntity(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      host: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host'],
      )!,
      port: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}port'],
      )!,
      secure: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}secure'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      renamed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}renamed'],
      )!,
      lastConnectedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_connected_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $DesktopsTable createAlias(String alias) {
    return $DesktopsTable(attachedDatabase, alias);
  }
}

class DesktopEntity extends DataClass implements Insertable<DesktopEntity> {
  final String id;
  final String name;
  final String host;
  final String port;
  final bool secure;
  final bool isActive;
  final bool renamed;
  final DateTime? lastConnectedAt;
  final DateTime createdAt;
  const DesktopEntity({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.secure,
    required this.isActive,
    required this.renamed,
    this.lastConnectedAt,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['host'] = Variable<String>(host);
    map['port'] = Variable<String>(port);
    map['secure'] = Variable<bool>(secure);
    map['is_active'] = Variable<bool>(isActive);
    map['renamed'] = Variable<bool>(renamed);
    if (!nullToAbsent || lastConnectedAt != null) {
      map['last_connected_at'] = Variable<DateTime>(lastConnectedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  DesktopsCompanion toCompanion(bool nullToAbsent) {
    return DesktopsCompanion(
      id: Value(id),
      name: Value(name),
      host: Value(host),
      port: Value(port),
      secure: Value(secure),
      isActive: Value(isActive),
      renamed: Value(renamed),
      lastConnectedAt: lastConnectedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastConnectedAt),
      createdAt: Value(createdAt),
    );
  }

  factory DesktopEntity.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DesktopEntity(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      host: serializer.fromJson<String>(json['host']),
      port: serializer.fromJson<String>(json['port']),
      secure: serializer.fromJson<bool>(json['secure']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      renamed: serializer.fromJson<bool>(json['renamed']),
      lastConnectedAt: serializer.fromJson<DateTime?>(json['lastConnectedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'host': serializer.toJson<String>(host),
      'port': serializer.toJson<String>(port),
      'secure': serializer.toJson<bool>(secure),
      'isActive': serializer.toJson<bool>(isActive),
      'renamed': serializer.toJson<bool>(renamed),
      'lastConnectedAt': serializer.toJson<DateTime?>(lastConnectedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  DesktopEntity copyWith({
    String? id,
    String? name,
    String? host,
    String? port,
    bool? secure,
    bool? isActive,
    bool? renamed,
    Value<DateTime?> lastConnectedAt = const Value.absent(),
    DateTime? createdAt,
  }) => DesktopEntity(
    id: id ?? this.id,
    name: name ?? this.name,
    host: host ?? this.host,
    port: port ?? this.port,
    secure: secure ?? this.secure,
    isActive: isActive ?? this.isActive,
    renamed: renamed ?? this.renamed,
    lastConnectedAt: lastConnectedAt.present
        ? lastConnectedAt.value
        : this.lastConnectedAt,
    createdAt: createdAt ?? this.createdAt,
  );
  DesktopEntity copyWithCompanion(DesktopsCompanion data) {
    return DesktopEntity(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      host: data.host.present ? data.host.value : this.host,
      port: data.port.present ? data.port.value : this.port,
      secure: data.secure.present ? data.secure.value : this.secure,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      renamed: data.renamed.present ? data.renamed.value : this.renamed,
      lastConnectedAt: data.lastConnectedAt.present
          ? data.lastConnectedAt.value
          : this.lastConnectedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DesktopEntity(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('host: $host, ')
          ..write('port: $port, ')
          ..write('secure: $secure, ')
          ..write('isActive: $isActive, ')
          ..write('renamed: $renamed, ')
          ..write('lastConnectedAt: $lastConnectedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    host,
    port,
    secure,
    isActive,
    renamed,
    lastConnectedAt,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DesktopEntity &&
          other.id == this.id &&
          other.name == this.name &&
          other.host == this.host &&
          other.port == this.port &&
          other.secure == this.secure &&
          other.isActive == this.isActive &&
          other.renamed == this.renamed &&
          other.lastConnectedAt == this.lastConnectedAt &&
          other.createdAt == this.createdAt);
}

class DesktopsCompanion extends UpdateCompanion<DesktopEntity> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> host;
  final Value<String> port;
  final Value<bool> secure;
  final Value<bool> isActive;
  final Value<bool> renamed;
  final Value<DateTime?> lastConnectedAt;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const DesktopsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.host = const Value.absent(),
    this.port = const Value.absent(),
    this.secure = const Value.absent(),
    this.isActive = const Value.absent(),
    this.renamed = const Value.absent(),
    this.lastConnectedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DesktopsCompanion.insert({
    required String id,
    required String name,
    required String host,
    required String port,
    required bool secure,
    this.isActive = const Value.absent(),
    this.renamed = const Value.absent(),
    this.lastConnectedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       host = Value(host),
       port = Value(port),
       secure = Value(secure);
  static Insertable<DesktopEntity> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? host,
    Expression<String>? port,
    Expression<bool>? secure,
    Expression<bool>? isActive,
    Expression<bool>? renamed,
    Expression<DateTime>? lastConnectedAt,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (host != null) 'host': host,
      if (port != null) 'port': port,
      if (secure != null) 'secure': secure,
      if (isActive != null) 'is_active': isActive,
      if (renamed != null) 'renamed': renamed,
      if (lastConnectedAt != null) 'last_connected_at': lastConnectedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DesktopsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? host,
    Value<String>? port,
    Value<bool>? secure,
    Value<bool>? isActive,
    Value<bool>? renamed,
    Value<DateTime?>? lastConnectedAt,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return DesktopsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      secure: secure ?? this.secure,
      isActive: isActive ?? this.isActive,
      renamed: renamed ?? this.renamed,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (host.present) {
      map['host'] = Variable<String>(host.value);
    }
    if (port.present) {
      map['port'] = Variable<String>(port.value);
    }
    if (secure.present) {
      map['secure'] = Variable<bool>(secure.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (renamed.present) {
      map['renamed'] = Variable<bool>(renamed.value);
    }
    if (lastConnectedAt.present) {
      map['last_connected_at'] = Variable<DateTime>(lastConnectedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DesktopsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('host: $host, ')
          ..write('port: $port, ')
          ..write('secure: $secure, ')
          ..write('isActive: $isActive, ')
          ..write('renamed: $renamed, ')
          ..write('lastConnectedAt: $lastConnectedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $DesktopsTable desktops = $DesktopsTable(this);
  late final DesktopDao desktopDao = DesktopDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [desktops];
}

typedef $$DesktopsTableCreateCompanionBuilder =
    DesktopsCompanion Function({
      required String id,
      required String name,
      required String host,
      required String port,
      required bool secure,
      Value<bool> isActive,
      Value<bool> renamed,
      Value<DateTime?> lastConnectedAt,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$DesktopsTableUpdateCompanionBuilder =
    DesktopsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> host,
      Value<String> port,
      Value<bool> secure,
      Value<bool> isActive,
      Value<bool> renamed,
      Value<DateTime?> lastConnectedAt,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$DesktopsTableFilterComposer
    extends Composer<_$AppDatabase, $DesktopsTable> {
  $$DesktopsTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get secure => $composableBuilder(
    column: $table.secure,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get renamed => $composableBuilder(
    column: $table.renamed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastConnectedAt => $composableBuilder(
    column: $table.lastConnectedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DesktopsTableOrderingComposer
    extends Composer<_$AppDatabase, $DesktopsTable> {
  $$DesktopsTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get secure => $composableBuilder(
    column: $table.secure,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get renamed => $composableBuilder(
    column: $table.renamed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastConnectedAt => $composableBuilder(
    column: $table.lastConnectedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DesktopsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DesktopsTable> {
  $$DesktopsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get host =>
      $composableBuilder(column: $table.host, builder: (column) => column);

  GeneratedColumn<String> get port =>
      $composableBuilder(column: $table.port, builder: (column) => column);

  GeneratedColumn<bool> get secure =>
      $composableBuilder(column: $table.secure, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<bool> get renamed =>
      $composableBuilder(column: $table.renamed, builder: (column) => column);

  GeneratedColumn<DateTime> get lastConnectedAt => $composableBuilder(
    column: $table.lastConnectedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$DesktopsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DesktopsTable,
          DesktopEntity,
          $$DesktopsTableFilterComposer,
          $$DesktopsTableOrderingComposer,
          $$DesktopsTableAnnotationComposer,
          $$DesktopsTableCreateCompanionBuilder,
          $$DesktopsTableUpdateCompanionBuilder,
          (
            DesktopEntity,
            BaseReferences<_$AppDatabase, $DesktopsTable, DesktopEntity>,
          ),
          DesktopEntity,
          PrefetchHooks Function()
        > {
  $$DesktopsTableTableManager(_$AppDatabase db, $DesktopsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DesktopsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DesktopsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DesktopsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> host = const Value.absent(),
                Value<String> port = const Value.absent(),
                Value<bool> secure = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<bool> renamed = const Value.absent(),
                Value<DateTime?> lastConnectedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DesktopsCompanion(
                id: id,
                name: name,
                host: host,
                port: port,
                secure: secure,
                isActive: isActive,
                renamed: renamed,
                lastConnectedAt: lastConnectedAt,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String host,
                required String port,
                required bool secure,
                Value<bool> isActive = const Value.absent(),
                Value<bool> renamed = const Value.absent(),
                Value<DateTime?> lastConnectedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DesktopsCompanion.insert(
                id: id,
                name: name,
                host: host,
                port: port,
                secure: secure,
                isActive: isActive,
                renamed: renamed,
                lastConnectedAt: lastConnectedAt,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DesktopsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DesktopsTable,
      DesktopEntity,
      $$DesktopsTableFilterComposer,
      $$DesktopsTableOrderingComposer,
      $$DesktopsTableAnnotationComposer,
      $$DesktopsTableCreateCompanionBuilder,
      $$DesktopsTableUpdateCompanionBuilder,
      (
        DesktopEntity,
        BaseReferences<_$AppDatabase, $DesktopsTable, DesktopEntity>,
      ),
      DesktopEntity,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$DesktopsTableTableManager get desktops =>
      $$DesktopsTableTableManager(_db, _db.desktops);
}
