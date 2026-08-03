// Video detail — embedded Vimeo WebView player for one block.
//
// Below the 16:9 player, a small info row shows the block's headword-id
// range and a shortcut button that jumps into that block's First Stage
// learning flow.

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

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

  void _initController(String embedUrl) {
    if (_controller != null) return;
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (_) => setState(() => _loadError = true),
      ))
      ..loadRequest(Uri.parse(embedUrl));
    _controller = c;
  }

  Future<void> _startLearning(BuildContext context) async {
    final blockDef =
        kAllBlocks.firstWhere((b) => b.no == widget.block, orElse: () => kAllBlocks.first);
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2b6cb0),
        elevation: 0,
        title: Text('第${widget.block}ブロック 解説'),
      ),
      body: videosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('動画情報の読込エラー: $e')),
        data: (repo) {
          final v = repo.byBlock(widget.block);
          if (v == null) {
            return const Center(
                child: Text('この block の動画は登録されていません。'));
          }
          _initController(v.embedUrl);
          return SafeArea(
            child: Column(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _loadError
                      ? const _PlayerError()
                      : WebViewWidget(controller: _controller!),
                ),
                _InfoStrip(video: v),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 16),
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
          );
        },
      ),
    );
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
