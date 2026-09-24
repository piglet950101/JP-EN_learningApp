// Core app providers: persistence (drift), router, ephemeral pending-args
// state that the range-select screen sets before navigating into the session.

import 'dart:convert';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart' show InAppPurchase;

import '../data/progress/progress_db.dart';
import '../data/progress/progress_repository.dart';
import '../data/second_stage.dart';
import '../data/trial/unlock_verifier.dart';
import '../data/trial/purchase_service.dart';
import '../features/legal/privacy_policy_screen.dart';
import '../data/video.dart';
import '../features/range_select/range_screen.dart';
import '../features/session/presentation/session_screen.dart';
import '../features/start/start_screen.dart';
import '../features/trial/presentation/unlock_screen.dart';
import '../features/videos/presentation/video_detail_screen.dart';
import '../features/videos/presentation/video_list_screen.dart';

/// Word IDs that have a bundled illustration. Built at app start by reading
/// `assets/images/manifest.json` (produced by `tool/import_images.py`).
/// Empty when no manifest is present — UI shows the no-image placeholder.
final imageManifestProvider = FutureProvider<Set<int>>((ref) async {
  try {
    final raw = await rootBundle.loadString('assets/images/manifest.json');
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final ids = (j['ids'] as List? ?? const []).cast<int>().toSet();
    return ids;
  } catch (_) {
    // No manifest yet (first run before pipeline) — degrade gracefully.
    return <int>{};
  }
});

String imageAssetPath(int wordId) =>
    'assets/images/${wordId.toString().padLeft(4, '0')}.webp';

/// Map of word-id → asset path for client-recorded pronunciation audio.
/// Built at app start by reading `assets/audio/manifest.json` (produced by
/// `tool/import_audio.py`). Empty when no manifest is present — TTS falls
/// back to the pronunciation-hint / raw-word path in [TtsService].
final audioManifestProvider = FutureProvider<Map<int, String>>((ref) async {
  try {
    final raw = await rootBundle.loadString('assets/audio/manifest.json');
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final entries = (j['entries'] as Map<String, dynamic>? ?? const {});
    return {
      for (final e in entries.entries)
        int.parse(e.key): 'audio/${(e.value as Map)['file'] as String}',
    };
  } catch (_) {
    return const <int, String>{};
  }
});

final progressDbProvider = Provider<ProgressDb>((ref) {
  final db = ProgressDb.openDefault();
  ref.onDispose(db.close);
  return db;
});

final progressRepoProvider = Provider<ProgressRepository>((ref) {
  return ProgressRepository(ref.watch(progressDbProvider));
});

/// Latest lap count for the given stage. Refreshable: callers can
/// `ref.invalidate(lapCountProvider(...))` after writing.
final lapCountProvider =
    FutureProvider.family<int, String>((ref, stage) async {
  return ref.watch(progressRepoProvider).lapCount(stage);
});

/// Latest block status map. Refreshable on completion.
final blockStatusesProvider =
    FutureProvider.family<Map<int, String>, String>((ref, stage) async {
  return ref.watch(progressRepoProvider).blockStatuses(stage);
});

/// What ②③ Range-select passed to ⑥ Session. The session screen reads this
/// in initState; range-select writes it before `context.push('/session')`.
class PendingSessionArgs {
  final List<int> wordIds;
  final Set<int> selectedBlocks;
  final bool excludeFirstOk;
  final String stage;
  const PendingSessionArgs({
    required this.wordIds,
    required this.selectedBlocks,
    required this.excludeFirstOk,
    required this.stage,
  });
}

class PendingSessionArgsNotifier extends Notifier<PendingSessionArgs?> {
  @override
  PendingSessionArgs? build() => null;
  set value(PendingSessionArgs? v) => state = v;
}

final pendingSessionArgsProvider =
    NotifierProvider<PendingSessionArgsNotifier, PendingSessionArgs?>(
        PendingSessionArgsNotifier.new);

/// Bundled Second Stage entries. Empty repo when the asset is absent (dev).
final secondStageRepoProvider =
    FutureProvider<SecondStageRepository>((ref) async {
  return SecondStageRepository.loadFromAsset();
});

/// Bundled 46 Vimeo video entries (blocks 1-46).
final videoRepoProvider = FutureProvider<VideoRepository>((ref) async {
  return VideoRepository.loadFromAsset();
});

/// Trial-unlock state, refreshable after `recordUnlock`.
final unlockedProvider = FutureProvider<bool>((ref) async {
  return ref.watch(progressRepoProvider).isUnlocked();
});

final unlockVerifierProvider =
    Provider<UnlockVerifier>((ref) => const UnlockVerifier());

/// Whether to offer the in-app purchase alongside the code field.
///
/// iOS only. Apple 3.1.4 lets a physical product unlock app features ONLY if
/// an in-app purchase option exists too; Google Play explicitly permits a
/// consumption-only app, so Android keeps the code-only flow the client
/// already has and was told would not change.
///
/// A provider rather than a bare Platform check so tests can drive both.
final showIapProvider =
    Provider<bool>((ref) => defaultTargetPlatform == TargetPlatform.iOS);

/// Whether this build accepts codes sold on their own, without the
/// physical study set (the standalone series in code_series.dart).
///
/// False on iOS. There a code field is allowed only under Guideline
/// 3.1.4, for codes that come with a physical product; a code sold alone
/// is the license-key unlock that 3.1.1 bans. Google Play permits a
/// consumption-only app, so Android accepts both series.
///
/// A provider rather than a bare Platform check so tests can drive both.
final standaloneCodesAcceptedProvider =
    Provider<bool>((ref) => defaultTargetPlatform != TargetPlatform.iOS);

/// The store connection. A provider so tests can put a fake store behind the
/// real purchase wiring below.
final inAppPurchaseProvider =
    Provider<InAppPurchase>((ref) => InAppPurchase.instance);

final purchaseServiceProvider = Provider<PurchaseService>((ref) {
  final s = PurchaseService(
    iap: ref.watch(inAppPurchaseProvider),
    onUnlocked: (marker) async {
      await ref.read(progressRepoProvider).recordUnlock(codeHash: marker);
      ref.invalidate(unlockedProvider);
    },
  );
  ref.onDispose(s.dispose);
  return s;
});

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (c, s) => const StartScreen()),
      GoRoute(path: '/range', builder: (c, s) {
        final stageParam = s.uri.queryParameters['stage'] ?? kStageFirst;
        return RangeScreen(stage: stageParam);
      }),
      GoRoute(path: '/session', builder: (c, s) => const SessionScreen()),
      GoRoute(path: '/unlock', builder: (c, s) => const UnlockScreen()),
      GoRoute(
          path: '/privacy', builder: (c, s) => const PrivacyPolicyScreen()),
      GoRoute(path: '/videos', builder: (c, s) => const VideoListScreen()),
      GoRoute(path: '/videos/:block', builder: (c, s) {
        final block = int.parse(s.pathParameters['block']!);
        return VideoDetailScreen(block: block);
      }),
    ],
  );
});
