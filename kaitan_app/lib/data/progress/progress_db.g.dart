// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'progress_db.dart';

// ignore_for_file: type=lint
class $WordProgressTable extends WordProgress
    with TableInfo<$WordProgressTable, WordProgressData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WordProgressTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _wordIdMeta = const VerificationMeta('wordId');
  @override
  late final GeneratedColumn<int> wordId = GeneratedColumn<int>(
    'word_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stageMeta = const VerificationMeta('stage');
  @override
  late final GeneratedColumn<String> stage = GeneratedColumn<String>(
    'stage',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _firstRoundResultMeta = const VerificationMeta(
    'firstRoundResult',
  );
  @override
  late final GeneratedColumn<String> firstRoundResult = GeneratedColumn<String>(
    'first_round_result',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastResultMeta = const VerificationMeta(
    'lastResult',
  );
  @override
  late final GeneratedColumn<String> lastResult = GeneratedColumn<String>(
    'last_result',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    wordId,
    stage,
    firstRoundResult,
    lastResult,
    attempts,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'word_progress';
  @override
  VerificationContext validateIntegrity(
    Insertable<WordProgressData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('word_id')) {
      context.handle(
        _wordIdMeta,
        wordId.isAcceptableOrUnknown(data['word_id']!, _wordIdMeta),
      );
    } else if (isInserting) {
      context.missing(_wordIdMeta);
    }
    if (data.containsKey('stage')) {
      context.handle(
        _stageMeta,
        stage.isAcceptableOrUnknown(data['stage']!, _stageMeta),
      );
    } else if (isInserting) {
      context.missing(_stageMeta);
    }
    if (data.containsKey('first_round_result')) {
      context.handle(
        _firstRoundResultMeta,
        firstRoundResult.isAcceptableOrUnknown(
          data['first_round_result']!,
          _firstRoundResultMeta,
        ),
      );
    }
    if (data.containsKey('last_result')) {
      context.handle(
        _lastResultMeta,
        lastResult.isAcceptableOrUnknown(data['last_result']!, _lastResultMeta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {wordId, stage};
  @override
  WordProgressData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WordProgressData(
      wordId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}word_id'],
      )!,
      stage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stage'],
      )!,
      firstRoundResult: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_round_result'],
      ),
      lastResult: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_result'],
      ),
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $WordProgressTable createAlias(String alias) {
    return $WordProgressTable(attachedDatabase, alias);
  }
}

class WordProgressData extends DataClass
    implements Insertable<WordProgressData> {
  final int wordId;
  final String stage;
  final String? firstRoundResult;
  final String? lastResult;
  final int attempts;
  final DateTime updatedAt;
  const WordProgressData({
    required this.wordId,
    required this.stage,
    this.firstRoundResult,
    this.lastResult,
    required this.attempts,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['word_id'] = Variable<int>(wordId);
    map['stage'] = Variable<String>(stage);
    if (!nullToAbsent || firstRoundResult != null) {
      map['first_round_result'] = Variable<String>(firstRoundResult);
    }
    if (!nullToAbsent || lastResult != null) {
      map['last_result'] = Variable<String>(lastResult);
    }
    map['attempts'] = Variable<int>(attempts);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  WordProgressCompanion toCompanion(bool nullToAbsent) {
    return WordProgressCompanion(
      wordId: Value(wordId),
      stage: Value(stage),
      firstRoundResult: firstRoundResult == null && nullToAbsent
          ? const Value.absent()
          : Value(firstRoundResult),
      lastResult: lastResult == null && nullToAbsent
          ? const Value.absent()
          : Value(lastResult),
      attempts: Value(attempts),
      updatedAt: Value(updatedAt),
    );
  }

  factory WordProgressData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WordProgressData(
      wordId: serializer.fromJson<int>(json['wordId']),
      stage: serializer.fromJson<String>(json['stage']),
      firstRoundResult: serializer.fromJson<String?>(json['firstRoundResult']),
      lastResult: serializer.fromJson<String?>(json['lastResult']),
      attempts: serializer.fromJson<int>(json['attempts']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'wordId': serializer.toJson<int>(wordId),
      'stage': serializer.toJson<String>(stage),
      'firstRoundResult': serializer.toJson<String?>(firstRoundResult),
      'lastResult': serializer.toJson<String?>(lastResult),
      'attempts': serializer.toJson<int>(attempts),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  WordProgressData copyWith({
    int? wordId,
    String? stage,
    Value<String?> firstRoundResult = const Value.absent(),
    Value<String?> lastResult = const Value.absent(),
    int? attempts,
    DateTime? updatedAt,
  }) => WordProgressData(
    wordId: wordId ?? this.wordId,
    stage: stage ?? this.stage,
    firstRoundResult: firstRoundResult.present
        ? firstRoundResult.value
        : this.firstRoundResult,
    lastResult: lastResult.present ? lastResult.value : this.lastResult,
    attempts: attempts ?? this.attempts,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  WordProgressData copyWithCompanion(WordProgressCompanion data) {
    return WordProgressData(
      wordId: data.wordId.present ? data.wordId.value : this.wordId,
      stage: data.stage.present ? data.stage.value : this.stage,
      firstRoundResult: data.firstRoundResult.present
          ? data.firstRoundResult.value
          : this.firstRoundResult,
      lastResult: data.lastResult.present
          ? data.lastResult.value
          : this.lastResult,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WordProgressData(')
          ..write('wordId: $wordId, ')
          ..write('stage: $stage, ')
          ..write('firstRoundResult: $firstRoundResult, ')
          ..write('lastResult: $lastResult, ')
          ..write('attempts: $attempts, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    wordId,
    stage,
    firstRoundResult,
    lastResult,
    attempts,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WordProgressData &&
          other.wordId == this.wordId &&
          other.stage == this.stage &&
          other.firstRoundResult == this.firstRoundResult &&
          other.lastResult == this.lastResult &&
          other.attempts == this.attempts &&
          other.updatedAt == this.updatedAt);
}

class WordProgressCompanion extends UpdateCompanion<WordProgressData> {
  final Value<int> wordId;
  final Value<String> stage;
  final Value<String?> firstRoundResult;
  final Value<String?> lastResult;
  final Value<int> attempts;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const WordProgressCompanion({
    this.wordId = const Value.absent(),
    this.stage = const Value.absent(),
    this.firstRoundResult = const Value.absent(),
    this.lastResult = const Value.absent(),
    this.attempts = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WordProgressCompanion.insert({
    required int wordId,
    required String stage,
    this.firstRoundResult = const Value.absent(),
    this.lastResult = const Value.absent(),
    this.attempts = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : wordId = Value(wordId),
       stage = Value(stage);
  static Insertable<WordProgressData> custom({
    Expression<int>? wordId,
    Expression<String>? stage,
    Expression<String>? firstRoundResult,
    Expression<String>? lastResult,
    Expression<int>? attempts,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (wordId != null) 'word_id': wordId,
      if (stage != null) 'stage': stage,
      if (firstRoundResult != null) 'first_round_result': firstRoundResult,
      if (lastResult != null) 'last_result': lastResult,
      if (attempts != null) 'attempts': attempts,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WordProgressCompanion copyWith({
    Value<int>? wordId,
    Value<String>? stage,
    Value<String?>? firstRoundResult,
    Value<String?>? lastResult,
    Value<int>? attempts,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return WordProgressCompanion(
      wordId: wordId ?? this.wordId,
      stage: stage ?? this.stage,
      firstRoundResult: firstRoundResult ?? this.firstRoundResult,
      lastResult: lastResult ?? this.lastResult,
      attempts: attempts ?? this.attempts,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (wordId.present) {
      map['word_id'] = Variable<int>(wordId.value);
    }
    if (stage.present) {
      map['stage'] = Variable<String>(stage.value);
    }
    if (firstRoundResult.present) {
      map['first_round_result'] = Variable<String>(firstRoundResult.value);
    }
    if (lastResult.present) {
      map['last_result'] = Variable<String>(lastResult.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
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
    return (StringBuffer('WordProgressCompanion(')
          ..write('wordId: $wordId, ')
          ..write('stage: $stage, ')
          ..write('firstRoundResult: $firstRoundResult, ')
          ..write('lastResult: $lastResult, ')
          ..write('attempts: $attempts, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BlockStateTable extends BlockState
    with TableInfo<$BlockStateTable, BlockStateData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BlockStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _blockNoMeta = const VerificationMeta(
    'blockNo',
  );
  @override
  late final GeneratedColumn<int> blockNo = GeneratedColumn<int>(
    'block_no',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stageMeta = const VerificationMeta('stage');
  @override
  late final GeneratedColumn<String> stage = GeneratedColumn<String>(
    'stage',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unlearned'),
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [blockNo, stage, status, completedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'block_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<BlockStateData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('block_no')) {
      context.handle(
        _blockNoMeta,
        blockNo.isAcceptableOrUnknown(data['block_no']!, _blockNoMeta),
      );
    } else if (isInserting) {
      context.missing(_blockNoMeta);
    }
    if (data.containsKey('stage')) {
      context.handle(
        _stageMeta,
        stage.isAcceptableOrUnknown(data['stage']!, _stageMeta),
      );
    } else if (isInserting) {
      context.missing(_stageMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {blockNo, stage};
  @override
  BlockStateData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BlockStateData(
      blockNo: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}block_no'],
      )!,
      stage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stage'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
    );
  }

  @override
  $BlockStateTable createAlias(String alias) {
    return $BlockStateTable(attachedDatabase, alias);
  }
}

class BlockStateData extends DataClass implements Insertable<BlockStateData> {
  final int blockNo;
  final String stage;
  final String status;
  final DateTime? completedAt;
  const BlockStateData({
    required this.blockNo,
    required this.stage,
    required this.status,
    this.completedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['block_no'] = Variable<int>(blockNo);
    map['stage'] = Variable<String>(stage);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    return map;
  }

  BlockStateCompanion toCompanion(bool nullToAbsent) {
    return BlockStateCompanion(
      blockNo: Value(blockNo),
      stage: Value(stage),
      status: Value(status),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
    );
  }

  factory BlockStateData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BlockStateData(
      blockNo: serializer.fromJson<int>(json['blockNo']),
      stage: serializer.fromJson<String>(json['stage']),
      status: serializer.fromJson<String>(json['status']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'blockNo': serializer.toJson<int>(blockNo),
      'stage': serializer.toJson<String>(stage),
      'status': serializer.toJson<String>(status),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
    };
  }

  BlockStateData copyWith({
    int? blockNo,
    String? stage,
    String? status,
    Value<DateTime?> completedAt = const Value.absent(),
  }) => BlockStateData(
    blockNo: blockNo ?? this.blockNo,
    stage: stage ?? this.stage,
    status: status ?? this.status,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
  );
  BlockStateData copyWithCompanion(BlockStateCompanion data) {
    return BlockStateData(
      blockNo: data.blockNo.present ? data.blockNo.value : this.blockNo,
      stage: data.stage.present ? data.stage.value : this.stage,
      status: data.status.present ? data.status.value : this.status,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BlockStateData(')
          ..write('blockNo: $blockNo, ')
          ..write('stage: $stage, ')
          ..write('status: $status, ')
          ..write('completedAt: $completedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(blockNo, stage, status, completedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BlockStateData &&
          other.blockNo == this.blockNo &&
          other.stage == this.stage &&
          other.status == this.status &&
          other.completedAt == this.completedAt);
}

class BlockStateCompanion extends UpdateCompanion<BlockStateData> {
  final Value<int> blockNo;
  final Value<String> stage;
  final Value<String> status;
  final Value<DateTime?> completedAt;
  final Value<int> rowid;
  const BlockStateCompanion({
    this.blockNo = const Value.absent(),
    this.stage = const Value.absent(),
    this.status = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BlockStateCompanion.insert({
    required int blockNo,
    required String stage,
    this.status = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : blockNo = Value(blockNo),
       stage = Value(stage);
  static Insertable<BlockStateData> custom({
    Expression<int>? blockNo,
    Expression<String>? stage,
    Expression<String>? status,
    Expression<DateTime>? completedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (blockNo != null) 'block_no': blockNo,
      if (stage != null) 'stage': stage,
      if (status != null) 'status': status,
      if (completedAt != null) 'completed_at': completedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BlockStateCompanion copyWith({
    Value<int>? blockNo,
    Value<String>? stage,
    Value<String>? status,
    Value<DateTime?>? completedAt,
    Value<int>? rowid,
  }) {
    return BlockStateCompanion(
      blockNo: blockNo ?? this.blockNo,
      stage: stage ?? this.stage,
      status: status ?? this.status,
      completedAt: completedAt ?? this.completedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (blockNo.present) {
      map['block_no'] = Variable<int>(blockNo.value);
    }
    if (stage.present) {
      map['stage'] = Variable<String>(stage.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BlockStateCompanion(')
          ..write('blockNo: $blockNo, ')
          ..write('stage: $stage, ')
          ..write('status: $status, ')
          ..write('completedAt: $completedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StageProgressTable extends StageProgress
    with TableInfo<$StageProgressTable, StageProgressData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StageProgressTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _stageMeta = const VerificationMeta('stage');
  @override
  late final GeneratedColumn<String> stage = GeneratedColumn<String>(
    'stage',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lapCountMeta = const VerificationMeta(
    'lapCount',
  );
  @override
  late final GeneratedColumn<int> lapCount = GeneratedColumn<int>(
    'lap_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [stage, lapCount, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stage_progress';
  @override
  VerificationContext validateIntegrity(
    Insertable<StageProgressData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('stage')) {
      context.handle(
        _stageMeta,
        stage.isAcceptableOrUnknown(data['stage']!, _stageMeta),
      );
    } else if (isInserting) {
      context.missing(_stageMeta);
    }
    if (data.containsKey('lap_count')) {
      context.handle(
        _lapCountMeta,
        lapCount.isAcceptableOrUnknown(data['lap_count']!, _lapCountMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {stage};
  @override
  StageProgressData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StageProgressData(
      stage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stage'],
      )!,
      lapCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lap_count'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $StageProgressTable createAlias(String alias) {
    return $StageProgressTable(attachedDatabase, alias);
  }
}

class StageProgressData extends DataClass
    implements Insertable<StageProgressData> {
  final String stage;
  final int lapCount;
  final DateTime updatedAt;
  const StageProgressData({
    required this.stage,
    required this.lapCount,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['stage'] = Variable<String>(stage);
    map['lap_count'] = Variable<int>(lapCount);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  StageProgressCompanion toCompanion(bool nullToAbsent) {
    return StageProgressCompanion(
      stage: Value(stage),
      lapCount: Value(lapCount),
      updatedAt: Value(updatedAt),
    );
  }

  factory StageProgressData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StageProgressData(
      stage: serializer.fromJson<String>(json['stage']),
      lapCount: serializer.fromJson<int>(json['lapCount']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'stage': serializer.toJson<String>(stage),
      'lapCount': serializer.toJson<int>(lapCount),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  StageProgressData copyWith({
    String? stage,
    int? lapCount,
    DateTime? updatedAt,
  }) => StageProgressData(
    stage: stage ?? this.stage,
    lapCount: lapCount ?? this.lapCount,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  StageProgressData copyWithCompanion(StageProgressCompanion data) {
    return StageProgressData(
      stage: data.stage.present ? data.stage.value : this.stage,
      lapCount: data.lapCount.present ? data.lapCount.value : this.lapCount,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StageProgressData(')
          ..write('stage: $stage, ')
          ..write('lapCount: $lapCount, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(stage, lapCount, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StageProgressData &&
          other.stage == this.stage &&
          other.lapCount == this.lapCount &&
          other.updatedAt == this.updatedAt);
}

class StageProgressCompanion extends UpdateCompanion<StageProgressData> {
  final Value<String> stage;
  final Value<int> lapCount;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const StageProgressCompanion({
    this.stage = const Value.absent(),
    this.lapCount = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StageProgressCompanion.insert({
    required String stage,
    this.lapCount = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : stage = Value(stage);
  static Insertable<StageProgressData> custom({
    Expression<String>? stage,
    Expression<int>? lapCount,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (stage != null) 'stage': stage,
      if (lapCount != null) 'lap_count': lapCount,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StageProgressCompanion copyWith({
    Value<String>? stage,
    Value<int>? lapCount,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return StageProgressCompanion(
      stage: stage ?? this.stage,
      lapCount: lapCount ?? this.lapCount,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (stage.present) {
      map['stage'] = Variable<String>(stage.value);
    }
    if (lapCount.present) {
      map['lap_count'] = Variable<int>(lapCount.value);
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
    return (StringBuffer('StageProgressCompanion(')
          ..write('stage: $stage, ')
          ..write('lapCount: $lapCount, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$ProgressDb extends GeneratedDatabase {
  _$ProgressDb(QueryExecutor e) : super(e);
  $ProgressDbManager get managers => $ProgressDbManager(this);
  late final $WordProgressTable wordProgress = $WordProgressTable(this);
  late final $BlockStateTable blockState = $BlockStateTable(this);
  late final $StageProgressTable stageProgress = $StageProgressTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    wordProgress,
    blockState,
    stageProgress,
  ];
}

typedef $$WordProgressTableCreateCompanionBuilder =
    WordProgressCompanion Function({
      required int wordId,
      required String stage,
      Value<String?> firstRoundResult,
      Value<String?> lastResult,
      Value<int> attempts,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$WordProgressTableUpdateCompanionBuilder =
    WordProgressCompanion Function({
      Value<int> wordId,
      Value<String> stage,
      Value<String?> firstRoundResult,
      Value<String?> lastResult,
      Value<int> attempts,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$WordProgressTableFilterComposer
    extends Composer<_$ProgressDb, $WordProgressTable> {
  $$WordProgressTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get wordId => $composableBuilder(
    column: $table.wordId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stage => $composableBuilder(
    column: $table.stage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firstRoundResult => $composableBuilder(
    column: $table.firstRoundResult,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastResult => $composableBuilder(
    column: $table.lastResult,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WordProgressTableOrderingComposer
    extends Composer<_$ProgressDb, $WordProgressTable> {
  $$WordProgressTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get wordId => $composableBuilder(
    column: $table.wordId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stage => $composableBuilder(
    column: $table.stage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firstRoundResult => $composableBuilder(
    column: $table.firstRoundResult,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastResult => $composableBuilder(
    column: $table.lastResult,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WordProgressTableAnnotationComposer
    extends Composer<_$ProgressDb, $WordProgressTable> {
  $$WordProgressTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get wordId =>
      $composableBuilder(column: $table.wordId, builder: (column) => column);

  GeneratedColumn<String> get stage =>
      $composableBuilder(column: $table.stage, builder: (column) => column);

  GeneratedColumn<String> get firstRoundResult => $composableBuilder(
    column: $table.firstRoundResult,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastResult => $composableBuilder(
    column: $table.lastResult,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$WordProgressTableTableManager
    extends
        RootTableManager<
          _$ProgressDb,
          $WordProgressTable,
          WordProgressData,
          $$WordProgressTableFilterComposer,
          $$WordProgressTableOrderingComposer,
          $$WordProgressTableAnnotationComposer,
          $$WordProgressTableCreateCompanionBuilder,
          $$WordProgressTableUpdateCompanionBuilder,
          (
            WordProgressData,
            BaseReferences<_$ProgressDb, $WordProgressTable, WordProgressData>,
          ),
          WordProgressData,
          PrefetchHooks Function()
        > {
  $$WordProgressTableTableManager(_$ProgressDb db, $WordProgressTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WordProgressTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WordProgressTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WordProgressTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> wordId = const Value.absent(),
                Value<String> stage = const Value.absent(),
                Value<String?> firstRoundResult = const Value.absent(),
                Value<String?> lastResult = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WordProgressCompanion(
                wordId: wordId,
                stage: stage,
                firstRoundResult: firstRoundResult,
                lastResult: lastResult,
                attempts: attempts,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int wordId,
                required String stage,
                Value<String?> firstRoundResult = const Value.absent(),
                Value<String?> lastResult = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WordProgressCompanion.insert(
                wordId: wordId,
                stage: stage,
                firstRoundResult: firstRoundResult,
                lastResult: lastResult,
                attempts: attempts,
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

typedef $$WordProgressTableProcessedTableManager =
    ProcessedTableManager<
      _$ProgressDb,
      $WordProgressTable,
      WordProgressData,
      $$WordProgressTableFilterComposer,
      $$WordProgressTableOrderingComposer,
      $$WordProgressTableAnnotationComposer,
      $$WordProgressTableCreateCompanionBuilder,
      $$WordProgressTableUpdateCompanionBuilder,
      (
        WordProgressData,
        BaseReferences<_$ProgressDb, $WordProgressTable, WordProgressData>,
      ),
      WordProgressData,
      PrefetchHooks Function()
    >;
typedef $$BlockStateTableCreateCompanionBuilder =
    BlockStateCompanion Function({
      required int blockNo,
      required String stage,
      Value<String> status,
      Value<DateTime?> completedAt,
      Value<int> rowid,
    });
typedef $$BlockStateTableUpdateCompanionBuilder =
    BlockStateCompanion Function({
      Value<int> blockNo,
      Value<String> stage,
      Value<String> status,
      Value<DateTime?> completedAt,
      Value<int> rowid,
    });

class $$BlockStateTableFilterComposer
    extends Composer<_$ProgressDb, $BlockStateTable> {
  $$BlockStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get blockNo => $composableBuilder(
    column: $table.blockNo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stage => $composableBuilder(
    column: $table.stage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BlockStateTableOrderingComposer
    extends Composer<_$ProgressDb, $BlockStateTable> {
  $$BlockStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get blockNo => $composableBuilder(
    column: $table.blockNo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stage => $composableBuilder(
    column: $table.stage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BlockStateTableAnnotationComposer
    extends Composer<_$ProgressDb, $BlockStateTable> {
  $$BlockStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get blockNo =>
      $composableBuilder(column: $table.blockNo, builder: (column) => column);

  GeneratedColumn<String> get stage =>
      $composableBuilder(column: $table.stage, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );
}

class $$BlockStateTableTableManager
    extends
        RootTableManager<
          _$ProgressDb,
          $BlockStateTable,
          BlockStateData,
          $$BlockStateTableFilterComposer,
          $$BlockStateTableOrderingComposer,
          $$BlockStateTableAnnotationComposer,
          $$BlockStateTableCreateCompanionBuilder,
          $$BlockStateTableUpdateCompanionBuilder,
          (
            BlockStateData,
            BaseReferences<_$ProgressDb, $BlockStateTable, BlockStateData>,
          ),
          BlockStateData,
          PrefetchHooks Function()
        > {
  $$BlockStateTableTableManager(_$ProgressDb db, $BlockStateTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BlockStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BlockStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BlockStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> blockNo = const Value.absent(),
                Value<String> stage = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BlockStateCompanion(
                blockNo: blockNo,
                stage: stage,
                status: status,
                completedAt: completedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int blockNo,
                required String stage,
                Value<String> status = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BlockStateCompanion.insert(
                blockNo: blockNo,
                stage: stage,
                status: status,
                completedAt: completedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BlockStateTableProcessedTableManager =
    ProcessedTableManager<
      _$ProgressDb,
      $BlockStateTable,
      BlockStateData,
      $$BlockStateTableFilterComposer,
      $$BlockStateTableOrderingComposer,
      $$BlockStateTableAnnotationComposer,
      $$BlockStateTableCreateCompanionBuilder,
      $$BlockStateTableUpdateCompanionBuilder,
      (
        BlockStateData,
        BaseReferences<_$ProgressDb, $BlockStateTable, BlockStateData>,
      ),
      BlockStateData,
      PrefetchHooks Function()
    >;
typedef $$StageProgressTableCreateCompanionBuilder =
    StageProgressCompanion Function({
      required String stage,
      Value<int> lapCount,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$StageProgressTableUpdateCompanionBuilder =
    StageProgressCompanion Function({
      Value<String> stage,
      Value<int> lapCount,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$StageProgressTableFilterComposer
    extends Composer<_$ProgressDb, $StageProgressTable> {
  $$StageProgressTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get stage => $composableBuilder(
    column: $table.stage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lapCount => $composableBuilder(
    column: $table.lapCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StageProgressTableOrderingComposer
    extends Composer<_$ProgressDb, $StageProgressTable> {
  $$StageProgressTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get stage => $composableBuilder(
    column: $table.stage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lapCount => $composableBuilder(
    column: $table.lapCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StageProgressTableAnnotationComposer
    extends Composer<_$ProgressDb, $StageProgressTable> {
  $$StageProgressTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get stage =>
      $composableBuilder(column: $table.stage, builder: (column) => column);

  GeneratedColumn<int> get lapCount =>
      $composableBuilder(column: $table.lapCount, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$StageProgressTableTableManager
    extends
        RootTableManager<
          _$ProgressDb,
          $StageProgressTable,
          StageProgressData,
          $$StageProgressTableFilterComposer,
          $$StageProgressTableOrderingComposer,
          $$StageProgressTableAnnotationComposer,
          $$StageProgressTableCreateCompanionBuilder,
          $$StageProgressTableUpdateCompanionBuilder,
          (
            StageProgressData,
            BaseReferences<
              _$ProgressDb,
              $StageProgressTable,
              StageProgressData
            >,
          ),
          StageProgressData,
          PrefetchHooks Function()
        > {
  $$StageProgressTableTableManager(_$ProgressDb db, $StageProgressTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StageProgressTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StageProgressTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StageProgressTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> stage = const Value.absent(),
                Value<int> lapCount = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StageProgressCompanion(
                stage: stage,
                lapCount: lapCount,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String stage,
                Value<int> lapCount = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StageProgressCompanion.insert(
                stage: stage,
                lapCount: lapCount,
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

typedef $$StageProgressTableProcessedTableManager =
    ProcessedTableManager<
      _$ProgressDb,
      $StageProgressTable,
      StageProgressData,
      $$StageProgressTableFilterComposer,
      $$StageProgressTableOrderingComposer,
      $$StageProgressTableAnnotationComposer,
      $$StageProgressTableCreateCompanionBuilder,
      $$StageProgressTableUpdateCompanionBuilder,
      (
        StageProgressData,
        BaseReferences<_$ProgressDb, $StageProgressTable, StageProgressData>,
      ),
      StageProgressData,
      PrefetchHooks Function()
    >;

class $ProgressDbManager {
  final _$ProgressDb _db;
  $ProgressDbManager(this._db);
  $$WordProgressTableTableManager get wordProgress =>
      $$WordProgressTableTableManager(_db, _db.wordProgress);
  $$BlockStateTableTableManager get blockState =>
      $$BlockStateTableTableManager(_db, _db.blockState);
  $$StageProgressTableTableManager get stageProgress =>
      $$StageProgressTableTableManager(_db, _db.stageProgress);
}
