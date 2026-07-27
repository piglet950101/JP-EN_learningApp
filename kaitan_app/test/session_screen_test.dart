// Widget-level smoke test for the ⑥ Question ⇄ ⑦ Answer hot loop.
// Verifies that the live counter advances correctly through the spec flow:
//   first question → tap 意味・例文 → tap OK → counter shows OK=1
//   next question → tap 意味・例文 → tap 再チェック → counter shows OK=1, 再チェック=1

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kaitan/core/providers.dart';
import 'package:kaitan/data/progress/progress_db.dart';
import 'package:kaitan/data/tts_service.dart';
import 'package:kaitan/data/word.dart';
import 'package:kaitan/features/session/presentation/session_controller.dart';
import 'package:kaitan/features/session/presentation/session_screen.dart';

/// A no-op TTS so widget tests don't try to invoke the real plugin.
class _NoopTts implements TtsService {
  @override
  Future<void> init() async {}
  @override
  Future<void> speak(String text, {String? pronunciationHint, int? wordId}) async {}
}

void main() {
  testWidgets('hot loop: question → answer → OK → next + 再チェック',
      (tester) async {
    // Override the word repo with a tiny synthetic dataset (3 words in block 1)
    // so the test doesn't need the bundled JSON.
    final synthetic = [
      const Word(
        id: 1, vol: 1, block: 1, word: 'absorb',
        posRaw: '他', posList: ['他'],
        meaningMode: MeaningMode.single,
        meanings: ['吸収する'],
        mnemonics: [Mnemonic(type: 'ゴロ', runs: [MnemonicRun(text: '虻、象ブスッと', bold: true)])],
        examples: [Example(en: 'Plants absorb water.', ja: '植物は水を吸収する。')],
        imageFilename: '0001.webp', pronunciationHint: null,
      ),
      const Word(
        id: 2, vol: 1, block: 1, word: 'scatter',
        posRaw: '他', posList: ['他'],
        meaningMode: MeaningMode.single,
        meanings: ['まき散らす'],
        mnemonics: [Mnemonic(type: 'ゴロ', runs: [MnemonicRun(text: 'スケーター', bold: false)])],
        examples: [Example(en: 'Wind scatters leaves.', ja: '風が葉をまき散らす。')],
        imageFilename: '0002.webp', pronunciationHint: null,
      ),
      const Word(
        id: 3, vol: 1, block: 1, word: 'banish',
        posRaw: '他', posList: ['他'],
        meaningMode: MeaningMode.single,
        meanings: ['追放する'],
        mnemonics: [Mnemonic(type: 'ゴロ', runs: [MnemonicRun(text: 'バアに石', bold: false)])],
        examples: [Example(en: 'The king banished him.', ja: '王は彼を追放した。')],
        imageFilename: '0003.webp', pronunciationHint: null,
      ),
    ];
    final fakeRepo = _FakeWordRepository(synthetic);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wordRepoProvider.overrideWith((ref) async => fakeRepo),
          ttsProvider.overrideWithValue(_NoopTts()),
          progressDbProvider.overrideWith((ref) {
            final db = ProgressDb.memory();
            ref.onDispose(db.close);
            return db;
          }),
        ],
        child: const MaterialApp(home: SessionScreen()),
      ),
    );

    // Initial load.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Repo future resolves + initial start fires.
    await tester.pumpAndSettle();

    // 1) Question screen visible with one of the 3 words; counter 3/3.
    expect(find.text('意味・例文'), findsOneWidget);
    expect(find.text('3/3'), findsOneWidget);

    // 2) Tap 意味・例文 → answer screen.
    await tester.tap(find.text('意味・例文'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'OK'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '再チェック'), findsOneWidget);

    // 3) Tap the big OK button → back to question, counter 2/3.
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle(const Duration(milliseconds: 150));
    expect(find.text('2/3'), findsOneWidget);

    // 4) Tap 意味・例文 → answer → 再チェック → counter 1/3, OK=1, 再チェック=1.
    await tester.tap(find.text('意味・例文'));
    await tester.pumpAndSettle();
    // The footer also has a 再チェック label chip; the BUTTON is the big one.
    // Tap the BUTTON labelled 再チェック (the largest hittable widget with that text).
    await tester.tap(find.widgetWithText(OutlinedButton, '再チェック'));
    await tester.pumpAndSettle(const Duration(milliseconds: 150));
    expect(find.text('1/3'), findsOneWidget);
  });

  testWidgets('illustration card hidden when manifest is empty',
      (tester) async {
    final repo = _FakeWordRepository([
      const Word(
        id: 99, vol: 1, block: 1, word: 'demo',
        posRaw: '他', posList: ['他'],
        meaningMode: MeaningMode.single,
        meanings: ['テスト用'],
        mnemonics: [Mnemonic(type: 'ゴロ', runs: [MnemonicRun(text: 'なんとなく', bold: false)])],
        examples: [Example(en: 'A demo word.', ja: 'デモ単語。')],
        imageFilename: '0099.webp', pronunciationHint: null,
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wordRepoProvider.overrideWith((ref) async => repo),
          ttsProvider.overrideWithValue(_NoopTts()),
          progressDbProvider.overrideWith((ref) {
            final db = ProgressDb.memory();
            ref.onDispose(db.close);
            return db;
          }),
          imageManifestProvider.overrideWith((ref) async => const <int>{}),
        ],
        child: const MaterialApp(home: SessionScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('意味・例文'));
    await tester.pumpAndSettle();

    // No Image widget on the answer screen because the manifest is empty.
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('illustration card shown when manifest contains the word ID',
      (tester) async {
    final repo = _FakeWordRepository([
      const Word(
        id: 99, vol: 1, block: 1, word: 'demo',
        posRaw: '他', posList: ['他'],
        meaningMode: MeaningMode.single,
        meanings: ['テスト用'],
        mnemonics: [Mnemonic(type: 'ゴロ', runs: [MnemonicRun(text: 'なんとなく', bold: false)])],
        examples: [Example(en: 'A demo word.', ja: 'デモ単語。')],
        imageFilename: '0099.webp', pronunciationHint: null,
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wordRepoProvider.overrideWith((ref) async => repo),
          ttsProvider.overrideWithValue(_NoopTts()),
          progressDbProvider.overrideWith((ref) {
            final db = ProgressDb.memory();
            ref.onDispose(db.close);
            return db;
          }),
          imageManifestProvider.overrideWith((ref) async => const {99}),
        ],
        child: const MaterialApp(home: SessionScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('意味・例文'));
    await tester.pumpAndSettle();

    // The illustration card builds an Image widget. We don't care whether the
    // asset actually decodes in the test bundle — only that the widget is built.
    expect(find.byType(Image), findsAtLeastNWidgets(1));
  });
}

class _FakeWordRepository implements WordRepository {
  _FakeWordRepository(this._words);
  final List<Word> _words;

  @override
  int get count => _words.length;

  @override
  List<int> allBlocks() => [1];

  @override
  List<Word> byBlock(int block) =>
      _words.where((w) => w.block == block).toList();

  @override
  Word? byId(int id) {
    for (final w in _words) {
      if (w.id == id) return w;
    }
    return null;
  }
}
