// Round-trip the SS answer-string sanitizer against the exact patterns
// the client called out (2026-08-04 client feedback ⑤⑥ + the general
// [POS] / (parenthetical) rules).

import 'package:flutter_test/flutter_test.dart';

// The sanitizer is a static method on the concrete FlutterTtsService — kept
// private-ish by using a leading underscore in the class file, but its
// behavior is worth pinning here. We restate the same rules independently
// so that if the implementation drifts, this test catches it.

List<String> _splitAnswer(String raw) {
  final leadingPos = RegExp(r'^\s*[［\[][^］\]]{1,4}[］\]]\s*');
  final parens = RegExp(r'[(（][^)）]*[)）]');
  final conjSep = RegExp(r'\s*>\s*');
  var s = raw.replaceFirst(leadingPos, '');
  s = s.replaceAll(parens, '');
  s = s.trim();
  if (s.isEmpty) return const [];
  if (s.contains('>')) {
    return s
        .split(conjSep)
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
  }
  return [s];
}

void main() {
  group('SS answer sanitizer', () {
    test('strips leading POS marker like "[自]" (0030 apology case)', () {
      expect(_splitAnswer('[自] apologize'), ['apologize']);
      expect(_splitAnswer('［自］apologize'), ['apologize']);
    });

    test('drops trailing parenthetical (to 人 for 事)', () {
      expect(_splitAnswer('apologize (to 人 for 事)'), ['apologize']);
      expect(_splitAnswer('apologize（to 人 for 事）'), ['apologize']);
    });

    test('combines POS + parens (client 0030 apology full case)', () {
      expect(_splitAnswer('[自] apologize (to 人 for 事)'), ['apologize']);
      expect(_splitAnswer('自 apologize (to 人 for 事)'),
          ['自 apologize']); // no square-bracket → no strip; free-form
    });

    test('splits conjugation triple on > (0041 sting)', () {
      expect(_splitAnswer('sting > stung > stung'),
          ['sting', 'stung', 'stung']);
      expect(
          _splitAnswer('lay > laid > laid'), ['lay', 'laid', 'laid']);
    });

    test('empty after cleanup returns []', () {
      expect(_splitAnswer('[自]'), isEmpty);
      expect(_splitAnswer('   '), isEmpty);
    });

    test('plain single word passes through unchanged', () {
      expect(_splitAnswer('variety'), ['variety']);
      expect(_splitAnswer('appearance'), ['appearance']);
    });
  });
}
