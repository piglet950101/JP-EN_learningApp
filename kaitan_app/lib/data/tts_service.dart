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

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// One utterance in an auto-played sequence.
///
/// This type exists because `speakSequence` used to take bare `List<String>`
/// answers, which silently dropped the pronunciation hint that the per-row
/// speaker button was passing. The engine then received raw Japanese and read
/// it with whatever voice its script suggested — Chinese for pure kanji
/// (0544 母音, 1317 金庫), Japanese where kana appeared (2107 典型的に) —
/// which is exactly what the client reported on 2026-09-08:
/// 「…の発音は入っているようですが、中国語の音声が邪魔してボタンを押さないと
/// 聞こえません」. The audio *was* there; only the button path could reach it.
class SpeakItem {
  const SpeakItem(this.text, {this.pronunciationHint, this.audio = const []});

  final String text;

  /// How the row must be READ, overriding what is shown.
  final String? pronunciationHint;

  /// Recorded files for this row, played in order and preferred over TTS.
  final List<String> audio;
}

abstract class TtsService {
  Future<void> init();
  Future<void> speak(String text, {String? pronunciationHint, int? wordId});

  /// Speak an SS answer string, cleaning it before speaking:
  ///   • strips a leading POS marker like "[自]" / "[他]" / "[名]" ...
  ///   • strips trailing "(...)" parenthetical placeholders (e.g. "(to 人 for 事)")
  ///   • splits "lay > laid > laid" style conjugation triples on `>` and
  ///     speaks each in sequence with a short pause (no `>` uttered).
  /// If the cleaned string is empty (e.g. only `[自]` was there), this is a no-op.
  /// [pronunciationHint] overrides how the answer is READ without changing
  /// what is shown. Needed where the spelling misleads the engine — 0242 wind
  /// is ワインド not ウインド, 0916 tear is ティア, 0410 prayer is プレア in one
  /// row and プレイア in the next.
  Future<void> speakAnswer(String raw,
      {String? pronunciationHint, List<String> audio = const []});

  /// Speak several SS rows back-to-back with a short pause between, used by
  /// the ⑦' auto-play when the answer view opens. Takes [SpeakItem]s rather
  /// than strings so each row keeps its pronunciation hint and recorded audio.
  Future<void> speakSequence(List<SpeakItem> items);
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

  @override
  Future<void> speakAnswer(String raw,
      {String? pronunciationHint, List<String> audio = const []}) async {
    if (!_ready) await init();
    await _tts.stop();
    await _player.stop();
    // A recording of the row beats every synthesised variant — and a row that
    // declares one never falls back to speaking itself, even if playback
    // fails. Several of these rows answer in Japanese (1901 axis 斧/公理,
    // 0916 涙　tear), and the English engine hands those to a Chinese voice.
    // Silence is the better failure: 「中国語の音声が入るようです」 has now
    // been filed three review rounds running.
    if (audio.isNotEmpty) {
      await _playAll(audio);
      return;
    }
    final hint = pronunciationHint?.trim() ?? '';
    if (hint.isNotEmpty) {
      // Kana is read by the Japanese voice, which is the only way to force an
      // English spelling to a specific sound; anything else is read as-is.
      // Waiting for the utterance matters in a sequence: _tts.speak() returns
      // as soon as the phrase is QUEUED, so a hint row used to hand straight
      // back to speakSequence and the next row began 550ms later, over the top.
      if (_kanaRe.hasMatch(hint)) {
        await _tts.setLanguage('ja-JP');
        await _speakOneAndWait(hint);
        await _tts.setLanguage(_defaultLang);
      } else {
        await _speakOneAndWait(hint);
      }
      return;
    }
    final words = _splitAnswerForSpeech(raw);
    if (words.isEmpty) return;
    for (var i = 0; i < words.length; i++) {
      if (i > 0) await Future<void>.delayed(const Duration(milliseconds: 350));
      await _speakOneAndWait(words[i]);
    }
  }

  @override
  Future<void> speakSequence(List<SpeakItem> items) async {
    if (!_ready) await init();
    for (var i = 0; i < items.length; i++) {
      if (i > 0) await Future<void>.delayed(const Duration(milliseconds: 550));
      await speakAnswer(items[i].text,
          pronunciationHint: items[i].pronunciationHint,
          audio: items[i].audio);
    }
  }

  /// Play recorded files in order, waiting for each. Returns false only when
  /// nothing could be STARTED, so the caller can fall back to TTS.
  ///
  /// The verdict deliberately depends on `play()` alone, never on the wait
  /// that follows. Setting it after awaiting the completion event — as this
  /// did until 2026-09-09 — meant any failure of that future was caught here,
  /// reported as "nothing played", and sent the caller on to synthesise the
  /// row as well, on top of a recording that was still sounding. That is the
  /// doubled audio the client reported across six rows:
  ///   0773 「同音の発音が２回あります。最初の音声は不要です」
  ///   0410 「カタカナの発音も同時に聞こえます」
  ///   0916 「涙 の発音が二重になっています」
  ///   1901 「中国語の音声が入るようです」 — 斧/公理 read by the CJK voice
  Future<bool> _playAll(List<String> assets) async {
    var played = false;
    for (var i = 0; i < assets.length; i++) {
      if (i > 0) await Future<void>.delayed(const Duration(milliseconds: 250));
      Future<void> done;
      try {
        // Stop first: replaying the SAME asset back-to-back is the case that
        // exposed this, 1829 upset being one take played three times.
        await _player.stop();
        done = _player.onPlayerComplete.first;
        await _player.play(AssetSource(assets[i]));
        played = true;
      } catch (_) {
        continue; // could not start this one; the next may still work
      }
      // Best-effort wait. It must never change the verdict above, and if the
      // completion event cannot be observed we still hold the line so the
      // next file does not start on top of this one.
      try {
        await done.timeout(const Duration(seconds: 8), onTimeout: () {});
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      }
    }
    return played;
  }

  Future<void> _speakOneAndWait(String s) async {
    // flutter_tts's speak() returns immediately once queued. We attach a
    // completion handler so `await` resolves when audio actually finishes.
    final completer = Completer<void>();
    _tts.setCompletionHandler(() {
      if (!completer.isCompleted) completer.complete();
    });
    _tts.setErrorHandler((_) {
      if (!completer.isCompleted) completer.complete();
    });
    await _tts.speak(s);
    // Guard against a stuck utterance (some Android voices misbehave).
    await completer.future
        .timeout(const Duration(seconds: 6), onTimeout: () {});
  }

  /// Splits an SS answer string into utterable words:
  ///   • strips a leading POS marker `[自]`, `［自］`, `他`, etc.
  ///   • drops any `(...)` / `（...）` parenthetical
  ///   • splits on `>` (conjugation triples: `lay > laid > laid`)
  static final RegExp _leadingPosRe = RegExp(
    r'^\s*[［\[][^］\]]{1,4}[］\]]\s*',
  );
  static final RegExp _parensRe = RegExp(r'[(（][^)）]*[)）]');
  static final RegExp _conjSep = RegExp(r'\s*>\s*');
  static List<String> _splitAnswerForSpeech(String raw) {
    var s = raw;
    s = s.replaceFirst(_leadingPosRe, '');
    s = s.replaceAll(_parensRe, '');
    s = s.trim();
    if (s.isEmpty) return const [];
    if (s.contains('>')) {
      return s.split(_conjSep).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    }
    return [s];
  }
}
