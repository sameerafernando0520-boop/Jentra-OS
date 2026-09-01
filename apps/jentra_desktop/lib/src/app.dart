import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

import 'app_providers.dart';
import 'router.dart';

class JentraApp extends ConsumerWidget {
  const JentraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences =
        ref.watch(appPreferencesProvider).value ??
        const AppPreferences(
          themeMode: ThemeMode.light,
          density: JentraDensity.comfortable,
        );
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Jentra OS',
      debugShowCheckedModeBanner: false,
      themeMode: preferences.themeMode,
      theme: JentraTheme.light(density: preferences.density),
      darkTheme: JentraTheme.dark(density: preferences.density),
      routerConfig: router,
    );
  }
}
