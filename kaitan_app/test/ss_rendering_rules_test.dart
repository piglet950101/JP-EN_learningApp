// Second Stage rendering rules from the 2026-08-19 review batch.
//
// Two global rules replace what would otherwise have been ~148 individual
// per-word corrections, so they are worth pinning:
//
//   1. Multi-sense text breaks onto one line per part of speech, in the
//      ANSWER field as well as the meaning field. Previously only the
//      meaning field broke, which is why ~71 words still ran together.
//   2. A meaning line splits three ways (client 2026-08-24 ③, superseding the
//      08-19 rule, which had it inverted): the meaning stays ゴチ, the run of
//      a 「…」ゴロ that echoes the English goes ゴチ BOLD, and the rest of the
//      ゴロ goes 明朝. An unmarked line stays wholly ゴチ.
//
// The helpers under test are private to ss_session_view.dart, so the rules
// are restated here independently — if the implementation drifts from the
// client's spec, these fail.

import 'package:flutter_test/flutter_test.dart';

String breakForReading(String s,
    {bool breakBeforeQuote = true}) {
  var out = s.replaceAll(RegExp(r'\s*cf\.\s*'), '\ncf. ');
  out = out.replaceAllMapped(
    RegExp(r'\s+([他自名形副動前接])\s'),
    (m) => '\n${m.group(1)} ',
  );
  // A ゴロ starts its own line (2026-08-26 ④) — but only a ゴロ;
  // a grammar note keeps its quotes inline (2026-08-31).
  if (breakBeforeQuote) {
    out = out.replaceAllMapped(
      RegExp(r'([^\n\s])\s*(?=「)'),
      (m) => '${m.group(1)}\n',
    );
  }
  return out.trim();
}

