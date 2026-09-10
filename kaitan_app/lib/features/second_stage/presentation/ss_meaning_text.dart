// The three-way styling of a Second Stage meaning line, kept out of the widget
// so it can be tested directly. Between 2026-08-19 and 2026-09-08 this logic
// silently failed twice — first with the ゴチ/明朝 rule inverted, then with a
// supplementary note short-circuiting the ゴロ emphasis — and both times the
// only signal was the client re-reporting rows whose data was already right.

import 'package:flutter/material.dart';

final RegExp _quoteRe = RegExp(r'「[^」]*」');

/// Style a meaning line, splitting any 「…」 mnemonic three ways.
///
/// Client 2026-08-24 ③, replacing the 08-19 rule. Taking 0007 opaque, whose
/// meaning reads 不透明な「OPECは不透明」:
///
///   不透明な   the meaning        → ゴチ, normal
///   OPEC       echoes the English → ゴチ, bold
///   「…は不透明」the rest of the ゴロ → 明朝
///
/// The earlier rule had this inverted — it set the whole mnemonic in gothic
/// bold and the meaning in mincho, which is why rows with no correction at all
/// still changed appearance.
///
/// [echo] carries the runs that echo the English word. It has to be recorded
/// per entry: the echo is a pun on the sound, and it may be written in Latin
/// (OPEC/opaque), katakana (プリーズ/priest) or plain kanji (政治/sage), so no
/// rule over the characters can find it.
///
/// With no echo recorded the line stays entirely gothic — its appearance
/// before any of this. That default matters: not every 「…」 is a ゴロ. Many are
/// grammar notes quoting Japanese (「賛成する」は自動詞), and the client asked
/// for mincho only inside 意味の覚え方. Leaving an entry unmarked is therefore
/// always safe, never a half-applied rule.
InlineSpan buildMeaningSpans(String text,
    {required TextStyle base,
    List<String> echo = const [],
    bool asMnemonic = false,
    String? noteFrom}) {
  // Client 2026-08-26 ③: a ゴロ is 「基本的に黒字で、小さいフォント」. The same
  // treatment serves a supplementary note running to the end of the line.
  final quoted = base.copyWith(
    color: Colors.black,
    // A ratio, not a fixed -2, so it holds at the 22px size too.
    //   0.72 → 11px, the clamp floor: 「小さく感じられる」 (09-09).
    //   0.85 → 13px, which is exactly the -2 this began as, so it read as no
    //          change at all: 「以前と同じ大きさに戻っているようなので、小さめ
    //          にお願いしたい」 (09-10).
    //   0.8  → 12px, the step between the two he has now bracketed.
    fontSize: ((base.fontSize ?? 15) * 0.8).roundToDouble().clamp(11.0, 40.0),
  );

  // A note and a 「…」 ゴロ can share one line: 2003 sigh reads
  // サイ「いいえ、くらいの」rhinoceros の略, and 2098 corporation and 2137
  // obvious have the same shape. Until 2026-09-08 a noteFrom returned here
  // immediately, so the echo recorded for those rows was never applied and
  // the client kept re-reporting bold that the data already asked for.
  // The note now only changes the base style of its own tail; the quote
  // logic still runs across both halves.
  var head = text;
  String? tail;
  if (noteFrom != null && noteFrom.isNotEmpty) {
    final i = text.indexOf(noteFrom);
    if (i >= 0) {
      head = text.substring(0, i);
      tail = text.substring(i);
    }
  }

  // 細字. The note and the ゴロ were set identically — same colour, same size,
  // same weight — until the client separated them on 2026-09-10: the ゴロ
  // 「小さく」, the note 「細字で小さく」 (1338 cf., 2003 rhinoceros の略,
  // 2098 = body, 2137 oblivion 忘却, 2140 （サツ、デカの感覚）…). w300 is a
  // real bundled face, so it is a weight the device actually honours.
  final note = quoted.copyWith(fontWeight: FontWeight.w300);

  final children = <InlineSpan>[
    if (head.isNotEmpty)
      ..._styleRun(head,
          plain: base, quoted: quoted, echo: echo, asMnemonic: asMnemonic),
    if (tail != null && tail.isNotEmpty)
      ..._styleRun(tail,
          plain: note, quoted: quoted, echo: echo, asMnemonic: asMnemonic),
  ];
  if (children.isEmpty) return TextSpan(text: text, style: base);
  if (children.length == 1) return children.first;
  return TextSpan(children: children);
}

/// Style one run: text outside 「…」 takes [plain]; each 「…」 is set from
/// [quoted] — 明朝 throughout, with the runs that echo the English word in
/// ゴチ bold.
List<InlineSpan> _styleRun(String text,
    {required TextStyle plain,
    required TextStyle quoted,
    required List<String> echo,
    required bool asMnemonic}) {
  // No echo AND not flagged means the 「…」 is a grammar note, which keeps
  // the surrounding style. Flagged with no echo means a ゴロ with nothing to
  // emphasise inside it — the whole quote goes mincho.
  if (echo.isEmpty && !asMnemonic) {
    return [TextSpan(text: text, style: plain)];
  }
  final mincho = quoted.copyWith(fontFamily: 'KaitanSerif');
  final echoStyle = quoted.copyWith(fontWeight: FontWeight.w900);

  final children = <InlineSpan>[];
  var cursor = 0;
  for (final q in _quoteRe.allMatches(text)) {
    if (q.start > cursor) {
      children.add(
          TextSpan(text: text.substring(cursor, q.start), style: plain));
    }
    children.addAll(_insideQuote(text.substring(q.start, q.end),
        mincho: mincho, echoStyle: echoStyle, echo: echo));
    cursor = q.end;
  }
  if (cursor < text.length) {
    children.add(TextSpan(text: text.substring(cursor), style: plain));
  }
  if (children.isEmpty) return [TextSpan(text: text, style: plain)];
  return children;
}

/// One 「…」 run: mincho throughout, except the echoing parts.
List<InlineSpan> _insideQuote(String quoted,
    {required TextStyle mincho,
    required TextStyle echoStyle,
    required List<String> echo}) {
  // Collect the ranges to emphasise, longest first so that a short echo
  // that happens to be a substring of a longer one cannot split it.
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

  final out = <InlineSpan>[];
  var cursor = 0;
  for (final h in hits) {
    if (h[0] > cursor) {
      out.add(TextSpan(text: quoted.substring(cursor, h[0]), style: mincho));
    }
    out.add(TextSpan(
        text: quoted.substring(h[0], h[1]), style: echoStyle));
    cursor = h[1];
  }
  if (cursor < quoted.length) {
    out.add(TextSpan(text: quoted.substring(cursor), style: mincho));
  }
  return out;
}
