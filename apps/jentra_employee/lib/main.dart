import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/data/employee_gateway.dart';
import 'src/data/employee_storage.dart';
import 'src/employee_app.dart';
import 'src/employee_configuration.dart';
import 'src/employee_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const config = EmployeeConfiguration.fromEnvironment();
  final secureStore = NativeEmployeeKeyValueStore();
  final authStorage = EmployeeAuthStorage(secureStore);
  EmployeeGateway? gateway;
  EmployeeFailure? setupError;
  if (config.isValid && !kIsWeb) {
    try {
      await Supabase.initialize(
        url: config.url,
        publishableKey: config.publishableKey,
        authOptions: FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          localStorage: authStorage,
          pkceAsyncStorage: EmployeePkceStorage(secureStore),
          detectSessionInUri: false,
        ),
      );
      gateway = SupabaseEmployeeGateway(
        Supabase.instance.client,
        authStorage: authStorage,
      );
    } on Object {
      setupError = const EmployeeFailure(
        'APP_SETUP_UNAVAILABLE',
        'The app could not open protected account storage. Unlock your device and restart the app.',
      );
    }
  }
  SharedPreferences? preferences;
  try {
    preferences = await SharedPreferences.getInstance();
  } on Object {
    /* Session still works without appearance preferences. */
  }
  final savedLanguage = preferences?.getString('employee.language');
  final locale = Locale(
    {'en', 'si', 'ta'}.contains(savedLanguage) ? savedLanguage! : 'en',
  );
  final theme = switch (preferences?.getString('employee.theme')) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
  final controller = EmployeeController(
    gateway: gateway,
    draftStore: EmployeeDraftStore(secureStore),
  );
  controller.error = setupError;
  runApp(
    EmployeeApp(
      controller: controller,
      initialThemeMode: theme,
      initialLocale: locale,
      onPreferencesChanged: (theme, locale) async {
        await preferences?.setString('employee.theme', theme.name);
        await preferences?.setString('employee.language', locale.languageCode);
      },
    ),
  );
  if (gateway != null) unawaited(controller.start());
}
