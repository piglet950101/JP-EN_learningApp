// progress.db — writable, on-device, holds user learning state.
// Schema is small and exact to the spec: word_progress (for 「初回OKを除く」),
// block_state (range-select colors), stage_progress (lap_count for ★ rating).

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'progress_db.g.dart';

class WordProgress extends Table {
  @override
  String get tableName => 'word_progress';

  IntColumn get wordId => integer()();
  TextColumn get stage => text()();
  TextColumn get firstRoundResult => text().nullable()(); // 'ok' | 'recheck' | null
  TextColumn get lastResult => text().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {wordId, stage};
}

class BlockState extends Table {
  @override
  String get tableName => 'block_state';

  IntColumn get blockNo => integer()();
  TextColumn get stage => text()();
  TextColumn get status =>
      text().withDefault(const Constant('unlearned'))(); // unlearned | completed
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {blockNo, stage};
}

class StageProgress extends Table {
  @override
  String get tableName => 'stage_progress';

  TextColumn get stage => text()();
  IntColumn get lapCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {stage};
}

@DriftDatabase(tables: [WordProgress, BlockState, StageProgress])
class ProgressDb extends _$ProgressDb {
  ProgressDb(super.e);

  /// Production database: a file under the platform's app-documents dir.
  ProgressDb.openDefault() : super(_openDefault());

  /// In-memory database for tests.
  ProgressDb.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openDefault() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'progress.db'));
    return NativeDatabase.createInBackground(file);
  });
}
