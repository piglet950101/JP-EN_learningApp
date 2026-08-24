// Second Stage — relational-drill data model + repository.
//
// Loads `assets/content/second_stage.json` (produced by
// `tool/import_second_stage.py`) into memory once at app start.
// Every SS entry is anchored to a Phase-1 word by `word_id`; a single
// headword typically carries multiple entries (類/反/名/形/意/セ/etc.),
// and the ⑥' Second Stage 問題 screen renders them together as a vertical
// list of prompts per headword.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Base categories the client uses as free-form prefixes on the `relation`
/// column. UI can use these to render icons/color; anything not matched is
/// treated as free-form text and shown verbatim (e.g. "意 racism",
/// "セ 彼に留学するように勧める", "意３（名２，他１）").
class SsRelationCategory {
  static const synonym = '類';
  static const antonym = '反';
  static const preposition = '前';
  static const idiom = '熟';
  static const conjugation = '活';
  static const posMarker = '品';
  static const usage = '法';
  static const plural = '複';
  static const homophone = '同音';
  static const setPhrase = 'セ';
  static const meaning = '意';
  static const nounForm = '名';
  static const adjForm = '形';
  static const advForm = '副';
  static const verbForm = '動';

  static const all = <String>[
    synonym, antonym, preposition, idiom, conjugation, posMarker,
    usage, plural, homophone, setPhrase, meaning,
    nounForm, adjForm, advForm, verbForm,
  ];

  /// Detects the base code that a raw `relation` string starts with.
  /// Returns null when the relation is fully free-form (rendered verbatim).
  ///
  /// Rule: the string must START with one of the base codes. This is
  /// intentional — the client uses compound forms like `類義語とその名詞`
  /// (starts with `類`, means "synonyms and their nouns"), `意 racism`,
  /// `意３（名２，他１）`, `名詞とその複数形` — in every observed case the
  /// leading character IS the semantic category.
  ///
  /// The 2-char code `同音` is checked before the single-char codes to
  /// avoid its prefix `同` being mistaken (no such single-char code exists,
  /// so ordering is defensive only).
  static String? categoryOf(String relation) {
    final trimmed = relation.trim();
    if (trimmed.isEmpty) return null;
    for (final code in _codesLongestFirst) {
      if (trimmed.startsWith(code)) return code;
    }
    return null;
  }

  // Longer codes first so multi-char codes win over any single-char prefix
  // collisions (currently only 同音 is multi-char). Computed once.
  static final List<String> _codesLongestFirst = List<String>.from(all)
    ..sort((a, b) => b.length.compareTo(a.length));
}

class SecondStageEntry {
  final int id;             // 1..N (assigned by importer)
  final int wordId;         // FK → Phase 1 word.id
  final int block;          // 1..46 (medical block 47 is Phase 1-style; no SS entries)
  final String relation;    // raw client string (e.g. "類", "意 racism", "意３（名２，他１）")
  final String? baseCategory; // cached prefix, or null for free-form
  final String answer;
  final String? answerMeaning;
  final bool ttsEnabled;
  /// The run(s) inside a 「…」 mnemonic that echo the English word — 「OPEC」
  /// for opaque, 「政治」 for sage. The client sets these in gothic bold while
  /// the rest of the mnemonic is mincho (2026-08-24). Only the author knows
  /// which characters carry the pun, so it is recorded rather than guessed;
  /// when empty the renderer falls back to any Latin run in the mnemonic.
  final List<String> mnemonicEcho;
  final String? notes;

  const SecondStageEntry({
    required this.id,
    required this.wordId,
    required this.block,
    required this.relation,
    required this.baseCategory,
    required this.answer,
    required this.answerMeaning,
    required this.ttsEnabled,
    this.mnemonicEcho = const [],
    required this.notes,
  });

  factory SecondStageEntry.fromJson(Map<String, dynamic> j) {
    return SecondStageEntry(
      id: j['id'] as int,
      wordId: j['word_id'] as int,
      block: j['block'] as int,
      relation: (j['relation'] ?? '') as String,
      baseCategory: j['base_category'] as String?,
      answer: (j['answer'] ?? '') as String,
      answerMeaning: j['answer_meaning'] as String?,
      ttsEnabled: (j['tts_enabled'] ?? false) as bool,
      mnemonicEcho: (j['mnemonic_echo'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList(growable: false) ??
          const [],
      notes: j['notes'] as String?,
    );
  }
}

class SecondStageRepository {
  SecondStageRepository._(
    this._byId,
    this._byBlock,
    this._byWordId,
    this._headwordIdsByBlock,
  );

  final Map<int, SecondStageEntry> _byId;
  final Map<int, List<SecondStageEntry>> _byBlock;
  final Map<int, List<SecondStageEntry>> _byWordId;
  final Map<int, List<int>> _headwordIdsByBlock;

  static Future<SecondStageRepository> loadFromAsset(
      [String path = 'assets/content/second_stage.json']) async {
    final raw = await rootBundle.loadString(path);
    final doc = jsonDecode(raw) as Map<String, dynamic>;
    final entries = (doc['entries'] as List)
        .cast<Map<String, dynamic>>()
        .map(SecondStageEntry.fromJson)
        .toList();

    final byId = <int, SecondStageEntry>{};
    final byBlock = <int, List<SecondStageEntry>>{};
    final byWordId = <int, List<SecondStageEntry>>{};
    final headwordIdsByBlock = <int, Set<int>>{};

    for (final e in entries) {
      byId[e.id] = e;
      (byBlock[e.block] ??= <SecondStageEntry>[]).add(e);
      (byWordId[e.wordId] ??= <SecondStageEntry>[]).add(e);
      (headwordIdsByBlock[e.block] ??= <int>{}).add(e.wordId);
    }
    // Stable ordering within each block: headword id ascending, then entry id.
    for (final list in byBlock.values) {
      list.sort((a, b) {
        final w = a.wordId.compareTo(b.wordId);
        return w != 0 ? w : a.id.compareTo(b.id);
      });
    }
    for (final list in byWordId.values) {
      list.sort((a, b) => a.id.compareTo(b.id));
    }

    return SecondStageRepository._(
      Map.unmodifiable(byId),
      {for (final e in byBlock.entries) e.key: List.unmodifiable(e.value)},
      {for (final e in byWordId.entries) e.key: List.unmodifiable(e.value)},
      {
        for (final e in headwordIdsByBlock.entries)
          e.key: (e.value.toList()..sort()),
      },
    );
  }

  int get count => _byId.length;

  /// Blocks that actually contain at least one SS entry (client's data
  /// covers blocks 1..46; block 47 is FS-style and has no SS drills).
  List<int> allBlocks() => _byBlock.keys.toList()..sort();

  bool hasEntriesForBlock(int block) => _byBlock.containsKey(block);
  bool hasEntriesForWord(int wordId) => _byWordId.containsKey(wordId);

  List<SecondStageEntry> byBlock(int block) =>
      _byBlock[block] ?? const <SecondStageEntry>[];

  List<SecondStageEntry> byWordId(int wordId) =>
      _byWordId[wordId] ?? const <SecondStageEntry>[];

  SecondStageEntry? byId(int entryId) => _byId[entryId];

  /// Every entry, ordered by id. Mirrors VideoRepository.all.
  Iterable<SecondStageEntry> get all => _byId.values;

  /// Unique headword IDs that carry ≥1 SS entry in the given block,
  /// in ascending order. Used to build the SS session queue.
  List<int> headwordIdsInBlock(int block) =>
      _headwordIdsByBlock[block] ?? const <int>[];
}
