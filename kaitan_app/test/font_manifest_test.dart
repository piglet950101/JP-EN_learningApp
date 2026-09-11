// Every FontWeight the ゴロ renderer distinguishes must actually be registered
// in pubspec.yaml, or Flutter silently falls back to the nearest weight that is.
//
// KaitanSans-Light.ttf was built, committed and shipped inside the APK on
// 2026-09-10 — but never listed under `fonts:`, so it never reached the
// FontManifest and FontWeight.w300 could not select it. The 細字 the client
// asked for only *looked* applied, on the rows whose surrounding weight
// happened to be heavier. Nothing failed, and the delivery note said it was done.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pubspec registers every weight the ゴロ renderer distinguishes', () {
    // Scoped to the span builder, where weight IS the distinction: w300 marks
    // a supplementary note, w400 the ゴロ, w900 the run echoing the English
    // word. Elsewhere (w500/w600 on buttons and headings) falling back to the
    // nearest declared weight is fine and intended.
    final src =
        File('lib/features/second_stage/presentation/ss_meaning_text.dart')
            .readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    final used = RegExp(r'FontWeight\.w([1-9]00)')
        .allMatches(src)
        .map((m) => int.parse(m.group(1)!))
        .toSet();
    final declared = RegExp(r'weight:\s*([1-9]00)')
        .allMatches(pubspec)
        .map((m) => int.parse(m.group(1)!))
        .toSet();

    expect(used, isNotEmpty, reason: 'no FontWeight found — regex out of date?');
    expect(declared.containsAll(used), isTrue,
        reason: 'ss_meaning_text.dart asks for weights $used but pubspec '
            'declares $declared; missing ${used.difference(declared)} — '
            'Flutter falls back silently to the nearest declared weight');
  });

  test('every declared font asset exists on disk', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final assets =
        RegExp(r'asset:\s*(assets/fonts/\S+)').allMatches(pubspec).toList();
    expect(assets, isNotEmpty);
    for (final m in assets) {
      expect(File(m.group(1)!).existsSync(), isTrue,
          reason: '${m.group(1)} is declared in pubspec but missing on disk');
    }
  });
}
