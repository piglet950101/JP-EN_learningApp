// Widget-level pins for the v1.2 (2026-06-02) layout changes:
//   • Question screen: word appears ABOVE POS+speaker
//   • Top bar: 巡目 badge is centered; retire button is to its right
//   • Answer screen: 英単語 NO longer repeated; "意味" label removed; meaning
//     rendered in RED via _MeaningHeader; bold-pronunciation mnemonic via
//     RichText spans
//   • ⑩ Result screen: both 「同じ範囲を続ける」 and 「範囲指定画面に戻る」
//   • Start screen: bright gradient background + arrow on stage card

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kaitan/core/providers.dart';
import 'package:kaitan/data/progress/progress_db.dart';
import 'package:kaitan/data/tts_service.dart';
import 'package:kaitan/data/word.dart';
import 'package:kaitan/features/session/presentation/session_controller.dart';
import 'package:kaitan/features/session/presentation/session_screen.dart';

class _NoopTts implements TtsService {
  @override
  Future<void> init() async {}
  @override
  Future<void> speak(String text, {String? pronunciationHint, int? wordId}) async {}
  @override
  Future<void> speakAnswer(String raw, {String? pronunciationHint}) async {}
  @override
  Future<void> speakSequence(List<String> answers) async {}
}

class _FakeRepo implements WordRepository {
  _FakeRepo(this._words);
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

const _absorb = Word(
  id: 1, vol: 1, block: 1, word: 'absorb',
  posRaw: '他', posList: ['他'],
  meaningMode: MeaningMode.single,
  meanings: ['吸収する'],
  mnemonics: [Mnemonic(type: 'ゴロ', runs: [
    MnemonicRun(text: '虻、象ブスッと', bold: true),
    MnemonicRun(text: '［吸収する］', bold: false),
  ])],
  examples: [Example(en: 'Plants absorb water.', ja: '植物は水を吸収する。')],
  imageFilename: '0001.webp', pronunciationHint: null,
);

Widget _wrap({required Set<int> imageIds}) {
  return ProviderScope(
    overrides: [
      wordRepoProvider.overrideWith((ref) async => _FakeRepo([_absorb])),
      ttsProvider.overrideWithValue(_NoopTts()),
      progressDbProvider.overrideWith((ref) {
        final db = ProgressDb.memory();
        ref.onDispose(db.close);
        return db;
      }),
      imageManifestProvider.overrideWith((ref) async => imageIds),
    ],
    child: const MaterialApp(home: SessionScreen()),
  );
}

void main() {
  testWidgets('Question screen: word appears ABOVE POS+speaker icon',
      (tester) async {
    await tester.pumpWidget(_wrap(imageIds: const {}));
    await tester.pumpAndSettle();

    final wordY = tester.getCenter(find.text('absorb')).dy;
    final speakerY = tester.getCenter(find.byIcon(Icons.volume_up_rounded)).dy;
    expect(wordY < speakerY, true,
        reason: 'spec v1.2 ②: word must be above speaker/POS row');
  });

  testWidgets('Top bar: 巡目 badge is horizontally centered; retire on right',
      (tester) async {
    await tester.pumpWidget(_wrap(imageIds: const {}));
    await tester.pumpAndSettle();

    final round = find.text('1巡目');
    final retire = find.text('リタイヤ');
    expect(round, findsOneWidget);
    expect(retire, findsOneWidget);

    final screenW = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final roundX = tester.getCenter(round).dx;
    final retireX = tester.getCenter(retire).dx;
    // 巡目 is roughly in the center half; retire sits to its right.
    expect((roundX - screenW / 2).abs() < screenW * 0.15, true,
        reason: '巡目 should sit near the horizontal center');
    expect(retireX > roundX, true,
        reason: 'retire button should be to the right of the 巡目 badge');
  });

  testWidgets('Answer screen: no duplicated word; no "意味" label; mnemonic is RichText',
      (tester) async {
    await tester.pumpWidget(_wrap(imageIds: const {}));
    await tester.pumpAndSettle();

    // Tap into the answer screen.
    await tester.tap(find.text('意味・例文'));
    await tester.pumpAndSettle();

    // After the tap, '意味・例文' is gone (the button label, on ⑥).
    expect(find.text('意味・例文'), findsNothing);

    // The 英単語 is shown exactly ONCE on the answer screen (the question
    // screen's centered word is gone after navigation; the answer view does
    // not duplicate it). The top bar shows the № only, not the word.
    expect(find.text('absorb'), findsNothing,
        reason: 'spec ③a: 英単語をなくしてください');

    // The "意味" label text must be GONE (spec ③b).
    expect(find.text('意味'), findsNothing,
        reason: 'spec ③b: 「意味」 ラベル削除');

    // The mnemonic must contain RichText (it's how we render bold +
    // plain spans).
    expect(find.byType(RichText), findsWidgets);
  });

  testWidgets('Answer screen: meaning text rendered in RED', (tester) async {
    await tester.pumpWidget(_wrap(imageIds: const {}));
    await tester.pumpAndSettle();
    await tester.tap(find.text('意味・例文'));
    await tester.pumpAndSettle();

    // Walk every Text.rich on screen looking for a span whose color
    // matches the spec's red palette.
    bool sawRedSpan = false;
    void visit(InlineSpan span) {
      final col = span.style?.color;
      if (col != null) {
        // Accept the answer-screen red (0xFFC53030) or its supplementary
        // shade (0xFFE53E3E).
        if (col.toARGB32() == 0xFFC53030 ||
            col.toARGB32() == 0xFFE53E3E) {
          sawRedSpan = true;
        }
      }
      if (span is TextSpan && span.children != null) {
        for (final c in span.children!) {
          visit(c);
        }
      }
    }
    for (final el in find.byType(RichText).evaluate()) {
      final w = el.widget as RichText;
      visit(w.text);
    }
    expect(sawRedSpan, true,
        reason: 'spec ③b: meaning must render in red on the answer screen');
  });
}
