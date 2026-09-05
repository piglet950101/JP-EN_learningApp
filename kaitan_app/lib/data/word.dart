// Word model + repository. For the MVP demo, words are loaded from the
// bundled JSON asset (`assets/content/words_vol1.json`) produced by
// `tool/import_excel.py`. Later this will be replaced by a drift `content.db`.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

enum MeaningMode { single, bothRequired, eitherOk }

MeaningMode _parseMode(String s) => switch (s) {
      'both_required' => MeaningMode.bothRequired,
      'either_ok' => MeaningMode.eitherOk,
      _ => MeaningMode.single,
    };

/// A single styled run within a mnemonic — text + bold flag.
/// Bold is sourced from the Excel's character-level formatting (the
/// pronunciation-linked portion is bold per spec v1.2 ⑤).
class MnemonicRun {
  final String text;
  final bool bold;
  const MnemonicRun({required this.text, required this.bold});

  factory MnemonicRun.fromJson(Map<String, dynamic> j) =>
      MnemonicRun(text: j['text'] ?? '', bold: j['bold'] == true);
}

class Mnemonic {
  final String type; // ゴロ / 語源 / カタカナ / セットフレーズ / イメージ
  final List<MnemonicRun> runs;
  const Mnemonic({required this.type, required this.runs});

  /// Flattened plain text — handy for fallback / search / tests.
  String get text => runs.map((r) => r.text).join();

  factory Mnemonic.fromJson(Map<String, dynamic> j) {
    final rawRuns = (j['runs'] as List?) ?? const [];
    final runs = rawRuns
        .map((e) => MnemonicRun.fromJson(e as Map<String, dynamic>))
        .toList();
    // Backwards-compat: older JSON might still carry "text".
    if (runs.isEmpty && j['text'] is String && (j['text'] as String).isNotEmpty) {
      return Mnemonic(
        type: j['type'] ?? '',
        runs: [MnemonicRun(text: j['text'] as String, bold: false)],
      );
    }
    return Mnemonic(type: j['type'] ?? '', runs: runs);
  }
}

/// One (English, Japanese) example pair shown on the answer screen.
class Example {
  final String en;
  final String ja;
  const Example({required this.en, required this.ja});

  factory Example.fromJson(Map<String, dynamic> j) =>
      Example(en: j['en'] ?? '', ja: j['ja'] ?? '');
}

class Word {
  final int id;          // 見出し№
  final int vol;         // 1 or 2
  final int block;       // 1..46
  final String word;
  final String posRaw;   // raw POS string ("他", "形(2)", etc.)
  final List<String> posList; // base POS chars
  final MeaningMode meaningMode;
  final List<String> meanings;
  final List<Mnemonic> mnemonics;
  /// Ordered list of example pairs — typically 0, 1, or 2 entries.
  /// Spec 2026-06-30: when 2 are present, show them stacked on the answer screen.
  final List<Example> examples;
  final String imageFilename;  // e.g. "0001.webp"
  final String? pronunciationHint;
  /// Second Stage must not show this word's meaning under the headword. Most
  /// cases the app derives; this covers the ones it cannot (0572 disagree is
  /// asked as 彼と意見が合わない but means 不賛成である).
  final bool hideMeaningInSs;

  const Word({
    required this.id,
    required this.vol,
    required this.block,
    required this.word,
    required this.posRaw,
    required this.posList,
    required this.meaningMode,
    required this.meanings,
    required this.mnemonics,
    required this.examples,
    required this.imageFilename,
    required this.pronunciationHint,
    this.hideMeaningInSs = false,
  });

  // Back-compat accessors so existing callers keep working.
  String get exampleEn => examples.isNotEmpty ? examples.first.en : '';
  String get exampleJa => examples.isNotEmpty ? examples.first.ja : '';

  factory Word.fromJson(Map<String, dynamic> j) {
    final rawEx = (j['examples'] as List?) ?? const [];
    final examples = rawEx
        .map((e) => Example.fromJson(e as Map<String, dynamic>))
        .where((e) => e.en.isNotEmpty || e.ja.isNotEmpty)
        .toList();
    // Back-compat: fall back to flat example_en/example_ja when the JSON
    // hasn't been regenerated with the new `examples` array yet.
    if (examples.isEmpty) {
      final en = j['example_en'] as String? ?? '';
      final ja = j['example_ja'] as String? ?? '';
      if (en.isNotEmpty || ja.isNotEmpty) {
        examples.add(Example(en: en, ja: ja));
      }
    }
    return Word(
      id: j['id'] as int,
      vol: j['vol'] as int,
      block: j['block'] as int,
      word: j['word'] as String? ?? '',
      posRaw: j['pos_raw'] as String? ?? '',
      posList: (j['pos_list'] as List? ?? const []).cast<String>(),
      meaningMode: _parseMode(j['meaning_mode'] as String? ?? 'single'),
      meanings: (j['meanings'] as List? ?? const []).cast<String>(),
      mnemonics: (j['mnemonics'] as List? ?? const [])
          .map((e) => Mnemonic.fromJson(e as Map<String, dynamic>))
          .toList(),
      examples: examples,
      imageFilename: j['image_filename'] as String? ?? '',
      pronunciationHint: j['pronunciation_hint'] as String?,
      hideMeaningInSs: (j['hide_meaning_in_ss'] ?? false) as bool,
    );
  }
}

class WordRepository {
  WordRepository._(this._byId, this._byBlock);
  final Map<int, Word> _byId;
  final Map<int, List<Word>> _byBlock;

  static Future<WordRepository> loadFromAsset(
      {String path = 'assets/content/words.json'}) async {
    final raw = await rootBundle.loadString(path);
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final words = (j['words'] as List)
        .map((e) => Word.fromJson(e as Map<String, dynamic>))
        .toList();
    final byId = {for (final w in words) w.id: w};
    final byBlock = <int, List<Word>>{};
    for (final w in words) {
      byBlock.putIfAbsent(w.block, () => []).add(w);
    }
    return WordRepository._(byId, byBlock);
  }

  Word? byId(int id) => _byId[id];
  List<Word> byBlock(int block) => List.unmodifiable(_byBlock[block] ?? const []);
  List<int> allBlocks() => (_byBlock.keys.toList()..sort());
  int get count => _byId.length;
}
