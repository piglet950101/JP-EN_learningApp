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
}
