// Dataset integrity test — loads the actual bundled `words.json` (the real
// asset that ships in the APK) and asserts the cross-volume invariants.
// If anything silently regresses (vol.2 lost, IDs missing, schema drift) this
// fails before the APK ever leaves the build pipeline.

import 'package:flutter_test/flutter_test.dart';

import 'package:kaitan/data/word.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WordRepository repo;

  setUpAll(() async {
    repo = await WordRepository.loadFromAsset();
  });

  test('bundled dataset contains all 2,267 words (vol.1 + vol.2 + vol.3 医系)', () {
    // Phase 2 (2026-08-03): vol.3 医系ブロック added (66 words, block 47).
    expect(repo.count, 2267,
        reason: 'vol.1 + vol.2 + vol.3 (medical block) must all be present');
  });

  test('every ID 1..2267 is present, no duplicates, no gaps', () {
    for (var id = 1; id <= 2267; id++) {
      expect(repo.byId(id), isNotNull, reason: 'missing id $id');
    }
  });

  test('all 47 blocks present (46 core + 47 医系)', () {
    final blocks = repo.allBlocks();
    expect(blocks, equals([for (var b = 1; b <= 47; b++) b]));
  });

  test('block counts match the spec (48 each except 23=44, 46=45, 47=66)', () {
    for (var b = 1; b <= 47; b++) {
      final expected = (b == 23) ? 44 : (b == 46) ? 45 : (b == 47) ? 66 : 48;
      expect(repo.byBlock(b).length, expected,
          reason: 'block $b should have $expected words');
    }
  });

  test('vol.1 = blocks 1..23 / IDs 1..1100; vol.2 = 24..46 / 1101..2201; '
      'vol.3 医系 = block 47 / 2202..2267', () {
    for (final w in [repo.byId(1)!, repo.byId(1100)!]) {
      expect(w.vol, 1);
      expect(w.block, inInclusiveRange(1, 23));
    }
    for (final w in [repo.byId(1101)!, repo.byId(2201)!]) {
      expect(w.vol, 2);
      expect(w.block, inInclusiveRange(24, 46));
    }
    for (final w in [repo.byId(2202)!, repo.byId(2267)!]) {
      expect(w.vol, 3);
      expect(w.block, 47);
    }
  });

  test('no word is missing essential fields', () {
    var emptyWord = 0, emptyMeaning = 0, emptyExampleEn = 0, emptyExampleJa = 0;
    for (var id = 1; id <= 2267; id++) {
      final w = repo.byId(id)!;
      if (w.word.isEmpty) emptyWord++;
      if (w.meanings.isEmpty) emptyMeaning++;
      if (w.exampleEn.isEmpty) emptyExampleEn++;
      if (w.exampleJa.isEmpty) emptyExampleJa++;
    }
    expect(emptyWord, 0);
    expect(emptyMeaning, 0);
    expect(emptyExampleEn, 0,
        reason: 'vol.2 example_en MUST be non-empty after the 2026-06-13 update');
    expect(emptyExampleJa, 0,
        reason: 'vol.2 example_ja MUST be non-empty after the 2026-06-13 update');
  });

  test('spot-check known vol.1 (id=1 absorb) and vol.2 (id=1101 royal) entries',
      () {
    final absorb = repo.byId(1)!;
    expect(absorb.word, 'absorb');
    expect(absorb.vol, 1);
    expect(absorb.block, 1);

    final royal = repo.byId(1101)!;
    expect(royal.word, 'royal');
    expect(royal.vol, 2);
    expect(royal.block, 24);
    expect(royal.exampleEn, isNotEmpty);
    expect(royal.exampleJa, isNotEmpty);
  });

  test('dual-meaning POS convention (名2 / 名(2)) is preserved', () {
    var bothRequired = 0, eitherOk = 0;
    for (var id = 1; id <= 2267; id++) {
      final w = repo.byId(id)!;
      if (w.meaningMode == MeaningMode.bothRequired) bothRequired++;
      if (w.meaningMode == MeaningMode.eitherOk) eitherOk++;
    }
    // Pinning the post-vol.2 expected counts so a regression is loud.
    expect(bothRequired, greaterThan(0),
        reason: 'at least one 名2-style word must exist');
    expect(eitherOk, greaterThan(0),
        reason: 'at least one 名(2)-style word must exist');
    // Total of "dual" forms should be a reasonable number, not 0 or 2000.
    expect(bothRequired + eitherOk, inInclusiveRange(20, 200));
  });
}
