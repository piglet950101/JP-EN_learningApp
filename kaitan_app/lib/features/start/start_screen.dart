// ① Start screen — bright, broadly appealing redesign per client review v1.2
// (2026-06-02).
//
// Visual direction:
//   • warm cream → soft sky-blue gradient background
//   • 快単 title large and friendly, with a tagline that conveys the method
//   • Stage cards: First stage = inviting filled card with soft shadow;
//     Second stage = elegant "coming soon" card with the same shape
//   • ★5 row directly beneath each stage card
//   • Bottom: small accumulated-progress badge (回転数 + 累計OK語数 if any)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../data/progress/progress_repository.dart';

class StartScreen extends ConsumerWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lapsAsync = ref.watch(lapCountProvider(kStageFirst));
    return Scaffold(
      // Bright, warm gradient background — replaces the flat white.
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFF8E7), // cream
              Color(0xFFE6F4FF), // soft sky blue
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // ── Header ──────────────────────────────────────────
                    Column(
                      children: [
                        const SizedBox(height: 32),
                        // Title with playful warmth.
                        Text(
                          '快単',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 64,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF2b6cb0),
                            letterSpacing: 2,
                            shadows: [
                              Shadow(
                                color: const Color(0xFF2b6cb0).withValues(alpha: 0.15),
                                offset: const Offset(0, 4),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '英単語記憶アプリ',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF4A5568),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Tagline — sets a welcoming, methodical tone.
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: const Color(0xFFCBD5E0), width: 1),
                          ),
                          child: const Text(
                            '見聞きした瞬間に答えが出る、絶対記憶を作る。',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF2D3748),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // ── Stage choices ──────────────────────────────────
                    Column(
                      children: [
                        _StageCard(
                          label: 'First Stage',
                          subtitle: '2,201語の見出し語を絶対記憶に',
                          enabled: true,
                          onTap: () => context.push('/range'),
                        ),
                        const SizedBox(height: 10),
                        lapsAsync.when(
                          loading: () => const _StarRow(silver: 0, gold: 0),
                          error: (_, _) => const _StarRow(silver: 0, gold: 0),
                          data: (laps) => Column(
                            children: [
                              _StarRow(
                                silver: _silvers(laps),
                                gold: _golds(laps),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$laps回転',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF4A5568),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        _StageCard(
                          label: 'Second Stage',
                          subtitle: '2番目の意味・派生語・反対語',
                          enabled: false,
                          comingSoon: true,
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Second Stage は準備中です'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        const _StarRow(silver: 0, gold: 0),
                      ],
                    ),
                    // ── Bottom note ────────────────────────────────────
                    const Padding(
                      padding: EdgeInsets.only(top: 16, bottom: 8),
                      child: Text(
                        '快単 © 一般社団法人KAI',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF718096),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static int _golds(int laps) =>
      laps <= 5 ? 0 : (laps >= 10 ? 5 : laps - 5);
  static int _silvers(int laps) =>
      laps <= 0 ? 0 : (laps >= 10 ? 0 : (laps <= 5 ? laps : 10 - laps));
}

class _StageCard extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool enabled;
  final bool comingSoon;
  final VoidCallback onTap;
  const _StageCard({
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
    this.comingSoon = false,
  });

  @override
  Widget build(BuildContext context) {
    final base =
        enabled ? const Color(0xFF2b6cb0) : const Color(0xFFA0AEC0);
    final fg = enabled ? Colors.white : Colors.white;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: enabled
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2b6cb0), Color(0xFF3182CE)],
                  )
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [base, base.withValues(alpha: 0.7)],
                  ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              if (enabled)
                BoxShadow(
                  color: base.withValues(alpha: 0.30),
                  offset: const Offset(0, 6),
                  blurRadius: 18,
                ),
            ],
          ),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(label,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: fg,
                              )),
                          if (comingSoon) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('準備中',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(subtitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: fg.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w500,
                          )),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_rounded, color: fg, size: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StarRow extends StatelessWidget {
  final int silver;
  final int gold;
  const _StarRow({required this.silver, required this.gold});

  @override
  Widget build(BuildContext context) {
    final stars = <Widget>[];
    for (var i = 0; i < 5; i++) {
      Color c;
      if (i < gold) {
        c = const Color(0xFFD4AF37);
      } else if (i < gold + silver) {
        c = const Color(0xFFA8A8A8);
      } else {
        c = const Color(0xFFCBD5E0); // unearned — soft gray, not jarring
      }
      stars.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Icon(Icons.star_rounded, color: c, size: 30),
      ));
    }
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: stars);
  }
}
