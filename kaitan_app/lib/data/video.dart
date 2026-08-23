// Video (Vimeo) — bundled metadata + repository.
//
// The 46 videos correspond 1:1 to First Stage blocks 1..46 (client 2026-07-13).
// The medical block (47) has no accompanying video and is intentionally
// absent from the manifest.
//
// The Flutter side never talks to Vimeo's API — we bundle static metadata
// (id, hash, embed URL) and load an embed-player URL into a WebView.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class VideoEntry {
  final int id;             // 1..46 (matches block for the 46-block core)
  final int block;
  final int vol;            // 1 (blocks 1-23) or 2 (blocks 24-46)
  final String title;
  final String vimeoId;
  final String vimeoHash;
  final String embedUrl;    // https://player.vimeo.com/video/{id}?h={hash}
  final String shareUrl;    // https://vimeo.com/{id}/{hash}?...
  final int? durationSec;
  /// Width over height. Null when the manifest does not say, in which case
  /// [aspect] falls back to 16:9 — the shape of the original 46 videos.
  final double? aspectRatio;
  final int? firstWordId;
  final int? lastWordId;

  const VideoEntry({
    required this.id,
    required this.block,
    required this.vol,
    required this.title,
    required this.vimeoId,
    required this.vimeoHash,
    required this.embedUrl,
    required this.shareUrl,
    required this.durationSec,
    this.aspectRatio,
    required this.firstWordId,
    required this.lastWordId,
  });

  factory VideoEntry.fromJson(Map<String, dynamic> j) => VideoEntry(
        id: j['id'] as int,
        block: j['block'] as int,
        vol: j['vol'] as int,
        title: j['title'] as String,
        vimeoId: j['vimeo_id'] as String,
        vimeoHash: j['vimeo_hash'] as String,
        embedUrl: j['embed_url'] as String,
        shareUrl: j['share_url'] as String,
        durationSec: j['duration_sec'] as int?,
        aspectRatio: (j['aspect_ratio'] as num?)?.toDouble(),
        firstWordId: j['first_word_id'] as int?,
        lastWordId: j['last_word_id'] as int?,
      );

  /// Width over height, defaulting to 16:9 when the manifest is silent.
  double get aspect {
    final a = aspectRatio;
    return (a != null && a > 0) ? a : 16 / 9;
  }

  /// True for footage that is taller than it is wide. Such a video must NOT
  /// be shown by rotating the device — that would letterbox it on both sides
  /// and make it smaller, which is the opposite of what fullscreen is for.
  bool get isPortraitVideo => aspect < 1;

  /// Formatted like "約 6:00" if we have a duration, else "".
  String get durationLabel {
    final s = durationSec;
    if (s == null) return '';
    final m = s ~/ 60;
    final sec = s % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }
}

class VideoRepository {
  VideoRepository._(this._byBlock, this._all);
  final Map<int, VideoEntry> _byBlock;
  final List<VideoEntry> _all;

  static Future<VideoRepository> loadFromAsset(
      [String path = 'assets/content/videos.json']) async {
    try {
      final raw = await rootBundle.loadString(path);
      final doc = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (doc['entries'] as List)
          .cast<Map<String, dynamic>>()
          .map(VideoEntry.fromJson)
          .toList();
      entries.sort((a, b) => a.block.compareTo(b.block));
      return VideoRepository._(
        {for (final e in entries) e.block: e},
        List.unmodifiable(entries),
      );
    } catch (_) {
      // Manifest missing → repository is empty (video feature effectively off).
      return VideoRepository._({}, const []);
    }
  }

  int get count => _all.length;
  List<VideoEntry> get all => _all;
  VideoEntry? byBlock(int block) => _byBlock[block];
  bool hasVideoForBlock(int block) => _byBlock.containsKey(block);
}
