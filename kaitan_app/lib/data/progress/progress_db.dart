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

/// Global app state — single-row table (id=1). Added in schemaVersion 2
/// (2026-08-03) to hold the trial-unlock timestamp.
class AppState extends Table {
  @override
  String get tableName => 'app_state';

  IntColumn get id => integer().withDefault(const Constant(1))();
  // epoch seconds; null means the app is still in trial (未アンロック) mode.
  IntColumn get unlockedAt => integer().nullable()();
  // HMAC of the unlock code that was accepted (audit trail, not a re-verify key).
  TextColumn get unlockCodeHash => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [WordProgress, BlockState, StageProgress, AppState])
class ProgressDb extends _$ProgressDb {
  ProgressDb(super.e);

  /// Production database: a file under the platform's app-documents dir.
  ProgressDb.openDefault() : super(_openDefault());

  /// In-memory database for tests.
  ProgressDb.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await into(appState).insert(
            AppStateCompanion.insert(id: const Value(1)),
          );
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(appState);
            await into(appState).insert(
              AppStateCompanion.insert(id: const Value(1)),
            );
          }
        },
      );
}

LazyDatabase _openDefault() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'progress.db'));
    return NativeDatabase.createInBackground(file);
  });
}