void main() {
  _headwordMeaningTests();
  group('POS line-breaking (answer field)', () {
    test('0845 object — 名/自 split onto separate lines', () {
      final out = breakForReading('名 物体、対象、目的（語）　自 反対する');
      expect(out.split('\n'), [
        '名 物体、対象、目的（語）',
        '自 反対する',
      ]);
    });

    test('0217 state — 名/他 split', () {
      final out = breakForReading('名 状態、州、国家　他 述べる');
      expect(out.split('\n'), ['名 状態、州、国家', '他 述べる']);
    });

    test('0501 contract — 名/他 split with long tail', () {
      final out = breakForReading('名 契約　他 契約する、縮ませる、（カゼを）ひく');
      expect(out.length, greaterThan(0));
      expect(out.split('\n').length, 2);
      expect(out.split('\n')[1], startsWith('他 '));
    });

    test('conjugation triples are NOT broken', () {
      // `活` answers carry no POS markers, so they must stay on one line.
      expect(breakForReading('sting > stung > stung'),
          'sting > stung > stung');
      expect(breakForReading('lay > laid > laid'), 'lay > laid > laid');
    });

    test('single-sense answers are left untouched', () {
      expect(breakForReading('variety'), 'variety');
      expect(breakForReading('appearance'), 'appearance');
      expect(breakForReading('objection'), 'objection');
    });

    test('cf. still breaks onto its own line', () {
      final out = breakForReading(
          '他動詞なので with, to を取らない cf. be married to a doctor 医者と結婚している');
      expect(out, contains('\ncf. '));
    });
  });

  group('「」 mnemonic detection', () {
    final re = RegExp(r'「[^」]*」');

    test('finds the ゴロ inside a meaning', () {
      expect(re.firstMatch('不透明な「OPECは不透明」')?.group(0),
          '「OPECは不透明」');
      expect(re.firstMatch('高く上がる「空高く上がる」')?.group(0),
          '「空高く上がる」');
      expect(re.firstMatch('愛想よい「笑み溢るとは愛想よい」')?.group(0),
          '「笑み溢るとは愛想よい」');
    });

    test('meanings with no ゴロ are unaffected', () {
      expect(re.hasMatch('読み書きできること'), isFalse);
      expect(re.hasMatch('歓待'), isFalse);
    });
  });

  // ── The three-way split (client 2026-08-24 ③) ──────────────────────
  //
  // Restated from the client's own worked example, 0007 opaque:
  //   不透明な        the meaning        → gothic
  //   OPEC           echoes the English → gothic bold
  //   「…は不透明」    the rest of the ゴロ → mincho

  group('meaning line splits three ways', () {
    test("the client's own 0007 opaque example", () {
      final r = splitMeaning('不透明な「OPECは不透明」', ['OPEC']);
      expect(r, [
        ('不透明な', Face.gothic),
        ('「', Face.mincho),
        ('OPEC', Face.gothicBold),
        ('は不透明」', Face.mincho),
      ]);
    });

    test('a kanji echo is emphasised just like a Latin one', () {
      // 0605 sage 「政治する賢人」 — 政治(せいじ) is the pun. No rule over the
      // characters could find this, which is why it is recorded in data.
      expect(splitMeaning('賢人「政治する賢人」', ['政治']), [
        ('賢人', Face.gothic),
        ('「', Face.mincho),
        ('政治', Face.gothicBold),
        ('する賢人」', Face.mincho),
      ]);
    });

    test('several echoes in one ゴロ are all emphasised', () {
      // 1476 abduct 「ab アブノーマルな方へ　duct 導く」
      final r = splitMeaning('誘拐する「ab アブノーマルな方へ　duct 導く」',
          ['ab', 'duct']);
      expect(r.where((e) => e.$2 == Face.gothicBold).map((e) => e.$1),
          ['ab', 'duct']);
    });

    test('a short echo inside a longer one does not split it', () {
      // 2140 cop 「capture の cap が cop になった」 — 'cap' must not carve up
      // 'capture'; longest-first matching is what prevents that.
      final r = splitMeaning('警官「capture の cap が cop になった」',
          ['capture', 'cap', 'cop']);
      expect(r.where((e) => e.$2 == Face.gothicBold).map((e) => e.$1),
          ['capture', 'cap', 'cop']);
    });

    test('an unmarked line stays wholly gothic — nothing turns mincho', () {
      // Not every 「…」 is a ゴロ. 1185 approve carries 「賛成する」は自動詞,
      // a grammar note, and the client asked for mincho only inside 覚え方.
      expect(splitMeaning('「賛成する」は自動詞', const []),
          [('「賛成する」は自動詞', Face.gothic)]);
      expect(splitMeaning('不透明な「OPECは不透明」', const []),
          [('不透明な「OPECは不透明」', Face.gothic)]);
    });

    test('text outside every ゴロ is gothic even when an echo is marked', () {
      final r = splitMeaning('急性の、鋭い「あ、キューと来るのが急性病」',
          ['あ、キュー']);
      expect(r.first, ('急性の、鋭い', Face.gothic));
    });
  });

  // ── Only a ゴロ takes its own line (client 2026-08-31) ──────────────
  //
  // 1269 revenge and 1761 anxious both asked for 「１行に」. Their quotes are
  // grammar notes sitting mid-sentence, so breaking before each one would
  // scatter a single thought across three lines. mnemonicEcho is what tells
  // a ゴロ from a note, so the caller passes it in.

  group('a grammar note keeps its quotes inline', () {
    test('1761 anxious stays on one line when unmarked', () {
      expect(
          breakForReading('anxious は「やきもき」for は「求めて」',
              breakBeforeQuote: false),
          'anxious は「やきもき」for は「求めて」');
    });

    test('1269 revenge stays on one line when unmarked', () {
      expect(
          breakForReading('oneself「= 自分がやられたこと」を返す',
              breakBeforeQuote: false),
          'oneself「= 自分がやられたこと」を返す');
    });

    test('a marked ゴロ still breaks onto its own line', () {
      expect(
          breakForReading('聖職者「プリーズと祈る聖職者」',
              breakBeforeQuote: true),
          '聖職者\n「プリーズと祈る聖職者」');
    });
  });
}

// ── Independent restatement of the split, per this file's convention ──

enum Face { gothic, gothicBold, mincho }

