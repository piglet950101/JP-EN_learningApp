// Video repository — bundled data checks.
//
// The Vimeo id/hash must be non-empty for all 46 entries and the embed
// URL must be a real player.vimeo.com URL, otherwise the WebView will
// show a broken video.

import 'package:flutter_test/flutter_test.dart';

import 'package:kaitan/data/video.dart';

void main() {
  late VideoRepository repo;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    repo = await VideoRepository.loadFromAsset();
  });

  test('exactly 46 videos bundled (blocks 1..46)', () {
    expect(repo.count, 46);
    for (var b = 1; b <= 46; b++) {
      expect(repo.byBlock(b), isNotNull, reason: 'block $b missing');
    }
  });

  test('block 47 (医系) has no video', () {
    expect(repo.byBlock(47), isNull);
    expect(repo.hasVideoForBlock(47), isFalse);
  });

  test('every entry has non-empty vimeo_id, hash, and embed URL', () {
    for (final v in repo.all) {
      expect(v.vimeoId, isNotEmpty, reason: 'block ${v.block} id empty');
      expect(v.vimeoHash, isNotEmpty, reason: 'block ${v.block} hash empty');
      expect(v.embedUrl,
          startsWith('https://player.vimeo.com/video/${v.vimeoId}?h=${v.vimeoHash}'),
          reason: 'block ${v.block} embed URL malformed');
    }
  });

  test('vol assignments: blocks 1-23 → vol.1, 24-46 → vol.2', () {
    for (final v in repo.all) {
      final expectedVol = v.block <= 23 ? 1 : 2;
      expect(v.vol, expectedVol, reason: 'block ${v.block} vol mismatch');
    }
  });


  // ── Footage shape (client's vertical videos, due 2026-08-29) ────────
  //
  // The player must follow the shape of the footage. Rotating a 9:16 video
  // into landscape would letterbox it down both sides and make it smaller,
  // so isPortraitVideo is what decides whether 全画面 rotates the device.

  VideoEntry entryWith(Object? aspect) => VideoEntry.fromJson({
        'id': 1,
        'block': 1,
        'vol': 1,
        'title': 't',
        'vimeo_id': '1',
        'vimeo_hash': 'h',
        'embed_url': 'https://player.vimeo.com/video/1?h=h',
        'share_url': 'https://vimeo.com/1/h',
        'duration_sec': null,
        'aspect_ratio': aspect,
        'first_word_id': 1,
        'last_word_id': 2,
      });

  test('a manifest without aspect_ratio falls back to 16:9', () {
    final v = entryWith(null);
    expect(v.aspectRatio, isNull);
    expect(v.aspect, closeTo(16 / 9, 1e-9));
    expect(v.isPortraitVideo, isFalse);
  });

  test('vertical footage is recognised and never rotated', () {
    final v = entryWith(9 / 16);
    expect(v.aspect, closeTo(0.5625, 1e-9));
    expect(v.isPortraitVideo, isTrue);
  });

  test('landscape and square footage both stay landscape-mode', () {
    expect(entryWith(16 / 9).isPortraitVideo, isFalse);
    expect(entryWith(1.0).isPortraitVideo, isFalse);
  });

  test('a nonsensical aspect_ratio falls back rather than dividing by zero',
      () {
    for (final bad in <Object?>[0, -1.5]) {
      final v = entryWith(bad);
      expect(v.aspect, closeTo(16 / 9, 1e-9), reason: 'aspect_ratio=$bad');
      expect(v.isPortraitVideo, isFalse);
    }
  });

  test('every bundled video has a usable aspect', () {
    for (final v in repo.all) {
      expect(v.aspect, greaterThan(0), reason: 'block ${v.block}');
    }
  });

  test('all 46 blocks are vertical footage (delivered 2026-08-27)', () {
    // 湯原様 re-shot every block 9:16 and swapped them in place, so the
    // manifest must say portrait for all of them. If a re-import ever loses
    // the orientation field the entries fall back to 16:9 and fullscreen
    // starts rotating the device again — which for vertical footage makes
    // the picture SMALLER, the opposite of what the control is for.
    for (final v in repo.all) {
      expect(v.isPortraitVideo, isTrue, reason: 'block ${v.block}');
      expect(v.aspect, closeTo(9 / 16, 1e-9), reason: 'block ${v.block}');
    }
    expect(repo.all.length, 46);
  });
}