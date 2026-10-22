import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:jentra_desktop/main.dart' as entrypoint;
import 'package:jentra_desktop/src/app.dart';
import 'package:jentra_desktop/src/startup_error_app.dart';

void main() {
  testWidgets(
    'unconfigured startup renders a preview without native stores or a backend',
    (tester) async {
      // This test intentionally covers only the existing no-backend startup path.
      expect(RuntimeConfig.fromEnvironment().isSupabaseConfigured, isFalse);
      final previous = SharedPreferencesAsyncPlatform.instance;
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
      var credentialCalls = 0, pathCalls = 0;
      const credentials = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(credentials, (_) async {
        credentialCalls++;
        throw StateError('Native credential access is forbidden in this test');
      });
      messenger.setMockMethodCallHandler(paths, (_) async {
        pathCalls++;
        throw StateError(
          'Native local database access is forbidden in this test',
        );
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(credentials, null);
        messenger.setMockMethodCallHandler(paths, null);
      });
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await HttpOverrides.runZoned(
        entrypoint.main,
        createHttpClient: (_) =>
            throw StateError('Network disabled for preview startup'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(JentraApp), findsOneWidget);
      expect(find.byType(MaterialApp), findsOneWidget);
      expect(credentialCalls, 0);
      expect(pathCalls, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'release without configuration blocks before workspace or native stores',
    (tester) async {
      var nativeCalls = 0, networkCalls = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const credentials = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      for (final channel in [credentials, paths]) {
        messenger.setMockMethodCallHandler(channel, (_) async {
          nativeCalls++;
          throw StateError('Native stores must not initialize');
        });
      }
      addTearDown(() {
        messenger.setMockMethodCallHandler(credentials, null);
        messenger.setMockMethodCallHandler(paths, null);
      });
      await HttpOverrides.runZoned(
        () => entrypoint.launchJentra(
          configuration: const RuntimeConfig(
            environment: 'development',
            supabaseUrl: '',
            supabasePublishableKey: '',
          ),
          isRelease: true,
        ),
        createHttpClient: (_) {
          networkCalls++;
          throw StateError('Network must not initialize');
        },
      );
      await tester.pumpAndSettle();
      expect(find.byType(JentraStartupErrorApp), findsOneWidget);
      expect(find.byType(JentraApp), findsNothing);
      expect(
        find.text('This installation is missing its workspace connection.'),
        findsOneWidget,
      );
      expect(find.text('Support code: missingConnection'), findsOneWidget);
      expect(find.text('Jentra Holdings'), findsNothing);
      expect(nativeCalls, 0);
      expect(networkCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid client key renders a fixed error without exposing values',
    (tester) async {
      const private = 'sb_secret_do-not-display-this-fixture';
      await entrypoint.launchJentra(
        configuration: const RuntimeConfig(
          environment: 'production',
          supabaseUrl: 'https://aaaaaaaaaaaaaaaaaaaa.supabase.co',
          supabasePublishableKey: private,
          supabaseProjectRef: 'aaaaaaaaaaaaaaaaaaaa',
        ),
        isRelease: true,
      );
      await tester.pumpAndSettle();
      expect(find.byType(JentraStartupErrorApp), findsOneWidget);
      expect(find.byType(JentraApp), findsNothing);
      expect(find.text('Support code: invalidPublicKey'), findsOneWidget);
      expect(find.textContaining(private), findsNothing);
      expect(find.text('Try again'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
