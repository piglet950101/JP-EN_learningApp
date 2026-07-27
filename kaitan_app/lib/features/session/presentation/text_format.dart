// Text-formatting helpers used on the ⑦ Answer screen.
//
// Spec v1.2 (2026-06-02, 菊地 + 落合 review):
//   • Mnemonic (覚え方の具体的方法): text OUTSIDE square brackets [..] /［..］
//     is the pronunciation-linked part and is rendered in BOLD; text inside
//     brackets (the explanation/meaning portion) is normal weight.
//   • Meaning text: when a word is "single mode" (one meaning, possibly with
//     supplementary parenthesized notes), the bare meaning is big + bold;
//     parenthesized notes — (... / （...） — are small + thin.
//     When the word is multi-meaning (both_required / either_ok), each entry
//     is rendered as a big + bold piece in a horizontal Wrap (lays out side-
//     by-side if it fits, falls to a second row otherwise — but each
//     individual meaning never wraps mid-character).

import 'package:flutter/material.dart';

import '../../../data/word.dart';

/// Splits text on bracket pairs ([..] or ［..］) and emits (chunk, isBracketed)
/// runs in order. Used to bold the pronunciation portion of a mnemonic.
List<TextSpan> mnemonicSpans(String text, {
  TextStyle? boldStyle,
  TextStyle? plainStyle,
}) {
  if (text.isEmpty) return const [];
  // Matches both half-width [...] and full-width ［...］, non-greedy inner.
  final re = RegExp(r'[\[［][^\]］]*[\]］]');
  final spans = <TextSpan>[];
  var cursor = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > cursor) {
      spans.add(TextSpan(
        text: text.substring(cursor, m.start),
        style: boldStyle,
      ));
    }
    spans.add(TextSpan(text: text.substring(m.start, m.end), style: plainStyle));
    cursor = m.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: boldStyle));
  }
  return spans;
}

/// Splits a single meaning string into runs: parenthesized notes vs. the
/// "core" meaning. Half-width () and full-width （） both match.
List<TextSpan> meaningSingleSpans(String text, {
  required TextStyle bigStyle,
  required TextStyle smallStyle,
}) {
  if (text.isEmpty) return const [];
  final re = RegExp(r'[（(][^（()）]*[）)]');
  final spans = <TextSpan>[];
  var cursor = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, m.start), style: bigStyle));
    }
    spans.add(TextSpan(text: text.substring(m.start, m.end), style: smallStyle));
    cursor = m.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: bigStyle));
  }
  return spans;
}

/// True when the [Word] requires two side-by-side big/bold meanings rather
/// than the single "main + supplementary" rendering.
bool useDualMeaning(Word word) =>
    word.meaningMode == MeaningMode.bothRequired ||
    word.meaningMode == MeaningMode.eitherOk;
