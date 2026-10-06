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

class $SettingsTable extends Settings
    with TableInfo<$SettingsTable, SettingEntity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingEntity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingEntity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingEntity(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class SettingEntity extends DataClass implements Insertable<SettingEntity> {
  final String key;
  final String value;
  const SettingEntity({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory SettingEntity.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingEntity(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SettingEntity copyWith({String? key, String? value}) =>
      SettingEntity(key: key ?? this.key, value: value ?? this.value);
  SettingEntity copyWithCompanion(SettingsCompanion data) {
    return SettingEntity(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingEntity(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingEntity &&
          other.key == this.key &&
          other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<SettingEntity> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SettingEntity> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReplicaDocumentsTable extends ReplicaDocuments
    with TableInfo<$ReplicaDocumentsTable, ReplicaDocumentEntity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReplicaDocumentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _desktopIdMeta = const VerificationMeta(
    'desktopId',
  );
  @override
  late final GeneratedColumn<String> desktopId = GeneratedColumn<String>(
    'desktop_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [desktopId, key, body, fetchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'replica_documents';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReplicaDocumentEntity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('desktop_id')) {
      context.handle(
        _desktopIdMeta,
        desktopId.isAcceptableOrUnknown(data['desktop_id']!, _desktopIdMeta),
      );
    } else if (isInserting) {
      context.missing(_desktopIdMeta);
    }
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {desktopId, key};
  @override
  ReplicaDocumentEntity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReplicaDocumentEntity(
      desktopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}desktop_id'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $ReplicaDocumentsTable createAlias(String alias) {
    return $ReplicaDocumentsTable(attachedDatabase, alias);
  }
}

class ReplicaDocumentEntity extends DataClass
    implements Insertable<ReplicaDocumentEntity> {
  final String desktopId;
  final String key;
  final String body;
  final DateTime fetchedAt;
  const ReplicaDocumentEntity({
    required this.desktopId,
    required this.key,
    required this.body,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['desktop_id'] = Variable<String>(desktopId);
    map['key'] = Variable<String>(key);
    map['body'] = Variable<String>(body);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  ReplicaDocumentsCompanion toCompanion(bool nullToAbsent) {
    return ReplicaDocumentsCompanion(
      desktopId: Value(desktopId),
      key: Value(key),
      body: Value(body),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory ReplicaDocumentEntity.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReplicaDocumentEntity(
      desktopId: serializer.fromJson<String>(json['desktopId']),
      key: serializer.fromJson<String>(json['key']),
      body: serializer.fromJson<String>(json['body']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'desktopId': serializer.toJson<String>(desktopId),
      'key': serializer.toJson<String>(key),
      'body': serializer.toJson<String>(body),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  ReplicaDocumentEntity copyWith({
    String? desktopId,
    String? key,
    String? body,
    DateTime? fetchedAt,
  }) => ReplicaDocumentEntity(
    desktopId: desktopId ?? this.desktopId,
    key: key ?? this.key,
    body: body ?? this.body,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  ReplicaDocumentEntity copyWithCompanion(ReplicaDocumentsCompanion data) {
    return ReplicaDocumentEntity(
      desktopId: data.desktopId.present ? data.desktopId.value : this.desktopId,
      key: data.key.present ? data.key.value : this.key,
      body: data.body.present ? data.body.value : this.body,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReplicaDocumentEntity(')
          ..write('desktopId: $desktopId, ')
          ..write('key: $key, ')
          ..write('body: $body, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(desktopId, key, body, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReplicaDocumentEntity &&
          other.desktopId == this.desktopId &&
          other.key == this.key &&
          other.body == this.body &&
          other.fetchedAt == this.fetchedAt);
}

class ReplicaDocumentsCompanion extends UpdateCompanion<ReplicaDocumentEntity> {
  final Value<String> desktopId;
  final Value<String> key;
  final Value<String> body;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const ReplicaDocumentsCompanion({
    this.desktopId = const Value.absent(),
    this.key = const Value.absent(),
    this.body = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReplicaDocumentsCompanion.insert({
    required String desktopId,
    required String key,
    required String body,
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : desktopId = Value(desktopId),
       key = Value(key),
       body = Value(body),
       fetchedAt = Value(fetchedAt);
  static Insertable<ReplicaDocumentEntity> custom({
    Expression<String>? desktopId,
    Expression<String>? key,
    Expression<String>? body,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (desktopId != null) 'desktop_id': desktopId,
      if (key != null) 'key': key,
      if (body != null) 'body': body,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReplicaDocumentsCompanion copyWith({
    Value<String>? desktopId,
    Value<String>? key,
    Value<String>? body,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return ReplicaDocumentsCompanion(
      desktopId: desktopId ?? this.desktopId,
      key: key ?? this.key,
      body: body ?? this.body,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (desktopId.present) {
      map['desktop_id'] = Variable<String>(desktopId.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReplicaDocumentsCompanion(')
          ..write('desktopId: $desktopId, ')
          ..write('key: $key, ')
          ..write('body: $body, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReplicaBlockEventsTable extends ReplicaBlockEvents
    with TableInfo<$ReplicaBlockEventsTable, ReplicaBlockEventEntity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReplicaBlockEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _desktopIdMeta = const VerificationMeta(
    'desktopId',
  );
  @override
  late final GeneratedColumn<String> desktopId = GeneratedColumn<String>(
    'desktop_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [desktopId, sessionId, seq, body];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'replica_block_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReplicaBlockEventEntity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('desktop_id')) {
      context.handle(
        _desktopIdMeta,
        desktopId.isAcceptableOrUnknown(data['desktop_id']!, _desktopIdMeta),
      );
    } else if (isInserting) {
      context.missing(_desktopIdMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('seq')) {
      context.handle(
        _seqMeta,
        seq.isAcceptableOrUnknown(data['seq']!, _seqMeta),
      );
    } else if (isInserting) {
      context.missing(_seqMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {desktopId, sessionId, seq};
  @override
  ReplicaBlockEventEntity map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReplicaBlockEventEntity(
      desktopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}desktop_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
    );
  }

  @override
  $ReplicaBlockEventsTable createAlias(String alias) {
    return $ReplicaBlockEventsTable(attachedDatabase, alias);
  }
}

class ReplicaBlockEventEntity extends DataClass
    implements Insertable<ReplicaBlockEventEntity> {
  final String desktopId;
  final String sessionId;
  final int seq;
  final String body;
  const ReplicaBlockEventEntity({
    required this.desktopId,
    required this.sessionId,
    required this.seq,
    required this.body,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['desktop_id'] = Variable<String>(desktopId);
    map['session_id'] = Variable<String>(sessionId);
    map['seq'] = Variable<int>(seq);
    map['body'] = Variable<String>(body);
    return map;
  }

  ReplicaBlockEventsCompanion toCompanion(bool nullToAbsent) {
    return ReplicaBlockEventsCompanion(
      desktopId: Value(desktopId),
      sessionId: Value(sessionId),
      seq: Value(seq),
      body: Value(body),
    );
  }

  factory ReplicaBlockEventEntity.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReplicaBlockEventEntity(
      desktopId: serializer.fromJson<String>(json['desktopId']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      seq: serializer.fromJson<int>(json['seq']),
      body: serializer.fromJson<String>(json['body']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'desktopId': serializer.toJson<String>(desktopId),
      'sessionId': serializer.toJson<String>(sessionId),
      'seq': serializer.toJson<int>(seq),
      'body': serializer.toJson<String>(body),
    };
  }

  ReplicaBlockEventEntity copyWith({
    String? desktopId,
    String? sessionId,
    int? seq,
    String? body,
  }) => ReplicaBlockEventEntity(
    desktopId: desktopId ?? this.desktopId,
    sessionId: sessionId ?? this.sessionId,
    seq: seq ?? this.seq,
    body: body ?? this.body,
  );
  ReplicaBlockEventEntity copyWithCompanion(ReplicaBlockEventsCompanion data) {
    return ReplicaBlockEventEntity(
      desktopId: data.desktopId.present ? data.desktopId.value : this.desktopId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      seq: data.seq.present ? data.seq.value : this.seq,
      body: data.body.present ? data.body.value : this.body,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReplicaBlockEventEntity(')
          ..write('desktopId: $desktopId, ')
          ..write('sessionId: $sessionId, ')
          ..write('seq: $seq, ')
          ..write('body: $body')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(desktopId, sessionId, seq, body);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReplicaBlockEventEntity &&
          other.desktopId == this.desktopId &&
          other.sessionId == this.sessionId &&
          other.seq == this.seq &&
          other.body == this.body);
}

class ReplicaBlockEventsCompanion
    extends UpdateCompanion<ReplicaBlockEventEntity> {
  final Value<String> desktopId;
  final Value<String> sessionId;
  final Value<int> seq;
  final Value<String> body;
  final Value<int> rowid;
  const ReplicaBlockEventsCompanion({
    this.desktopId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.seq = const Value.absent(),
    this.body = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReplicaBlockEventsCompanion.insert({
    required String desktopId,
    required String sessionId,
    required int seq,
    required String body,
    this.rowid = const Value.absent(),
  }) : desktopId = Value(desktopId),
       sessionId = Value(sessionId),
       seq = Value(seq),
       body = Value(body);
  static Insertable<ReplicaBlockEventEntity> custom({
    Expression<String>? desktopId,
    Expression<String>? sessionId,
    Expression<int>? seq,
    Expression<String>? body,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (desktopId != null) 'desktop_id': desktopId,
      if (sessionId != null) 'session_id': sessionId,
      if (seq != null) 'seq': seq,
      if (body != null) 'body': body,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReplicaBlockEventsCompanion copyWith({
    Value<String>? desktopId,
    Value<String>? sessionId,
    Value<int>? seq,
    Value<String>? body,
    Value<int>? rowid,
  }) {
    return ReplicaBlockEventsCompanion(
      desktopId: desktopId ?? this.desktopId,
      sessionId: sessionId ?? this.sessionId,
      seq: seq ?? this.seq,
      body: body ?? this.body,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (desktopId.present) {
      map['desktop_id'] = Variable<String>(desktopId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReplicaBlockEventsCompanion(')
          ..write('desktopId: $desktopId, ')
          ..write('sessionId: $sessionId, ')
          ..write('seq: $seq, ')
          ..write('body: $body, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $DesktopsTable desktops = $DesktopsTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $ReplicaDocumentsTable replicaDocuments = $ReplicaDocumentsTable(
    this,
  );
  late final $ReplicaBlockEventsTable replicaBlockEvents =
      $ReplicaBlockEventsTable(this);
  late final DesktopDao desktopDao = DesktopDao(this as AppDatabase);
  late final SettingsDao settingsDao = SettingsDao(this as AppDatabase);
  late final ReplicaDocumentDao replicaDocumentDao = ReplicaDocumentDao(
    this as AppDatabase,
  );
  late final ReplicaBlockEventDao replicaBlockEventDao = ReplicaBlockEventDao(
    this as AppDatabase,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    desktops,
    settings,
    replicaDocuments,
    replicaBlockEvents,
  ];
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
typedef $$SettingsTableCreateCompanionBuilder =
    SettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SettingsTableUpdateCompanionBuilder =
    SettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTable,
          SettingEntity,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (
            SettingEntity,
            BaseReferences<_$AppDatabase, $SettingsTable, SettingEntity>,
          ),
          SettingEntity,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTable,
      SettingEntity,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (
        SettingEntity,
        BaseReferences<_$AppDatabase, $SettingsTable, SettingEntity>,
      ),
      SettingEntity,
      PrefetchHooks Function()
    >;
typedef $$ReplicaDocumentsTableCreateCompanionBuilder =
    ReplicaDocumentsCompanion Function({
      required String desktopId,
      required String key,
      required String body,
      required DateTime fetchedAt,
      Value<int> rowid,
    });
typedef $$ReplicaDocumentsTableUpdateCompanionBuilder =
    ReplicaDocumentsCompanion Function({
      Value<String> desktopId,
      Value<String> key,
      Value<String> body,
      Value<DateTime> fetchedAt,
      Value<int> rowid,
    });

class $$ReplicaDocumentsTableFilterComposer
    extends Composer<_$AppDatabase, $ReplicaDocumentsTable> {
  $$ReplicaDocumentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get desktopId => $composableBuilder(
    column: $table.desktopId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReplicaDocumentsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReplicaDocumentsTable> {
  $$ReplicaDocumentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get desktopId => $composableBuilder(
    column: $table.desktopId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReplicaDocumentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReplicaDocumentsTable> {
  $$ReplicaDocumentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get desktopId =>
      $composableBuilder(column: $table.desktopId, builder: (column) => column);

  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$ReplicaDocumentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReplicaDocumentsTable,
          ReplicaDocumentEntity,
          $$ReplicaDocumentsTableFilterComposer,
          $$ReplicaDocumentsTableOrderingComposer,
          $$ReplicaDocumentsTableAnnotationComposer,
          $$ReplicaDocumentsTableCreateCompanionBuilder,
          $$ReplicaDocumentsTableUpdateCompanionBuilder,
          (
            ReplicaDocumentEntity,
            BaseReferences<
              _$AppDatabase,
              $ReplicaDocumentsTable,
              ReplicaDocumentEntity
            >,
          ),
          ReplicaDocumentEntity,
          PrefetchHooks Function()
        > {
  $$ReplicaDocumentsTableTableManager(
    _$AppDatabase db,
    $ReplicaDocumentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReplicaDocumentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReplicaDocumentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReplicaDocumentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> desktopId = const Value.absent(),
                Value<String> key = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReplicaDocumentsCompanion(
                desktopId: desktopId,
                key: key,
                body: body,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String desktopId,
                required String key,
                required String body,
                required DateTime fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => ReplicaDocumentsCompanion.insert(
                desktopId: desktopId,
                key: key,
                body: body,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReplicaDocumentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReplicaDocumentsTable,
      ReplicaDocumentEntity,
      $$ReplicaDocumentsTableFilterComposer,
      $$ReplicaDocumentsTableOrderingComposer,
      $$ReplicaDocumentsTableAnnotationComposer,
      $$ReplicaDocumentsTableCreateCompanionBuilder,
      $$ReplicaDocumentsTableUpdateCompanionBuilder,
      (
        ReplicaDocumentEntity,
        BaseReferences<
          _$AppDatabase,
          $ReplicaDocumentsTable,
          ReplicaDocumentEntity
        >,
      ),
      ReplicaDocumentEntity,
      PrefetchHooks Function()
    >;
typedef $$ReplicaBlockEventsTableCreateCompanionBuilder =
    ReplicaBlockEventsCompanion Function({
      required String desktopId,
      required String sessionId,
      required int seq,
      required String body,
      Value<int> rowid,
    });
typedef $$ReplicaBlockEventsTableUpdateCompanionBuilder =
    ReplicaBlockEventsCompanion Function({
      Value<String> desktopId,
      Value<String> sessionId,
      Value<int> seq,
      Value<String> body,
      Value<int> rowid,
    });

class $$ReplicaBlockEventsTableFilterComposer
    extends Composer<_$AppDatabase, $ReplicaBlockEventsTable> {
  $$ReplicaBlockEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get desktopId => $composableBuilder(
    column: $table.desktopId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReplicaBlockEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReplicaBlockEventsTable> {
  $$ReplicaBlockEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get desktopId => $composableBuilder(
    column: $table.desktopId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReplicaBlockEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReplicaBlockEventsTable> {
  $$ReplicaBlockEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get desktopId =>
      $composableBuilder(column: $table.desktopId, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);
}

class $$ReplicaBlockEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReplicaBlockEventsTable,
          ReplicaBlockEventEntity,
          $$ReplicaBlockEventsTableFilterComposer,
          $$ReplicaBlockEventsTableOrderingComposer,
          $$ReplicaBlockEventsTableAnnotationComposer,
          $$ReplicaBlockEventsTableCreateCompanionBuilder,
          $$ReplicaBlockEventsTableUpdateCompanionBuilder,
          (
            ReplicaBlockEventEntity,
            BaseReferences<
              _$AppDatabase,
              $ReplicaBlockEventsTable,
              ReplicaBlockEventEntity
            >,
          ),
          ReplicaBlockEventEntity,
          PrefetchHooks Function()
        > {
  $$ReplicaBlockEventsTableTableManager(
    _$AppDatabase db,
    $ReplicaBlockEventsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReplicaBlockEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReplicaBlockEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReplicaBlockEventsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> desktopId = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<int> seq = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReplicaBlockEventsCompanion(
                desktopId: desktopId,
                sessionId: sessionId,
                seq: seq,
                body: body,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String desktopId,
                required String sessionId,
                required int seq,
                required String body,
                Value<int> rowid = const Value.absent(),
              }) => ReplicaBlockEventsCompanion.insert(
                desktopId: desktopId,
                sessionId: sessionId,
                seq: seq,
                body: body,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReplicaBlockEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReplicaBlockEventsTable,
      ReplicaBlockEventEntity,
      $$ReplicaBlockEventsTableFilterComposer,
      $$ReplicaBlockEventsTableOrderingComposer,
      $$ReplicaBlockEventsTableAnnotationComposer,
      $$ReplicaBlockEventsTableCreateCompanionBuilder,
      $$ReplicaBlockEventsTableUpdateCompanionBuilder,
      (
        ReplicaBlockEventEntity,
        BaseReferences<
          _$AppDatabase,
          $ReplicaBlockEventsTable,
          ReplicaBlockEventEntity
        >,
      ),
      ReplicaBlockEventEntity,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$DesktopsTableTableManager get desktops =>
      $$DesktopsTableTableManager(_db, _db.desktops);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$ReplicaDocumentsTableTableManager get replicaDocuments =>
      $$ReplicaDocumentsTableTableManager(_db, _db.replicaDocuments);
  $$ReplicaBlockEventsTableTableManager get replicaBlockEvents =>
      $$ReplicaBlockEventsTableTableManager(_db, _db.replicaBlockEvents);
}
