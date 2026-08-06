import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_os/app/app.dart';
import 'package:jentra_os/core/config/app_providers.dart';
import 'package:jentra_os/core/config/env_config.dart';

void main() {
  testWidgets('shows safe setup guidance when configuration is absent', (
    tester,
  ) async {
    const config = EnvConfig(
      name: 'test',
      supabaseUrl: '',
      supabaseAnonKey: '',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          envConfigProvider.overrideWithValue(config),
          supabaseClientProvider.overrideWithValue(null),
          startupFailureProvider.overrideWithValue(null),
        ],
        child: const JentraOSApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Environment setup required'), findsOneWidget);
    expect(find.textContaining('service-role key'), findsOneWidget);
  });
}
