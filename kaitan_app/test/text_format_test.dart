// Unit tests for the text-format helpers used on the ⑦ Answer screen:
//   • mnemonicSpans      — bolds text outside [..] / ［..］ brackets
//   • meaningSingleSpans — small/thin styling for parenthesized supplements

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kaitan/features/session/presentation/text_format.dart';

const boldStyle = TextStyle(fontWeight: FontWeight.w700);
const plainStyle = TextStyle(fontWeight: FontWeight.w400);

void main() {
  group('mnemonicSpans', () {
    test('text with brackets: bold outside, plain inside', () {
      final spans = mnemonicSpans(
        '虻、象ブスッと［吸収する］',
        boldStyle: boldStyle,
        plainStyle: plainStyle,
      );
      expect(spans, hasLength(2));
      expect(spans[0].text, '虻、象ブスッと');
      expect(spans[0].style?.fontWeight, FontWeight.w700);
      expect(spans[1].text, '［吸収する］');
      expect(spans[1].style?.fontWeight, FontWeight.w400);
    });

    test('half-width brackets work too', () {
      final spans = mnemonicSpans(
        'something[meaning]more',
        boldStyle: boldStyle,
        plainStyle: plainStyle,
      );
      expect(spans.map((s) => s.text), ['something', '[meaning]', 'more']);
      expect(spans[0].style?.fontWeight, FontWeight.w700);
      expect(spans[1].style?.fontWeight, FontWeight.w400);
      expect(spans[2].style?.fontWeight, FontWeight.w700);
    });

    test('combined goro + etymology (／-separator)', () {
      final spans = mnemonicSpans(
        'バー、ショッとと［消える］／van［空］',
        boldStyle: boldStyle,
        plainStyle: plainStyle,
      );
      expect(spans.map((s) => s.text), [
        'バー、ショッとと',
        '［消える］',
        '／van',
        '［空］',
      ]);
      expect(spans[0].style?.fontWeight, FontWeight.w700); // バー、ショッとと
      expect(spans[1].style?.fontWeight, FontWeight.w400); // ［消える］
      expect(spans[2].style?.fontWeight, FontWeight.w700); // ／van
      expect(spans[3].style?.fontWeight, FontWeight.w400); // ［空］
    });

    test('no brackets ⇒ whole string is bold', () {
      final spans = mnemonicSpans(
        'ロイヤルファミリー',
        boldStyle: boldStyle,
        plainStyle: plainStyle,
      );
      expect(spans, hasLength(1));
      expect(spans[0].text, 'ロイヤルファミリー');
      expect(spans[0].style?.fontWeight, FontWeight.w700);
    });

    test('empty input ⇒ empty list', () {
      expect(mnemonicSpans(''), isEmpty);
    });
  });

  group('meaningSingleSpans', () {
    final big = TextStyle(fontSize: 28, fontWeight: FontWeight.w800);
    final small = TextStyle(fontSize: 14, fontWeight: FontWeight.w400);

    test('plain meaning ⇒ all big', () {
      final spans = meaningSingleSpans(
        '吸収する',
        bigStyle: big,
        smallStyle: small,
      );
      expect(spans, hasLength(1));
      expect(spans[0].text, '吸収する');
      expect(spans[0].style?.fontSize, 28);
    });

    test('parenthesized supplement ⇒ small + thin', () {
      final spans = meaningSingleSpans(
        '現れる（突然）',
        bigStyle: big,
        smallStyle: small,
      );
      expect(spans.map((s) => s.text), ['現れる', '（突然）']);
      expect(spans[0].style?.fontSize, 28);
      expect(spans[1].style?.fontSize, 14);
      expect(spans[1].style?.fontWeight, FontWeight.w400);
    });

    test('half-width parens work too', () {
      final spans = meaningSingleSpans(
        'absorb (water etc.)',
        bigStyle: big,
        smallStyle: small,
      );
      expect(spans.map((s) => s.text), ['absorb ', '(water etc.)']);
      expect(spans[0].style?.fontSize, 28);
      expect(spans[1].style?.fontSize, 14);
    });

    test('parens at start ⇒ small first, then big', () {
      final spans = meaningSingleSpans(
        '（特に）特殊な意味',
        bigStyle: big,
        smallStyle: small,
      );
      expect(spans.map((s) => s.text), ['（特に）', '特殊な意味']);
      expect(spans[0].style?.fontSize, 14);
      expect(spans[1].style?.fontSize, 28);
    });

    test('empty input ⇒ empty list', () {
      expect(meaningSingleSpans('', bigStyle: big, smallStyle: small), isEmpty);
    });
  });
}
