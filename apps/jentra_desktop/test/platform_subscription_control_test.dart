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
  testWidgets('unconfigured admin build opens its own entry point', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: JentraAdministratorApp()),
    );
    expect(find.text('J panel'), findsOneWidget);
    expect(
      find.text(
        'Open the J panel build configured for your internal Supabase project.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('tenant users cannot load the admin queue', (tester) async {
    await tester.runAsync(() async {
      final client = _client(
        assigned: false,
        onQueue: () => fail('Unauthorized order read'),
      );
      addTearDown(client.dispose);
      await _signIn(client);
      await tester.pumpWidget(_app(client));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(find.text('Platform operator access required.'), findsOneWidget);
    expect(find.text('Subscription orders'), findsNothing);
    expect(find.byTooltip('Account security'), findsNothing);
  });

  testWidgets('operator can verify a recovery mailbox in J panel', (
    tester,
  ) async {
    final actions = <Map<String, Object?>>[];
    await tester.runAsync(() async {
      final client = _client(
        assigned: true,
        onQueue: () => 1,
        onIdentity: (body) {
          actions.add(body);
          return body['action'] == 'operator_profile'
              ? {'has_password': true, 'recovery_verified': false}
              : {'ok': true};
        },
      );
      addTearDown(client.dispose);
      await _signIn(client);
      await tester.pumpWidget(_app(client));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Account security'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add recovery email'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('account-current-password')),
      'synthetic-test-password',
    );
    await tester.enterText(
      find.byKey(const ValueKey('account-recovery-email')),
      'recovery@example.test',
    );
    await tester.tap(find.text('Send verification code'));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter the code sent to recovery@example.test.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('account-verification-code')),
      '12345678',
    );
    await tester.tap(find.text('Verify email'));
    await tester.pumpAndSettle();
    expect(actions, [
      {'action': 'operator_profile'},
      {
        'action': 'request_operator_recovery_email',
        'email': 'recovery@example.test',
        'current_password': 'synthetic-test-password',
      },
      {'action': 'verify_operator_recovery_email', 'code': '12345678'},
    ]);
  });

  testWidgets(
    'Forgot password uses operator endpoints with a neutral acknowledgement',
    (tester) async {
      final actions = <Map<String, Object?>>[];
      final client = _client(
        assigned: false,
        onQueue: () => fail('Unexpected order read'),
        onIdentity: (body) {
          actions.add(body);
          return {'ok': true};
        },
      );
      addTearDown(client.dispose);
      await tester.pumpWidget(_app(client));
      await tester.tap(find.text('Forgot password'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('reset-login')),
        'operator@example.test',
      );
      await tester.tap(find.text('Send reset code'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('If the account has a registered recovery email'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('reset-code')),
        '12345678',
      );
      await tester.enterText(
        find.byKey(const ValueKey('reset-password')),
        'New-Password-121',
      );
      await tester.enterText(
        find.byKey(const ValueKey('reset-confirmation')),
        'New-Password-121',
      );
      await tester.tap(find.text('Reset password'));
      await tester.pumpAndSettle();
      expect(
        find.text('Password reset. Sign in with your new password.'),
        findsOneWidget,
      );
      expect(actions, [
        {'action': 'request_operator_reset', 'login': 'operator@example.test'},
        {
          'action': 'reset_operator_password',
          'login': 'operator@example.test',
          'code': '12345678',
          'new_password': 'New-Password-121',
        },
      ]);
    },
  );

  testWidgets('assigned AAL2 operator sees refreshed orders after 15 seconds', (
    tester,
  ) async {
    late SupabaseClient client;
    var queueReads = 0;
    await tester.runAsync(() async {
      client = _client(assigned: true, onQueue: () => ++queueReads);
      addTearDown(client.dispose);
      await _signIn(client);
      await tester.pumpWidget(_app(client));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(find.text('Company 1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(queueReads, 2);
    expect(find.text('Company 2'), findsOneWidget);
  });

  testWidgets('mismatched transfer cannot be confirmed in the panel', (
    tester,
  ) async {
    var reviews = 0;
    await tester.runAsync(() async {
      final client = _client(
        assigned: true,
        onQueue: () => 1,
        onReview: () => reviews++,
      );
      addTearDown(client.dispose);
      await _signIn(client);
      await tester.pumpWidget(_app(client));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Company 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verify payment'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'different-reference');
    await tester.enterText(fields.at(1), '2500');
    await tester.enterText(fields.at(2), '2026-10-01 10:00:00');
    await tester.tap(find.text('Confirm payment'));
    await tester.pumpAndSettle();
    expect(reviews, 0);
    expect(find.textContaining('does not match this order'), findsOneWidget);
  });
}

Future<void> _signIn(SupabaseClient client) async {
  await client.auth.signInWithPassword(
    email: 'operator@example.test',
    password: 'synthetic-test-password',
  );
}

ProviderScope _app(SupabaseClient client) => ProviderScope(
  overrides: [
    foundationGatewayProvider.overrideWithValue(
      SupabaseFoundationGateway(client),
    ),
    platformOrganizationGatewayProvider.overrideWithValue(
      PlatformOrganizationGateway(client),
    ),
  ],
  child: const JentraAdministratorApp(),
);

SupabaseClient _client({
  required bool assigned,
  required int Function() onQueue,
  void Function()? onReview,
  Object? Function(Map<String, Object?>)? onIdentity,
}) {
  return SupabaseClient(
    'https://example.test',
    'synthetic-public-key',
    isolate: _TestJsonCodec(),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((request) async {
      final function = request.url.pathSegments.last;
      if (function == 'platform_review_subscription_payment') onReview?.call();
      final body = switch (function) {
        'token' => _session(),
        'org-identity' => onIdentity!.call(
          Map<String, Object?>.from(jsonDecode(request.body) as Map),
        ),
        'platform_organization_assignment' => assigned,
        'platform_list_organizations' ||
        'platform_list_packages' ||
        'platform_organization_cleanup_pending' ||
        'platform_organization_archive_history' => <Object?>[],
        'platform_review_subscription_payment' => <String, Object?>{},
        'platform_subscription_checkout_queue' => [
          {
            'id': 'test-order',
            'organization_name': 'Company ${onQueue()}',
            'status': 'under_review',
            'transfer_reference': 'expected-reference',
            'price_minor': 250000,
            'currency_code': 'LKR',
            'created_at': '2026-10-01T00:00:00Z',
            'expires_at': '2026-10-08T00:00:00Z',
          },
        ],
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
}

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
