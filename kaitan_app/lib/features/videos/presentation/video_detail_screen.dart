// Video detail — embedded Vimeo WebView player for one block.
//
// Portrait layout: 16:9 player at the top, an info strip, and a shortcut
// button that jumps into that block's First Stage learning flow.
//
// Fullscreen (client 2026-08-15 ②): a 16:9 video in portrait can only ever
// occupy ~56% of the screen width in height, so tapping 全画面 rotates to
// landscape and lets the player fill the display, as YouTube does.
//
// Vertical footage is the opposite case. Rotating a 9:16 video to landscape
// would letterbox it down both sides and make it SMALLER, so for those the
// fullscreen toggle stays in portrait and simply drops the surrounding
// chrome. Which one applies is read from the manifest's aspect_ratio
// (VideoEntry.isPortraitVideo); when the manifest is silent we assume 16:9,
// the shape of the original 46 videos.
//
// Implementation note: fullscreen is a STATE TOGGLE on this same page, not
// a pushed route. webview_flutter allows only one mounted WebViewWidget per
// controller, and a pushed route would keep the old one alive underneath —
// so re-laying-out in place is both simpler and keeps playback position.
// (Android's webview_flutter also does not expose onShowCustomView, so
// Vimeo's own HTML5 fullscreen button cannot be used.)

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../../core/providers.dart';
import '../../../data/block.dart';
import '../../../data/progress/progress_repository.dart';
import '../../../data/video.dart';

class VideoDetailScreen extends ConsumerStatefulWidget {
  final int block;
  const VideoDetailScreen({super.key, required this.block});

  @override
  ConsumerState<VideoDetailScreen> createState() =>
      _VideoDetailScreenState();
}

class _VideoDetailScreenState extends ConsumerState<VideoDetailScreen> {
  WebViewController? _controller;
  bool _loadError = false;
  bool _fullscreen = false;

  /// Vimeo's embed player rejects the default Android WebView UA in some
  /// scenarios (particularly on private/unlisted videos). Presenting as
  /// a stock mobile Chrome makes the embed permission checks pass.
  static const _mobileUa =
      'Mozilla/5.0 (Linux; Android 13; SM-S916U) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36';

