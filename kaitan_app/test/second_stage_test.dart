// Second Stage — data-layer tests (relation categorization + repository
// integrity against the bundled second_stage.json).

import 'package:flutter_test/flutter_test.dart';

import 'package:kaitan/data/second_stage.dart';

void main() {
  group('SsRelationCategory.categoryOf', () {
    test('recognises bare base codes', () {
      expect(SsRelationCategory.categoryOf('類'), '類');
      expect(SsRelationCategory.categoryOf('反'), '反');
      expect(SsRelationCategory.categoryOf('意'), '意');
      expect(SsRelationCategory.categoryOf('セ'), 'セ');
    });

    test('recognises "code + space + free text" pattern', () {
      expect(SsRelationCategory.categoryOf('意 racism'), '意');
      expect(SsRelationCategory.categoryOf('セ 彼に留学するように勧める'), 'セ');
      expect(SsRelationCategory.categoryOf('法 without と instead of の違い'), '法');
    });

    test('recognises "code + fullwidth space" as well', () {
      expect(SsRelationCategory.categoryOf('意　fertilizer'), '意');
    });

    test('recognises number-suffixed forms 意2 / 意３ / 名２', () {
      expect(SsRelationCategory.categoryOf('意2'), '意');
      expect(SsRelationCategory.categoryOf('意３'), '意');
      expect(SsRelationCategory.categoryOf('名２'), '名');
      expect(SsRelationCategory.categoryOf('類2'), '類');
    });

    test('recognises parenthetical forms 意３（名２，他１）', () {
      expect(SsRelationCategory.categoryOf('意３（名２，他１）'), '意');
      expect(SsRelationCategory.categoryOf('意(2)'), '意');
      expect(SsRelationCategory.categoryOf('形（名）'), '形');
    });

    test('returns null for unrecognised free-form values', () {
      expect(SsRelationCategory.categoryOf('全く別の記述'), isNull);
      expect(SsRelationCategory.categoryOf(''), isNull);
      expect(SsRelationCategory.categoryOf('   '), isNull);
    });
  });

  group('SecondStageRepository (bundled data)', () {
    late SecondStageRepository repo;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      repo = await SecondStageRepository.loadFromAsset();
    });

    test('bundled data has ~1,973 entries across blocks 1..46', () {
      expect(repo.count, greaterThanOrEqualTo(1900));
      expect(repo.count, lessThanOrEqualTo(2100));
      final blocks = repo.allBlocks();
      expect(blocks.first, 1);
      expect(blocks.last, 46);
      expect(blocks.length, 46);
    });

    test('block 47 (医系) has no SS entries by design', () {
      expect(repo.hasEntriesForBlock(47), isFalse);
      expect(repo.byBlock(47), isEmpty);
    });

    test('all entries reference a valid Phase 1 word_id (1..2201)', () {
      // Spot check: sample first 100 entries.
      final all = <SecondStageEntry>[];
      for (var b = 1; b <= 46; b++) {
        all.addAll(repo.byBlock(b).take(3));
      }
      for (final e in all) {
        expect(e.wordId, inInclusiveRange(1, 2201),
            reason: 'entry ${e.id}: word_id ${e.wordId} out of range');
      }
    });

    test('same word carries multiple entries as designed (diversity)', () {
      final entries = repo.byWordId(97); // diversity
      expect(entries.length, greaterThan(1),
          reason: 'diversity should have ≥1 SS entry');
    });

    test('a word without SS entries returns []', () {
      // Pick an id known to have no SS drills (890 base words fall here).
      // Word id 2 (scatter) — no SS entries per pilot data.
      final entries = repo.byWordId(2);
      expect(entries, isEmpty);
      expect(repo.hasEntriesForWord(2), isFalse);
    });
  });
}
