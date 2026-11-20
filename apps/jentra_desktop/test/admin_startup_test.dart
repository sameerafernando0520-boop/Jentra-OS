import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_desktop/main_admin.dart' as entrypoint;
import 'package:jentra_desktop/src/features/platform_control/admin_app.dart';
import 'package:jentra_desktop/src/startup_error_app.dart';

void main() {
  testWidgets('J panel startup failure shows an error instead of a blank window', (
    tester,
  ) async {
    await entrypoint.launchAdministrator(
      configuration: const RuntimeConfig(
        environment: 'unknown',
        supabaseUrl: 'https://aaaaaaaaaaaaaaaaaaaa.supabase.co',
        supabasePublishableKey: 'sb_publishable_fixture',
      ),
      isRelease: true,
    );
    await tester.pumpAndSettle();
    expect(find.byType(JentraStartupErrorApp), findsOneWidget);
    expect(find.byType(JentraAdministratorApp), findsNothing);
    expect(find.text('Support code: invalidEnvironment'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('released J panel without a connection reports it at startup', (
    tester,
  ) async {
    var networkCalls = 0;
    await HttpOverrides.runZoned(
      () => entrypoint.launchAdministrator(
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
    expect(find.byType(JentraAdministratorApp), findsNothing);
    expect(find.text('Support code: missingConnection'), findsOneWidget);
    expect(networkCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('debug J panel without a connection keeps the preview notice', (
    tester,
  ) async {
    await entrypoint.launchAdministrator(
      configuration: const RuntimeConfig(
        environment: 'development',
        supabaseUrl: '',
        supabasePublishableKey: '',
      ),
      isRelease: false,
    );
    await tester.pumpAndSettle();
    expect(find.byType(JentraAdministratorApp), findsOneWidget);
    expect(
      find.text(
        'Open the J panel build configured for your internal Supabase project.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
