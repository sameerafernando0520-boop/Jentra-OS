import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/platform_control/admin_app.dart';
import 'package:jentra_desktop/src/features/platform_control/platform_organization_screen.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// The SDK otherwise decodes Edge responses on a separate isolate.
// ignore: depend_on_referenced_packages
import 'package:yet_another_json_isolate/yet_another_json_isolate.dart';

void main() {
  testWidgets('operator switches a package module on', (tester) async {
    final calls = <String, Map<String, Object?>>{};
    await _open(tester, calls);
    await tester.tap(find.text('Organizations & plans'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Edit modules'));
    await tester.tap(find.byTooltip('Edit modules'));
    await tester.pumpAndSettle();
    expect(find.text('Modules for Starter'), findsOneWidget);
    for (final label in [
      'People (HR)',
      'Field Sales',
      'Finance',
      'Assets',
      'Projects',
      'Service',
      'Analytics',
      'AI',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'People (HR)'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('On').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(calls['platform_save_package_modules'], {
      'p_code': 'starter',
      'p_modules': {
        'module.people': true,
        'module.field_sales': true,
        'module.finance': false,
        'module.assets': false,
        'module.projects': false,
        'module.service': false,
        'analytics': false,
        'module.ai': false,
      },
      'p_expected_revision': 4,
    });
    expect(find.text('Modules for Starter'), findsNothing);
    expect(find.text('Package modules saved.'), findsOneWidget);
  });

  testWidgets('a stale module form reports the change and stays open', (
    tester,
  ) async {
    final calls = <String, Map<String, Object?>>{};
    await _open(tester, calls, saveModulesError: 'PACKAGE_CHANGED');
    await tester.tap(find.text('Organizations & plans'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Edit modules'));
    await tester.tap(find.byTooltip('Edit modules'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Modules for Starter'), findsOneWidget);
    expect(
      find.text(
        'Pricing changed. Close this form and refresh before confirming.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('operator changes the creation rule with a reason', (
    tester,
  ) async {
    final calls = <String, Map<String, Object?>>{};
    await _open(tester, calls);
    await tester.tap(find.text('Creation rule'));
    await tester.pumpAndSettle();
    expect(find.text('Who can create an organization'), findsOneWidget);
    expect(find.text('Provider only'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter reason for change.'), findsOneWidget);
    expect(calls.containsKey('platform_set_checkout_enforcement'), isFalse);

    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'Creation rule'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open self-service').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Reason for change'),
      'Pilot with a partner',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(calls['platform_set_checkout_enforcement'], {
      'p_enforce': false,
      'p_reason': 'Pilot with a partner',
    });
    expect(find.text('Creation rule saved.'), findsOneWidget);
  });
}

Future<void> _open(
  WidgetTester tester,
  Map<String, Map<String, Object?>> calls, {
  String? saveModulesError,
}) async {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(() async {
    final client = _client(calls, saveModulesError: saveModulesError);
    addTearDown(client.dispose);
    await client.auth.signInWithPassword(
      email: 'operator@example.test',
      password: 'synthetic-test-password',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          foundationGatewayProvider.overrideWithValue(
            SupabaseFoundationGateway(client),
          ),
          platformOrganizationGatewayProvider.overrideWithValue(
            PlatformOrganizationGateway(client),
          ),
        ],
        child: const JentraAdministratorApp(),
      ),
    );
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
}

SupabaseClient _client(
  Map<String, Map<String, Object?>> calls, {
  String? saveModulesError,
}) => SupabaseClient(
  'https://example.test',
  'synthetic-public-key',
  isolate: _TestJsonCodec(),
  authOptions: const AuthClientOptions(autoRefreshToken: false),
  httpClient: MockClient((request) async {
    final function = request.url.pathSegments.last;
    if (request.body.isNotEmpty && function.startsWith('platform_')) {
      calls[function] = Map<String, Object?>.from(
        jsonDecode(request.body) as Map,
      );
    }
    if (function == 'platform_save_package_modules' &&
        saveModulesError != null) {
      return http.Response(
        jsonEncode({'code': '40001', 'message': saveModulesError}),
        409,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    }
    final body = switch (function) {
      'token' => _session(),
      'org-identity' => {'has_password': true, 'recovery_verified': true},
      'platform_organization_assignment' => true,
      'platform_list_organizations' ||
      'platform_organization_cleanup_pending' ||
      'platform_organization_archive_history' ||
      'platform_subscription_checkout_queue' => <Object?>[],
      'platform_list_packages' => [
        {
          'code': 'starter',
          'name': 'Starter',
          'status': 'active',
          'price_minor': 250000,
          'currency_code': 'LKR',
          'trial_days': 30,
          'revision': 4,
        },
      ],
      'platform_package_modules' => [
        {
          'code': 'starter',
          'revision': 4,
          'modules': {
            'module.people': false,
            'module.field_sales': true,
            'module.finance': false,
            'module.assets': false,
            'module.projects': false,
            'module.service': false,
            'analytics': false,
            'module.ai': false,
          },
        },
      ],
      'platform_subscription_checkout_settings' => {
        'enabled': false,
        'enforce_checkout': true,
        'bank': null,
      },
      'platform_save_package_modules' ||
      'platform_set_checkout_enforcement' => null,
      _ => throw StateError('Unexpected test request $function'),
    };
    return http.Response(
      jsonEncode(body),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }),
);

final class _TestJsonCodec extends Fake implements YAJsonIsolate {
  @override
  Future<dynamic> decode(String json) async => jsonDecode(json);

  @override
  Future<String> encode(Object? json) async => jsonEncode(json);
}

Map<String, Object?> _session() {
  final claims = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'sub': 'operator',
            'aal': 'aal2',
            'exp':
                DateTime.now()
                    .add(const Duration(hours: 1))
                    .millisecondsSinceEpoch ~/
                1000,
          }),
        ),
      )
      .replaceAll('=', '');
  return {
    'access_token': 'eyJhbGciOiJIUzI1NiJ9.$claims.synthetic-signature',
    'refresh_token': 'synthetic-refresh',
    'expires_in': 3600,
    'token_type': 'bearer',
    'user': {
      'id': 'operator',
      'aud': 'authenticated',
      'app_metadata': <String, Object?>{},
      'user_metadata': <String, Object?>{},
      'created_at': '2026-09-11T00:00:00Z',
    },
  };
}
