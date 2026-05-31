import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tandem/core/branding/branding.g.dart';
import 'package:tandem/core/router/router.dart';
import 'package:tandem/core/theme/app_theme.dart';

class TandemApp extends ConsumerWidget {
  const TandemApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: Branding.name,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
