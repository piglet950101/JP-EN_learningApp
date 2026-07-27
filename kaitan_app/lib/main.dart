// kaitan — 「快単」 English-vocab memorization app.
// Routes: ① Start → ②③ Range → ⑥⑦/⑩/⑪ Session.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';

void main() {
  runApp(const ProviderScope(child: KaitanApp()));
}

class KaitanApp extends ConsumerWidget {
  const KaitanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: '快単',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2b6cb0),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.white,
        fontFamily: 'Yu Gothic',
      ),
      routerConfig: ref.watch(routerProvider),
      debugShowCheckedModeBanner: false,
    );
  }
}
