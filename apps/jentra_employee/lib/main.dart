import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/data/employee_gateway.dart';
import 'src/data/employee_storage.dart';
import 'src/data/employee_storage_factory.dart';
import 'src/data/employee_photo_factory.dart';
import 'src/data/employee_push.dart';
import 'src/data/employee_mfa.dart';
import 'src/ui/employee_mfa_panel.dart';
import 'src/employee_app.dart';
import 'src/employee_configuration.dart';
import 'src/employee_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const config = EmployeeConfiguration.fromEnvironment();
  final secureStore = config.isValid
      ? createEmployeeKeyValueStore(projectUrl: config.url)
      : NativeEmployeeKeyValueStore();
  final authStorage = EmployeeAuthStorage(secureStore);
  EmployeeGateway? gateway;
  EmployeeFailure? setupError;
  if (config.isValid) {
    try {
      await secureStore.read('jentra.employee.storage.check.v1');
      await Supabase.initialize(
        url: config.url,
        publishableKey: config.publishableKey,
        authOptions: FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          localStorage: authStorage,
          pkceAsyncStorage: EmployeePkceStorage(secureStore),
          detectSessionInUri: kIsWeb,
        ),
      );
      gateway = SupabaseEmployeeGateway(
        Supabase.instance.client,
        authStorage: authStorage,
      );
    } on EmployeeFailure catch (failure) {
      setupError = failure;
    } on Object {
      setupError = const EmployeeFailure(
        'APP_SETUP_UNAVAILABLE',
        'The app could not open protected account storage. Check this browser or device and restart the app.',
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
  EmployeePushCoordinator? push;
  final controller = EmployeeController(
    gateway: gateway,
    draftStore: EmployeeDraftStore(secureStore),
    photoPicker: createEmployeePhotoPicker(),
    beforeIdentityChange: () async {
      await push?.disconnect();
    },
  );
  if (gateway is SupabaseEmployeeGateway) {
    try {
      final transport = await AndroidEmployeePushTransport.initialize();
      if (transport != null) {
        push = EmployeePushCoordinator(
          transport: transport,
          repository: SupabaseEmployeePushRepository(gateway.client),
          store: secureStore,
          currentIdentity: () => controller.phase == EmployeePhase.ready
              ? controller.identity
              : null,
        );
        controller.addListener(() {
          unawaited(push?.reconcile());
        });
        var previousActor = gateway.actorId;
        gateway.actorChanges.listen((actor) {
          if (actor != previousActor) {
            previousActor = actor;
            unawaited(push?.disconnect().catchError((Object _) {}));
          }
        });
      }
    } on Object {
      /* Messaging setup cannot prevent protected employee sign-in. */
    }
  }
  controller.error = setupError;
  runApp(
    EmployeeApp(
      controller: controller,
      push: push,
      mfaPanel: gateway is SupabaseEmployeeGateway
          ? EmployeeMfaPanel(
              gateway: SupabaseEmployeeMfaGateway(gateway.client),
              onVerified: controller.start,
            )
          : null,
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
