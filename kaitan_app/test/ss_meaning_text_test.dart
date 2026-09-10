// Pins the three-way styling of a Second Stage meaning line.
//
// This logic has failed silently twice, and each time the only signal was the
// client re-reporting rows whose recorded data was already correct — once when
// the ゴチ/明朝 rule was inverted (2026-08-24) and once when a supplementary
// note short-circuited the ゴロ emphasis (found 2026-09-08). Both are cheap to
// reintroduce and expensive to notice, so they are pinned here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kaitan/data/second_stage.dart';
import 'package:kaitan/features/second_stage/presentation/ss_meaning_text.dart';

const _base = TextStyle(fontFamily: 'KaitanSans', fontSize: 15);

/// Flatten a span tree into (text, style) pairs, in reading order.
List<({String text, TextStyle style})> _runs(InlineSpan span) {
  final out = <({String text, TextStyle style})>[];
  void walk(InlineSpan s) {
    if (s is TextSpan) {
      if (s.text != null && s.text!.isNotEmpty) {
        out.add((text: s.text!, style: s.style ?? const TextStyle()));
      }
      for (final c in s.children ?? const <InlineSpan>[]) {
        walk(c);
      }
    }
  }

  walk(span);
  return out;
}

TextStyle _styleOf(InlineSpan span, String text) =>
    _runs(span).firstWhere((r) => r.text.contains(text)).style;

void main() {
  test('a ゴロ splits three ways: meaning ゴチ, echo ゴチ bold, rest 明朝', () {
    final span = buildMeaningSpans('不透明な「OPECは不透明」',
        base: _base, echo: const ['OPEC']);

    expect(_styleOf(span, '不透明な').fontFamily, 'KaitanSans');
    expect(_styleOf(span, '不透明な').fontSize, 15);

    final echo = _styleOf(span, 'OPEC');
    expect(echo.fontWeight, FontWeight.w900);
    expect(echo.fontFamily, 'KaitanSans');
    expect(echo.color, Colors.black);
    // 「基本的に黒字で、小さいフォント」 (client 2026-08-26 ③), as a ratio so it
    // holds at the 22px size too. Exact value pinned in its own test below.
    expect(echo.fontSize, lessThan(15));

    expect(_styleOf(span, 'は不透明').fontFamily, 'KaitanSerif');
  });

  test('an unmarked 「…」 keeps the surrounding style — it is a grammar note',
      () {
    // 「賛成する」は自動詞 must NOT turn mincho: leaving an entry unmarked has
    // to stay safe, never a half-applied rule.
    final span = buildMeaningSpans('「賛成する」は自動詞', base: _base);
    for (final r in _runs(span)) {
      expect(r.style.fontFamily, 'KaitanSans');
      expect(r.style.fontSize, 15);
    }
  });

  test('a note and a ゴロ on one line: both apply (2003 sigh)', () {
    // Until 2026-09-08 noteFrom returned early and the echo never ran, so
    // 「いいえ、くらいの」 rendered flat. 2098 corporation and 2137 obvious
    // have the same shape, and all three were re-reported by the client.
    final span = buildMeaningSpans('サイ「いいえ、くらいの」rhinoceros の略',
        base: _base, echo: const ['らいの'], noteFrom: 'rhinoceros の略');

    expect(_styleOf(span, 'サイ').fontFamily, 'KaitanSans');
    expect(_styleOf(span, 'サイ').fontSize, 15);

    expect(_styleOf(span, 'らいの').fontWeight, FontWeight.w900);
    expect(_styleOf(span, 'いいえ、く').fontFamily, 'KaitanSerif');

    // The note itself is black and smaller, and is NOT shrunk twice over.
    final note = _styleOf(span, 'rhinoceros の略');
    expect(note.color, Colors.black);
    expect(note.fontSize, _styleOf(span, 'らいの').fontSize);
  });

  test('a note with no ゴロ still sets its tail smaller and black', () {
    final span = buildMeaningSpans('女性用のハンドバッグ英では女性用の財布',
        base: _base, noteFrom: '英では');
    expect(_styleOf(span, '女性用のハンドバッグ').fontSize, 15);
    final note = _styleOf(span, '英では');
    expect(note.fontSize, lessThan(15));
    expect(note.color, Colors.black);
  });

  test('mnemonicBreak with no echo sets the whole quote 明朝', () {
    final span =
        buildMeaningSpans('「賛成する」が語源', base: _base, asMnemonic: true);
    expect(_styleOf(span, '賛成する').fontFamily, 'KaitanSerif');
  });

  test('the longest echo wins so a shorter one cannot split it', () {
    final span = buildMeaningSpans('銅「Cu は Cyprus から」',
        base: _base, echo: const ['Cu', 'Cyprus']);
    final runs = _runs(span);
    expect(runs.any((r) => r.text == 'Cyprus'), isTrue);
  });

  test('the ゴロ is smaller than the meaning, but not at the floor', () {
    // Bracketed by the client over two rounds: 11px (0.72) was 「小さく感じ
    // られる」 on 09-09; 13px (0.85) was the size it started at, so 09-10 read
    // as no change — 「以前と同じ大きさに戻っている」. 12px is the step between.
    final span = buildMeaningSpans('楕円「オバおるオフィス」',
        base: _base, echo: const ['オバおる']);
    expect(_styleOf(span, '楕円').fontSize, 15);
    expect(_styleOf(span, 'オバおる').fontSize, 12);
    expect(_styleOf(span, 'オフィス').fontSize, 12);
  });

  test('the note is 細字 — lighter than the ゴロ it sits beside', () {
    // Client 2026-09-10 separated the two: the ゴロ 「小さく」, the note
    // 「細字で小さく」. Same size and colour, different weight.
    final span = buildMeaningSpans('死体「こうプスッと刺した死体」= body',
        base: _base, echo: const ['こうプスッ'], noteFrom: '= body');
    final note = _styleOf(span, '= body');
    expect(note.fontWeight, FontWeight.w300);
    expect(note.fontSize, _styleOf(span, 'こうプスッ').fontSize);
    expect(_styleOf(span, 'こうプスッ').fontWeight, FontWeight.w900);
  });

  test('SpeakItem carries the hint and the recordings', () {
    // The auto-play mapped rows to bare answers until 2026-09-08, which is why
    // the engine read Japanese and Chinese aloud while the speaker button
    // beside the same row read English correctly.
    const e = SecondStageEntry(
      id: 1, wordId: 544, block: 12, relation: '意 vowel',
      baseCategory: '意', answer: '母音', answerMeaning: null,
      ttsEnabled: true, pronunciationHint: 'vowel, consonant', notes: null,
    );
    expect(e.pronunciationHint, 'vowel, consonant');
    expect(e.audio, isEmpty);
  });
}
