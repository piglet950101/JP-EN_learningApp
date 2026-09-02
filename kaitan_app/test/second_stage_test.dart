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

  // ── ゴロ echo markings (client 2026-08-24 ③) ────────────────────────
  //
  // The bold run of each mnemonic is recorded in data because it is a pun on
  // the sound and cannot be derived from the characters. Re-running the
  // import without apply_mnemonic_echo.py would silently drop the lot, and
  // nothing on screen would look broken — it would just quietly stop obeying
  // the client's rule. These pin it.

  group('mnemonic echo markings', () {
    test('the marked runs are actually present in their meaning', () async {
      final repo = await SecondStageRepository.loadFromAsset();
      var marked = 0;
      for (final e in repo.all) {
        if (e.mnemonicEcho.isEmpty) continue;
        marked++;
        final meaning = e.answerMeaning ?? '';
        expect(meaning, contains('「'),
            reason: '${e.wordId} ${e.answer}: marked but has no ゴロ');
        for (final n in e.mnemonicEcho) {
          expect(meaning, contains(n),
              reason: '${e.wordId} ${e.answer}: "$n" not in meaning');
        }
      }
      expect(marked, greaterThanOrEqualTo(80),
          reason: 'echo markings look dropped — did the import re-run '
              'without apply_mnemonic_echo.py?');
    });

    test("the client's worked example is marked as they described", () async {
      final repo = await SecondStageRepository.loadFromAsset();
      final opaque = repo.all.firstWhere(
          (e) => e.wordId == 7 && e.answer == 'opaque');
      expect(opaque.answerMeaning, '不透明な「OPECは不透明」');
      expect(opaque.mnemonicEcho, ['OPEC']);
    });

    test('grammar notes quoting Japanese are left unmarked', () async {
      final repo = await SecondStageRepository.loadFromAsset();
      for (final e in repo.all.where((e) => e.wordId == 1185)) {
        expect(e.mnemonicEcho, isEmpty,
            reason: '${e.answer}: 「…」は語法の注記であってゴロではない');
      }
    });
  });

  // ── Words the client asked to remove entirely ──────────────────────
  //
  // Fourteen words are mapped to an EMPTY override, which means "drop every
  // row" — 0269 defect, 1304 instead and twelve others from the 2026-08-19
  // review. An empty entry looks like junk in the override file and invites
  // tidying; deleting one silently brings its rows back, and nothing on
  // screen looks broken because the rows simply reappear.

  test('words the client removed stay removed', () async {
    final repo = await SecondStageRepository.loadFromAsset();
    const removed = [269, 469, 564, 620, 785, 870, 992, 1142, 1304, 1341,
                     1386, 1926, 2070, 2121];
    for (final id in removed) {
      expect(repo.byWordId(id), isEmpty,
          reason: 'word $id was deleted by the client but has rows again — '
              'was its empty override removed from ss_overrides.json?');
    }
  });

  test('mnemonic_break marks a ゴロ that has nothing to emphasise', () async {
    final repo = await SecondStageRepository.loadFromAsset();
    // 1560 collapse: 「滑り落ちる」が語源 is etymology, not a pun, so no run
    // echoes the English — but the client wants the ゴロ treatment anyway.
    final lapse = repo.all.firstWhere(
        (e) => e.wordId == 1560 && e.relation.startsWith('意 ２～３ lapse'));
    expect(lapse.mnemonicEcho, isEmpty);
    expect(lapse.mnemonicBreak, isTrue);
    expect(lapse.answerMeaning, '「滑り落ちる」が語源');
  });
}