  @override
  void dispose() {
    // Always hand the device back in portrait with the system bars restored,
    // even if the user backs out while still in fullscreen.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// The client-supplied embed_url is `player.vimeo.com/video/{id}?h={hash}`.
  /// We append typical mobile-embed params to keep the chrome minimal +
  /// prevent autoplay (which triggers extra permission handshakes).
  String _fullEmbedUrl(String embedUrl) {
    final sep = embedUrl.contains('?') ? '&' : '?';
    return '$embedUrl${sep}autoplay=0&title=0&byline=0&portrait=0'
        '&dnt=1&transparent=0';
  }

  void _initController(String embedUrl) {
    if (_controller != null) return;
    // iOS plays HTML5 video fullscreen unless the web view is created with
    // inline playback allowed — the flag is a CREATION parameter, so it cannot
    // be set after the fact the way the Android option below can. Without it
    // the player escapes our layout and the portrait/landscape rules that
    // follow the footage never get a chance to apply.
    final params = WebViewPlatform.instance is WebKitWebViewPlatform
        ? WebKitWebViewControllerCreationParams(
            allowsInlineMediaPlayback: true,
            mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
          )
        : const PlatformWebViewControllerCreationParams();
    final c = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..setUserAgent(_mobileUa)
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (err) {
          // Ignore sub-resource errors — only mark the whole load as failed
          // when the main frame itself fails. Vimeo pulls a lot of assets;
          // some ad/tracking pixels can 404 without breaking the player.
          if (err.isForMainFrame ?? true) {
            if (mounted) setState(() => _loadError = true);
          }
        },
        onPageFinished: (_) {
          if (mounted && _loadError) setState(() => _loadError = false);
        },
      ));
    // Android-specific: allow inline media playback without user gesture.
    if (c.platform is AndroidWebViewController) {
      (c.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
    c.loadRequest(
      Uri.parse(_fullEmbedUrl(embedUrl)),
      headers: const {'Referer': 'https://vimeo.com/'},
    );
    _controller = c;
  }

  Future<void> _enterFullscreen(VideoEntry v) async {
    setState(() => _fullscreen = true);
    // Rotate only for landscape footage — see the note at the top of the file.
    await SystemChrome.setPreferredOrientations(v.isPortraitVideo
        ? const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]
        : const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _exitFullscreen() async {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (mounted) setState(() => _fullscreen = false);
  }

  Future<void> _startLearning(BuildContext context) async {
    final blockDef = kAllBlocks
        .firstWhere((b) => b.no == widget.block, orElse: () => kAllBlocks.first);
    final ids = [
      for (var id = blockDef.firstId; id <= blockDef.lastId; id++) id
    ];
    ref.read(pendingSessionArgsProvider.notifier).value = PendingSessionArgs(
      wordIds: ids,
      selectedBlocks: {widget.block},
      excludeFirstOk: false,
      stage: kStageFirst,
    );
    if (mounted) context.go('/session');
  }

  @override
  Widget build(BuildContext context) {
    final videosAsync = ref.watch(videoRepoProvider);
    return videosAsync.when(
      loading: () => const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: Text('動画情報の読込エラー: $e')),
      ),
      data: (repo) {
        final v = repo.byBlock(widget.block);
        if (v == null) {
          return Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(title: Text('第${widget.block}ブロック 解説')),
            body: const Center(
                child: Text('このブロックの動画は登録されていません。')),
          );
        }
        _initController(v.embedUrl);
        return _fullscreen ? _buildFullscreen(v) : _buildPortrait(v);
      },
    );
  }

  // ── Fullscreen (landscape) ─────────────────────────────────────────

  Widget _buildFullscreen(VideoEntry v) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // Hardware/gesture back exits fullscreen instead of leaving the page.
        if (!didPop) _exitFullscreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Fit the player to the footage rather than stretching it: a
            // 9:16 video on a 9:19.5 phone must keep its shape, with the
            // black bars top and bottom rather than a distorted image.
            Center(
              child: AspectRatio(
                aspectRatio: v.aspect,
                child: _loadError
                    ? const _PlayerError()
                    : WebViewWidget(controller: _controller!),
              ),
            ),
            // Exit control — kept small and translucent so it never covers
            // the video content.
            Positioned(
              top: 8,
              right: 8,
              child: SafeArea(
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: IconButton(
                    onPressed: _exitFullscreen,
                    icon: const Icon(Icons.fullscreen_exit_rounded),
                    color: Colors.white,
                    iconSize: 28,
                    tooltip: '全画面を終了',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Portrait ───────────────────────────────────────────────────────

  Widget _buildPortrait(VideoEntry v) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2b6cb0),
        elevation: 0,
        title: Text('第${widget.block}ブロック 解説'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                _PlayerBox(
                  aspect: v.aspect,
                  child: _loadError
                      ? const _PlayerError()
                      : WebViewWidget(controller: _controller!),
                ),
                // Fullscreen affordance, bottom-right of the player.
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: IconButton(
                      onPressed: () => _enterFullscreen(v),
                      icon: const Icon(Icons.fullscreen_rounded),
                      color: Colors.white,
                      iconSize: 26,
                      tooltip: '全画面で見る',
                    ),
                  ),
                ),
              ],
            ),
            // Prominent full-width hint — the client specifically asked how
            // to make the video bigger, so the affordance is spelled out
            // rather than relying on the icon alone.
            InkWell(
              onTap: () => _enterFullscreen(v),
              child: Container(
                width: double.infinity,
                color: const Color(0xFFE6F4FF),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                        v.isPortraitVideo
                            ? Icons.fullscreen_rounded
                            : Icons.screen_rotation_rounded,
                        size: 18,
                        color: const Color(0xFF2b6cb0)),
                    const SizedBox(width: 8),
                    // Promising a rotation that will not happen is worse than
                    // saying nothing, so the wording follows the footage.
                    Text(
                      v.isPortraitVideo
                          ? 'タップすると全画面で大きく見られます'
                          : 'タップすると全画面（横向き）で大きく見られます',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A365D),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _InfoStrip(video: v),
            const Spacer(),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: SizedBox(
                height: 56,
                child: FilledButton.icon(
                  onPressed: () => _startLearning(context),
                  icon: const Icon(Icons.school_outlined),
                  label: const Text('このブロックの学習を始める',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2b6cb0),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The player, sized to the footage but never so tall that the block's
/// learning button is pushed off the screen. A 9:16 video at full width would
/// be about 1.8x the phone's height, so vertical footage is bound by height
/// and centred, with the leftover width left blank.
class _PlayerBox extends StatelessWidget {
  final double aspect;
  final Widget child;
  const _PlayerBox({required this.aspect, required this.child});

  /// Share of the screen the player may occupy before it starts crowding out
  /// the info strip and the 学習を始める button beneath it.
  static const _maxScreenFraction = 0.62;

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * _maxScreenFraction;
    return LayoutBuilder(builder: (context, c) {
      var w = c.maxWidth;
      var h = w / aspect;
      if (h > maxH) {
        h = maxH;
        w = h * aspect;
      }
      return Container(
        width: double.infinity,
        height: h,
        color: Colors.black,
        alignment: Alignment.center,
        child: SizedBox(width: w, height: h, child: child),
      );
    });
  }
}

class _InfoStrip extends StatelessWidget {
  final VideoEntry video;
  const _InfoStrip({required this.video});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE6F4FF),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('vol.${video.vol}',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2b6cb0))),
          ),
          const SizedBox(width: 10),
          Text(
            '№ ${video.firstWordId ?? "?"}〜${video.lastWordId ?? "?"}',
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const Spacer(),
          if (video.durationLabel.isNotEmpty)
            Text('約 ${video.durationLabel}',
                style: const TextStyle(
                    fontSize: 12, color: Colors.black45)),
        ],
      ),
    );
  }
}

class _PlayerError extends ConsumerWidget {
  const _PlayerError();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivityAsync =
        ref.watch(StreamProvider<List<ConnectivityResult>>(
      (ref) => Connectivity().onConnectivityChanged,
    ));
    final isOnline = connectivityAsync.maybeWhen(
      data: (r) => r.any((x) => x != ConnectivityResult.none),
      orElse: () => true,
    );
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.white70, size: 40),
            const SizedBox(height: 12),
            Text(
              isOnline
                  ? '動画が読み込めませんでした。時間をおいて再度お試しください。'
                  : 'インターネット接続が必要です。ネットワーク接続を確認してください。',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
