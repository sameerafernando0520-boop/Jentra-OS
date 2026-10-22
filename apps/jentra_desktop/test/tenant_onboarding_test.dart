import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/features/dashboard/dashboard_screen.dart';
import 'package:jentra_desktop/src/features/tenant/tenant_onboarding_screen.dart';
import 'package:jentra_desktop/src/features/tenant/workspace_creation.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _actor = '10000000-0000-0000-0000-000000000001';
const _otherActor = '10000000-0000-0000-0000-000000000002';
const _tenant = '20000000-0000-0000-0000-000000000001';
const _entity = '30000000-0000-0000-0000-000000000001';
const _branch = '40000000-0000-0000-0000-000000000001';
const _request = WorkspaceCreationRequest(
  actorId: _actor,
  idempotencyKey: '50000000-0000-0000-0000-000000000001',
  name: 'Example Holdings',
  slug: 'example-holdings',
  legalEntityName: 'Example Trading',
  legalEntityCode: 'ET',
  branchName: 'Head Office',
  branchCode: 'HQ',
);

http.Response _json(Object value, {int status = 200}) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
  request: http.Request(
    'POST',
    Uri.parse('https://example.test/rest/v1/rpc/synthetic'),
  ),
);

Matcher _failure(WorkspaceCreationFailure failure) =>
    isA<WorkspaceCreationException>().having(
      (e) => e.failure,
      'failure',
      failure,
    );