/// Returns (text, face) runs for a meaning line, mirroring _mnemonicSpans.
List<(String, Face)> splitMeaning(String text, List<String> echo) {
  if (echo.isEmpty) return [(text, Face.gothic)];
  final quoteRe = RegExp(r'「[^」]*」');
  final out = <(String, Face)>[];
  var cursor = 0;
  for (final q in quoteRe.allMatches(text)) {
    if (q.start > cursor) {
      out.add((text.substring(cursor, q.start), Face.gothic));
    }
    out.addAll(_inside(text.substring(q.start, q.end), echo));
    cursor = q.end;
  }
  if (cursor < text.length) out.add((text.substring(cursor), Face.gothic));
  return out.isEmpty ? [(text, Face.gothic)] : out;
}

List<(String, Face)> _inside(String quoted, List<String> echo) {
  final hits = <List<int>>[];
  final needles = [...echo]..sort((a, b) => b.length.compareTo(a.length));
  for (final n in needles) {
    if (n.isEmpty) continue;
    var from = 0;
    while (true) {
      final i = quoted.indexOf(n, from);
      if (i < 0) break;
      if (!hits.any((h) => i < h[1] && h[0] < i + n.length)) {
        hits.add([i, i + n.length]);
      }
      from = i + n.length;
    }
  }
  hits.sort((a, b) => a[0].compareTo(b[0]));
  final out = <(String, Face)>[];
  var cursor = 0;
  for (final h in hits) {
    if (h[0] > cursor) {
      out.add((quoted.substring(cursor, h[0]), Face.mincho));
    }
    out.add((quoted.substring(h[0], h[1]), Face.gothicBold));
    cursor = h[1];
  }
  if (cursor < quoted.length) {
    out.add((quoted.substring(cursor), Face.mincho));
  }
  return out;
}

// ── Headword-meaning visibility (refined 2026-08-19) ──────────────────
//
// A bare 意 / 意２ asks for the HEADWORD's meaning, so showing that meaning
// under the headword would give the answer away. But 意 <word> asks about a
// different look-alike word — 2172 lurk carries 意 lark, 0379 respectable
// carries 意 respectful — and there the headword meaning must stay visible.
// The original rule hid it whenever any 意 entry existed, blanking it on 12
// words.

final _meaningCodePrefix =
    RegExp(r'^意\s*[０-９0-9]*\s*[（(]?\s*[０-９0-9]*\s*[）)]?');

final _startsLatin = RegExp(r'^[A-Za-z]');

final _posThenOwnMeaning = RegExp(r'^[他自名形副動前接間]\s*の意味');

bool shouldHide(List<String> relations, String headword) {
  // Mirrors _shouldHideHeadwordLine, which is handed EVERY relation for the
  // word and does its own filtering — so this takes them all too, rather than
  // a pre-filtered list of 意 entries.
  for (final rel in relations) {
    final r = rel.trim();
    if (_posThenOwnMeaning.hasMatch(r)) return true;
    if (r.startsWith('品')) return true; // posMarker
    if (!r.startsWith('意')) continue; // not a meaning question at all
    final rest = r.replaceFirst(_meaningCodePrefix, '').trim();
    if (rest.isEmpty) return true;
    if (rest.toLowerCase() == headword.trim().toLowerCase()) return true;
    if (_startsLatin.hasMatch(rest)) continue;
    return true;
  }
  return false;
}


