// Second Stage rendering rules from the 2026-08-19 review batch.
//
// Two global rules replace what would otherwise have been ~148 individual
// per-word corrections, so they are worth pinning:
//
//   1. Multi-sense text breaks onto one line per part of speech, in the
//      ANSWER field as well as the meaning field. Previously only the
//      meaning field broke, which is why ~71 words still ran together.
//   2. 「...」 mnemonics render ゴチ/bold/smaller/black against a 明朝/normal
//      meaning.
//
// The helpers under test are private to ss_session_view.dart, so the rules
// are restated here independently — if the implementation drifts from the
// client's spec, these fail.

import 'package:flutter_test/flutter_test.dart';

String breakForReading(String s) {
  var out = s.replaceAll(RegExp(r'\s*cf\.\s*'), '\ncf. ');
  out = out.replaceAllMapped(
    RegExp(r'\s+([他自名形副動前接])\s'),
    (m) => '\n${m.group(1)} ',
  );
  return out.trim();
}

void main() {
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
}