void main() {
  late SupabaseClient client;
  late SupabaseFoundationGateway gateway;
  late ProviderContainer container;
  late String actor;
  var created = false;
  final requests = <http.Request>[];
  Future<http.Response?> Function(http.Request)? respond;

  Map<String, Object?> session() {
    String part(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    return {
      'access_token':
          '${part({'alg': 'HS256'})}.${part({'sub': actor, 'aal': 'aal1', 'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000})}.synthetic-signature',
      'refresh_token': 'synthetic-refresh-only',
      'expires_in': 3600,
      'token_type': 'bearer',
      'user': {
        'id': actor,
        'aud': 'authenticated',
        'email': 'member@example.test',
        'created_at': '2026-10-22T00:00:00Z',
        'app_metadata': <String, Object?>{},
        'user_metadata': <String, Object?>{},
      },
    };
  }

  Map<String, Object?> tenant() => {
    'tenant_id': _tenant,
    'tenant_name': _request.name,
    'tenant_slug': _request.slug,
    'tenant_status': 'trial',
    'membership_status': 'active',
  };

  setUp(() async {
    actor = _actor;
    created = false;
    requests.clear();
    respond = null;
    client = SupabaseClient(
      'https://example.test',
      'synthetic-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        final result = await respond?.call(request);
        if (result != null) return result;
        final path = request.url.path;
        if (path.endsWith('/token')) return _json(session());
        if (path.endsWith('/list_my_tenants')) {
          return _json(created && actor == _actor ? [tenant()] : []);
        }
        if (path.endsWith('/bootstrap_tenant')) {
          created = true;
          return _json({'tenant_id': _tenant, 'mfa_required': true});
        }
        if (path.endsWith('/legal_entities')) {
          return _json([
            {
              'id': _entity,
              'tenant_id': _tenant,
              'name': _request.legalEntityName,
              'code': 'ET',
              'currency_code': 'LKR',
              'timezone': 'Asia/Colombo',
              'status': 'active',
            },
          ]);
        }
        if (path.endsWith('/branches')) {
          return _json([
            {
              'id': _branch,
              'tenant_id': _tenant,
              'legal_entity_id': _entity,
              'name': 'Head Office',
              'code': 'HQ',
              'timezone': 'Asia/Colombo',
              'status': 'active',
            },
          ]);
        }
        if (path.endsWith('/get_my_capabilities')) return _json([]);
        throw StateError('Unexpected synthetic endpoint');
      }),
    );
    await client.auth.signInWithPassword(
      email: 'member@example.test',
      password: 'Synthetic-password-123',
    );
    gateway = SupabaseFoundationGateway(client);
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [foundationGatewayProvider.overrideWithValue(gateway)],
    );
    container.listen(tenantListProvider, (_, _) {});
    await container.read(tenantListProvider.future);
    container.listen(authSessionRevisionProvider, (_, _) {});
    await container.read(authSessionRevisionProvider.future);
  });
  tearDown(() async {
    container.dispose();
    await client.dispose();
  });

  Future<void> mount(WidgetTester tester, {double scale = 1}) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: JentraTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const Scaffold(body: DashboardScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);
  Future<void> fill(WidgetTester tester) async {
    await tester.enterText(field('Business group name'), _request.name);
    await tester.enterText(
      field('Registered entity name'),
      _request.legalEntityName,
    );
    await tester.enterText(field('Entity code'), _request.legalEntityCode);
  }

  Future<void> click(
    WidgetTester tester,
    String label, {
    bool settle = true,
  }) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  test('confirmed creation publishes membership and resets business scope without MFA bypass', () async {
    container.listen(businessScopeProvider, (_, _) {});
    await expectLater(
      container.read(businessScopeProvider.future),
      throwsStateError,
    );
    await container.read(tenantListProvider.notifier).createTenant(_request);
    expect(container.read(tenantListProvider).requireValue.single.id, _tenant);
    final scope = await container.read(businessScopeProvider.future);
    expect(
      [scope.tenantId, scope.legalEntityId, scope.branchId],
      [_tenant, _entity, _branch],
    );
    expect(gateway.currentAssurance(), MfaAssurance.aal1);
    expect(await container.read(businessCapabilitiesProvider.future), isEmpty);
    final body = jsonDecode(
      requests
          .singleWhere((r) => r.url.path.endsWith('/bootstrap_tenant'))
          .body,
    ) as Map;
    expect(body['p_idempotency_key'], _request.idempotencyKey);
  });

  testWidgets(
    'uncertain creation keeps mounted input and exact request for retry',
    (tester) async {
      respond = (request) async =>
          request.url.path.endsWith('/bootstrap_tenant')
          ? _json({
              'code': 'XX000',
              'message': 'private-server-detail',
            }, status: 500)
          : null;
      await mount(tester);
      await fill(tester);
      final state = tester.state(find.byType(TenantOnboardingScreen));
      await click(tester, 'Create workspace');
      expect(tester.state(find.byType(TenantOnboardingScreen)), same(state));
      expect(
        tester
            .widget<TextFormField>(field('Business group name'))
            .controller!
            .text,
        _request.name,
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: field('Business group name'),
                matching: find.byType(TextField),
              ),
            )
            .readOnly,
        isTrue,
      );
      expect(container.read(tenantListProvider).hasError, isFalse);
      expect(
        find.textContaining('Workspace creation has not been confirmed'),
        findsOneWidget,
      );
      expect(find.textContaining('private-server-detail'), findsNothing);
      await click(tester, 'Retry workspace creation');
      final bodies = requests
          .where((r) => r.url.path.endsWith('/bootstrap_tenant'))
          .map((r) => jsonDecode(r.body))
          .toList();
      expect(bodies.length, 2);
      expect(bodies[1], bodies[0]);
      expect(tester.takeException(), isNull);
    },
  );

  test('membership read failure preserves pending intent for a later confirmed retry', () async {
    var failedRead = false;
    respond = (request) async {
      if (created &&
          !failedRead &&
          request.url.path.endsWith('/list_my_tenants')) {
        failedRead = true;
        return _json({
          'code': 'XX000',
          'message': 'private-read-detail',
        }, status: 500);
      }
      return null;
    };
    await expectLater(
      container.read(tenantListProvider.notifier).createTenant(_request),
      throwsA(_failure(WorkspaceCreationFailure.unconfirmed)),
    );
    expect(container.read(tenantListProvider).requireValue, isEmpty);
    await container.read(tenantListProvider.notifier).createTenant(_request);
    final bodies = requests
        .where((r) => r.url.path.endsWith('/bootstrap_tenant'))
        .map((r) => jsonDecode(r.body))
        .toList();
    expect(bodies.length, 2);
    expect(bodies[0], bodies[1]);
    expect(container.read(tenantListProvider).requireValue.single.id, _tenant);
  });

  test(
    'duplicate response recovers a prior committed owner membership',
    () async {
      respond = (request) async {
        if (!request.url.path.endsWith('/bootstrap_tenant')) return null;
        created = true;
        return _json({
          'code': '23505',
          'message': 'private-duplicate-detail',
        }, status: 409);
      };
      await container.read(tenantListProvider.notifier).createTenant(_request);
      expect(
        container.read(tenantListProvider).requireValue.single.id,
        _tenant,
      );
    },
  );

  testWidgets(
    'definite duplicate allows correction while preserving entered values',
    (tester) async {
      respond = (request) async =>
          request.url.path.endsWith('/bootstrap_tenant')
          ? _json({
              'code': '23505',
              'message': 'private-duplicate-detail',
            }, status: 409)
          : null;
      await mount(tester);
      await fill(tester);
      await click(tester, 'Create workspace');
      expect(
        tester
            .widget<TextFormField>(field('Business group name'))
            .controller!
            .text,
        _request.name,
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: field('Workspace slug'),
                matching: find.byType(TextField),
              ),
            )
            .readOnly,
        isFalse,
      );
      expect(find.textContaining('already in use'), findsOneWidget);
      await tester.enterText(field('Workspace slug'), 'another-workspace');
      await click(tester, 'Create workspace');
      final bodies = requests
          .where((r) => r.url.path.endsWith('/bootstrap_tenant'))
          .map((r) => jsonDecode(r.body) as Map)
          .toList();
      expect(
        bodies[0]['p_idempotency_key'],
        isNot(bodies[1]['p_idempotency_key']),
      );
      expect(bodies[1]['p_slug'], 'another-workspace');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'account switch clears form and rejects late previous-actor result',
    (tester) async {
      final submitted = Completer<void>();
      final release = Completer<http.Response>();
      respond = (request) {
        if (!request.url.path.endsWith('/bootstrap_tenant')) {
          return Future.value(null);
        }
        submitted.complete();
        return release.future;
      };
      await mount(tester);
      await fill(tester);
      await click(tester, 'Create workspace', settle: false);
      await submitted.future;
      actor = _otherActor;
      await client.auth.signInWithPassword(
        email: 'other@example.test',
        password: 'Synthetic-password-123',
      );
      await tester.pump();
      // The old request is deliberately held. Do not wait for an animated
      // loading state to settle until that transport is released.
      expect(gateway.currentUser?.id, _otherActor);
      expect(find.text(_request.name), findsNothing);
      release.complete(_json({'tenant_id': _tenant, 'mfa_required': true}));
      await tester.pumpAndSettle();
      expect(container.read(tenantListProvider).requireValue, isEmpty);
      expect(
        tester
            .widget<TextFormField>(field('Business group name'))
            .controller!
            .text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('foreign receipt is not published as a confirmed workspace', () async {
    respond = (request) async {
      if (!request.url.path.endsWith('/bootstrap_tenant')) return null;
      created = true;
      return _json({'tenant_id': 'foreign-tenant', 'mfa_required': true});
    };
    await expectLater(
      container.read(tenantListProvider.notifier).createTenant(_request),
      throwsA(_failure(WorkspaceCreationFailure.unconfirmed)),
    );
    expect(container.read(tenantListProvider).requireValue, isEmpty);
  });

  testWidgets('onboarding form remains usable at 200 percent text', (
    tester,
  ) async {
    await mount(tester, scale: 2);
    await tester.ensureVisible(find.text('Create workspace'));
    expect(find.byType(TenantOnboardingScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