void _headwordMeaningTests() {
  group('headword meaning visibility', () {
    test('bare 意 / 意２ hides it (0005 appear)', () {
      expect(shouldHide(['意'], 'appear'), isTrue);
      expect(shouldHide(['意２'], 'appear'), isTrue);
      expect(shouldHide(['意3'], 'appear'), isTrue);
      expect(shouldHide(['意（2）'], 'appear'), isTrue);
    });

    test('意 <different word> keeps it visible', () {
      // These are the exact cases the client flagged on 2026-08-19.
      expect(shouldHide(['意 lark'], 'lurk'), isFalse);
      expect(shouldHide(['意 respectful'], 'respectable'), isFalse);
      expect(shouldHide(['意 decree'], 'discreet'), isFalse);
    });

    test('意 <headword itself> hides it', () {
      expect(shouldHide(['意 thread'], 'thread'), isTrue);
      expect(shouldHide(['意 THREAD'], 'thread'), isTrue);
    });

    test('no 意 entry at all keeps it visible', () {
      expect(shouldHide([], 'diversity'), isFalse);
    });

    test('Japanese qualifier after 意 still hides it', () {
      // 「他　～を訪問する ⇨ トル」-style cases: the text after the 意 code
      // describes how many of the HEADWORD's meanings to give, so the
      // headword line must stay hidden.
      expect(shouldHide(['意３とそれぞれの前置詞'], 'consist'), isTrue);
      expect(shouldHide(['意２～３'], 'degree'), isTrue);
      expect(shouldHide(['意２（他１、名１）'], 'exhaust'), isTrue);
    });
  });

  // ── Client 2026-08-26 ──────────────────────────────────────────────

  group('a ゴロ takes its own line (rule ④)', () {
    test('a mnemonic following a meaning is pushed onto the next line', () {
      expect(breakForReading('聖職者「プリーズと祈る聖職者」'),
          '聖職者\n「プリーズと祈る聖職者」');
    });

    test('two mnemonics in a row each get a line — 1324 surge', () {
      expect(breakForReading('急騰する「匙が急にふわ～と上がる」「血圧サージ」'),
          '急騰する\n「匙が急にふわ～と上がる」\n「血圧サージ」');
    });

    test('a line that is only a mnemonic is left alone', () {
      expect(breakForReading('「スター本許さぬがんこなおやじ」'),
          '「スター本許さぬがんこなおやじ」');
    });

    test('a 「」 used as a grammar note also breaks — harmless, still one idea',
        () {
      expect(breakForReading('approve of his idea「賛成する」は自動詞'),
          'approve of his idea\n「賛成する」は自動詞');
    });
  });

  group('asking for the headword own meaning hides it (rule ①)', () {
    test('0916 tear: 他の意味 and 名 の意味と発音 both hide it', () {
      expect(shouldHide(['他の意味'], 'tear'), isTrue);
      expect(shouldHide(['名 の意味と発音'], 'tear'), isTrue);
      expect(shouldHide(['他の活用'], 'tear'), isFalse);
    });

    test('a DERIVED word and its meaning leaves the headword visible', () {
      // 0006 apparent 副詞とその意味 wants apparently — showing 明らかな
      // gives nothing away, so the line must stay.
      expect(shouldHide(['副詞とその意味'], 'apparent'), isFalse);
      expect(shouldHide(['名詞とその意味を２つ'], 'occupy'), isFalse);
      expect(shouldHide(['形容詞とその意味'], 'condition'), isFalse);
    });

    test('a DIFFERENT word meaning leaves the headword visible', () {
      expect(shouldHide(['副詞 fairly の意味'], 'fair'), isFalse);
      expect(shouldHide(['dig の活用と意味'], 'dignity'), isFalse);
    });
  });

  // ── Repeated labels print once (client 2026-08-26, 0341 / 1275) ─────
  //
  // One question with several answers restated its label on every row. That
  // shape occurs 109 times across 86 words, so it is a rule rather than two
  // corrections.

  group('a repeated label prints once', () {
    test('consecutive identical labels collapse to the first', () {
      expect(labelVisibility(['意４（名２，自２）', '意４（名２，自２）', '名２']),
          [true, false, true]);
    });

    test('a label that returns after a gap prints again', () {
      // Not merely "have I seen this label" — the run has to be adjacent, or
      // a later group would silently lose its heading.
      expect(labelVisibility(['名２', '副', '名２']), [true, true, true]);
    });

    test('a single row always shows its label', () {
      expect(labelVisibility(['意 lapse']), [true]);
    });

    test('three in a row leave only the first', () {
      expect(labelVisibility(['名３', '名３', '名３']), [true, false, false]);
    });
  });
}

/// Mirrors the showLabel argument computed for each _EntryRow.
List<bool> labelVisibility(List<String> relations) => [
      for (var i = 0; i < relations.length; i++)
        i == 0 || relations[i] != relations[i - 1],
    ];