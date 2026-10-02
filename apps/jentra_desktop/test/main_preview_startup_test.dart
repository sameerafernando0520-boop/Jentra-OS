import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:jentra_desktop/main.dart' as entrypoint;
import 'package:jentra_desktop/src/app.dart';

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
}
