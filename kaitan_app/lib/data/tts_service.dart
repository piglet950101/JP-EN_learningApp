// TtsService — thin abstraction that plays a word's pronunciation, preferring
// a client-supplied recorded audio file when one is bundled for the word.
//
// Priority (per spec 2026-07-13):
//   1. Recorded audio file (`assets/audio/{padded_id}.{ext}`) if present in
//      the audio manifest — plays with audioplayers.
//   2. Pronunciation-hint TTS (katakana → Japanese voice; ASCII → English) —
//      unchanged from the 2026-06-30 spec.
//   3. Raw English word via flutter_tts.
//
// The audio manifest is loaded once at app start via `audioManifestProvider`
// (see core/providers.dart). `speak()` accepts an optional wordId so the
// caller doesn't have to know the manifest layout.

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

abstract class TtsService {
  Future<void> init();
  Future<void> speak(String text, {String? pronunciationHint, int? wordId});
}

class FlutterTtsService implements TtsService {
  FlutterTtsService({Map<int, String>? audioAssets})
      : _audioAssets = audioAssets ?? const {};

  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _player = AudioPlayer(playerId: 'kaitan_pronunciation');
  final Map<int, String> _audioAssets;
  bool _ready = false;
  static const _defaultLang = 'en-US';
  // Matches both hiragana (3040–309F) and katakana (30A0–30FF).
  static final _kanaRe = RegExp(r'[぀-ヿ]');

  @override
  Future<void> init() async {
    await _tts.setLanguage(_defaultLang);
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    try {
      await _tts.speak(' ');
      await _tts.stop();
    } catch (_) {}
    await _player.setReleaseMode(ReleaseMode.stop);
    _ready = true;
  }

  @override
  Future<void> speak(String text,
      {String? pronunciationHint, int? wordId}) async {
    if (!_ready) await init();
    await _tts.stop();
    await _player.stop();

    // 1. Recorded audio takes precedence over any TTS variant.
    if (wordId != null) {
      final assetPath = _audioAssets[wordId];
      if (assetPath != null) {
        try {
          await _player.play(AssetSource(assetPath));
          return;
        } catch (_) {
          // Fall through to TTS if playback fails for any reason.
        }
      }
    }

    if (pronunciationHint != null && pronunciationHint.trim().isNotEmpty) {
      final hint = pronunciationHint.trim();
      if (_kanaRe.hasMatch(hint)) {
        await _tts.setLanguage('ja-JP');
        await _tts.speak(hint);
        await _tts.setLanguage(_defaultLang);
        return;
      }
      await _tts.speak(hint);
      return;
    }
    await _tts.speak(text);
  }
}
