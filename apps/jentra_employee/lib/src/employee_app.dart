import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

import 'data/employee_gateway.dart';
import 'data/employee_push.dart';
import 'employee_controller.dart';
import 'l10n/employee_strings.dart';
import 'ui/employee_components.dart';
import 'ui/employee_shell.dart';
import 'ui/employee_theme.dart';
import 'ui/onboarding_screens.dart';
import 'ui/settings_screen.dart';
import 'ui/employee_push_settings.dart';
import 'ui/sign_in_screen.dart';

class EmployeeApp extends StatefulWidget {
  const EmployeeApp({
    required this.controller,
    this.initialThemeMode = ThemeMode.system,
    this.initialLocale = const Locale('en'),
    this.observeLifecycle = true,
    this.onPreferencesChanged,
    this.push,
    this.mfaPanel,
    super.key,
  });
  final EmployeeController controller;
  final EmployeePushCoordinator? push;
  final Widget? mfaPanel;
  final ThemeMode initialThemeMode;
  final Locale initialLocale;
  final bool observeLifecycle;
  final Future<void> Function(ThemeMode theme, Locale locale)?
  onPreferencesChanged;
  @override
  State<EmployeeApp> createState() => _EmployeeAppState();
}

class _EmployeeAppState extends State<EmployeeApp> with WidgetsBindingObserver {
  late ThemeMode _theme = widget.initialThemeMode;
  late Locale _locale = widget.initialLocale;

  @override
  void initState() {
    super.initState();
    if (widget.observeLifecycle) WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    if (widget.observeLifecycle) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.resume());
    } else {
      widget.controller.background();
    }
  }

  void _preferences(ThemeMode theme, Locale locale) {
    setState(() {
      _theme = theme;
      _locale = locale;
    });
    final save = widget.onPreferencesChanged;
    if (save != null) {
      unawaited(
        save(theme, locale).catchError((Object _) {
          // Preferences are nonsensitive. Current choices remain in effect this session.
        }),
      );
    }
  }

  void _settings(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => EmployeeSettingsScreen(
        themeMode: _theme,
        locale: _locale,
        onChanged: _preferences,
        notifications: EmployeePushSettings(
          coordinator: widget.push,
          authorized: () =>
              widget.controller.phase == EmployeePhase.ready &&
              widget.controller.identity != null,
          onRefresh: widget.controller.refresh,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      // A private navigator belongs to one currently authorized employee. A lock,
      // account change or scope change destroys all prior private routes/forms.
      final routeOwner =
          controller.phase == EmployeePhase.ready && controller.identity != null
          ? 'employee:${controller.identity!.key}:${controller.privateRouteVersion}'
          : 'public:${controller.phase.name}';
      return MaterialApp(
        key: ValueKey(routeOwner),
        debugShowCheckedModeBanner: false,
        title: 'Jentra Employee',
        theme: employeeTheme(Brightness.light),
        darkTheme: employeeTheme(Brightness.dark),
        themeMode: _theme,
        locale: _locale,
        supportedLocales: const [Locale('en'), Locale('si'), Locale('ta')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) {
          final s = EmployeeStrings.of(context);
          return LayoutBuilder(
            builder: (context, constraints) => Column(
              children: [
                if (controller.error?.code == 'MFA_REQUIRED' &&
                    widget.mfaPanel != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * .6,
                    ),
                    child: SingleChildScrollView(child: widget.mfaPanel!),
                  ),
                if (controller.notice != null)
                  ConstrainedBox(
                    // Long translated notices must not consume the private
                    // navigator on a short screen or with enlarged text.
                    // Keep the complete message available by scrolling it.
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * .3,
                    ),
                    child: Material(
                      child: SafeArea(
                        bottom: false,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(8),
                          child: Semantics(
                            liveRegion: true,
                            child: EmployeeMessage(
                              title: s.notice(controller.notice!),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Expanded(child: child ?? const SizedBox.shrink()),
              ],
            ),
          );
        },
        home: Builder(
          builder: (context) {
            final s = EmployeeStrings.of(context);
            return switch (controller.phase) {
              EmployeePhase.ready => EmployeeShell(
                controller: controller,
                onSettings: () => _settings(context),
              ),
              EmployeePhase.chooseWorkspace => EmployeeWorkspaceScreen(
                controller: controller,
                onSettings: () => _settings(context),
              ),
              EmployeePhase.linkRequired => EmployeeLinkScreen(
                controller: controller,
                onSettings: () => _settings(context),
              ),
              EmployeePhase.loading => Scaffold(
                body: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          JentraBrandMark(size: 56),
                          const SizedBox(height: 32),
                          const CircularProgressIndicator(),
                          const SizedBox(height: 24),
                          Text(s('loading'), textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              EmployeePhase.locked => Scaffold(
                body: SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: JentraBrandMark(size: 56),
                            ),
                            const SizedBox(height: 32),
                            EmployeeHeading(s('locked'), large: true),
                            const SizedBox(height: 16),
                            Text(s('lockedCopy')),
                            if (controller.error != null) ...[
                              const SizedBox(height: 20),
                              EmployeeMessage(
                                title: s.failure(controller.error!),
                                error: true,
                              ),
                            ],
                            const SizedBox(height: 24),
                            FilledButton(
                              onPressed: controller.busy
                                  ? null
                                  : controller.resume,
                              child: Text(s('continue')),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: controller.busy
                                  ? null
                                  : controller.signOut,
                              child: Text(s('signOut')),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              EmployeePhase.unconfigured || EmployeePhase.signedOut => Stack(
                children: [
                  EmployeeSignInScreen(
                    connected: controller.phase != EmployeePhase.unconfigured,
                    busy: controller.busy,
                    error: controller.error == null
                        ? null
                        : s.failure(controller.error!),
                    onSignIn: controller.signIn,
                  ),
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8, top: 16),
                        child: IconButton(
                          tooltip: s('settings'),
                          onPressed: () => _settings(context),
                          icon: const Icon(Icons.tune),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            };
          },
        ),
      );
    },
  );
}
