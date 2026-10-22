import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _actorA = '10000000-0000-0000-0000-000000000001';
const _actorB = '10000000-0000-0000-0000-000000000002';

void main() {
  late String actor;
  late List<String> tenants;
  late Map<String, List<String>> entities;
  late Map<String, List<String>> branches;
  late SupabaseClient client;
  late ProviderContainer container;
  Future<http.Response?> Function(http.Request)? intercept;

  http.Response json(Object value) => http.Response(
    jsonEncode(value),
    200,
    headers: {'content-type': 'application/json'},
    request: http.Request(
      'GET',
      Uri.parse('https://scope.example.test/synthetic'),
    ),
  );

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

  List<Map<String, Object?>> entityRows(String tenant) => [
    for (final id in entities[tenant] ?? <String>[])
      {
        'id': id,
        'tenant_id': tenant,
        'name': id,
        'code': id,
        'currency_code': 'LKR',
        'timezone': 'Asia/Colombo',
        'status': 'active',
      },
  ];

  setUp(() async {
    actor = _actorA;
    tenants = ['tenant-a', 'tenant-b'];
    entities = {
      'tenant-a': ['entity-a1', 'entity-a2'],
      'tenant-b': ['entity-b1', 'entity-b2'],
      'tenant-c': ['entity-c1'],
    };
    branches = {
      for (final entity in entities.values.expand((value) => value))
        entity: ['$entity-west', '$entity-east'],
    };
    intercept = null;
    client = SupabaseClient(
      'https://scope.example.test',
      'synthetic-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final response = await intercept?.call(request);
        if (response != null) return response;
        if (request.url.path.endsWith('/token')) return json(session());
        if (request.url.path.endsWith('/list_my_tenants')) {
          return json([
            for (final id in actor == _actorA ? tenants : ['tenant-c'])
              {
                'tenant_id': id,
                'tenant_name': id,
                'tenant_slug': id,
                'tenant_status': 'active',
                'membership_status': 'active',
              },
          ]);
        }
        final query = request.url.queryParameters;
        if (request.url.path.endsWith('/legal_entities')) {
          return json(entityRows(query['tenant_id']!.substring(3)));
        }
        if (request.url.path.endsWith('/branches')) {
          final entity = query['legal_entity_id']!.substring(3);
          final tenant = query['tenant_id']!.substring(3);
          return json([
            for (final id in branches[entity] ?? <String>[])
              {
                'id': id,
                'tenant_id': tenant,
                'legal_entity_id': entity,
                'name': id,
                'code': id,
                'timezone': 'Asia/Colombo',
                'status': 'active',
              },
          ]);
        }
        throw StateError('Unexpected synthetic endpoint');
      }),
    );
    await client.auth.signInWithPassword(
      email: 'member@example.test',
      password: 'Synthetic-password-123',
    );
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        foundationGatewayProvider.overrideWithValue(
          SupabaseFoundationGateway(client),
        ),
      ],
    );
    container.listen(businessScopeProvider, (_, _) {});
    await container.read(businessScopeProvider.future);
  });

  tearDown(() async {
    container.dispose();
    await client.dispose();
  });

  Future<BusinessScopeState> refresh() async {
    container.invalidate(tenantListProvider);
    await container.pump();
    return container.read(businessScopeProvider.future);
  }

  Future<void> selectSecondScope() async {
    final controller = container.read(businessScopeProvider.notifier);
    await controller.selectTenant('tenant-b');
    await controller.selectLegalEntity('entity-b2');
    controller.selectBranch('entity-b2-east');
  }

  List<String?> selected(BusinessScopeState scope) => [
    scope.tenantId,
    scope.legalEntityId,
    scope.branchId,
  ];

  test(
    'membership refresh preserves the permitted tenant, entity and branch',
    () async {
      await selectSecondScope();
      expect(selected(await refresh()), [
        'tenant-b',
        'entity-b2',
        'entity-b2-east',
      ]);
    },
  );

  test(
    'refresh falls back when the selected tenant is no longer permitted',
    () async {
      await selectSecondScope();
      tenants = ['tenant-a'];
      expect(selected(await refresh()), [
        'tenant-a',
        'entity-a1',
        'entity-a1-west',
      ]);
    },
  );

  test('refresh replaces a removed entity and a removed branch', () async {
    await selectSecondScope();
    branches['entity-b2'] = ['entity-b2-west'];
    expect(selected(await refresh()), [
      'tenant-b',
      'entity-b2',
      'entity-b2-west',
    ]);
    entities['tenant-b'] = ['entity-b1'];
    expect(selected(await refresh()), [
      'tenant-b',
      'entity-b1',
      'entity-b1-west',
    ]);
  });

  for (final selection in ['tenant', 'entity']) {
    test(
      'late $selection selection cannot overwrite a new account scope',
      () async {
        final held = Completer<http.Response>();
        final started = Completer<void>();
        final oldRows = entityRows('tenant-b');
        intercept = (request) {
          final query = request.url.queryParameters;
          final matches = selection == 'tenant'
              ? request.url.path.endsWith('/legal_entities') &&
                    query['tenant_id'] == 'eq.tenant-b'
              : request.url.path.endsWith('/branches') &&
                    query['legal_entity_id'] == 'eq.entity-a2';
          if (!matches) return Future.value();
          started.complete();
          return held.future;
        };
        final controller = container.read(businessScopeProvider.notifier);
        final pending = selection == 'tenant'
            ? controller.selectTenant('tenant-b')
            : controller.selectLegalEntity('entity-a2');
        await started.future;
        expect(container.read(activeTenantContextProvider), isNull);
        actor = _actorB;
        await client.auth.signInWithPassword(
          email: 'another@example.test',
          password: 'Synthetic-password-123',
        );
        await container.pump();
        final current = await container.read(businessScopeProvider.future);
        expect(selected(current), ['tenant-c', 'entity-c1', 'entity-c1-west']);
        held.complete(json(selection == 'tenant' ? oldRows : []));
        await pending;
        expect(
          container.read(businessScopeProvider).requireValue,
          same(current),
        );
        expect(container.read(activeTenantContextProvider)?.actorId, _actorB);
      },
    );
  }

  test(
    'membership refresh supersedes a pending selection by the same actor',
    () async {
      final held = Completer<http.Response>();
      final started = Completer<void>();
      final rows = entityRows('tenant-b');
      intercept = (request) {
        if (!request.url.path.endsWith('/legal_entities') ||
            request.url.queryParameters['tenant_id'] != 'eq.tenant-b') {
          return Future.value();
        }
        started.complete();
        return held.future;
      };
      final pending = container
          .read(businessScopeProvider.notifier)
          .selectTenant('tenant-b');
      await started.future;
      final current = await refresh();
      expect(current.tenantId, 'tenant-a');
      held.complete(json(rows));
      await pending;
      expect(container.read(businessScopeProvider).requireValue, same(current));
    },
  );
}
