import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient client;
  late SupabaseFoundationGateway gateway;
  late ProviderContainer container;
  var permissions = <String>{};
  var actor = 'owner';
  var capabilityReads = 0;

  Map<String, Object?> session(String assurance) {
    final claims = base64Url
        .encode(
          utf8.encode(
            jsonEncode({
              'sub': actor,
              'aal': assurance,
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
      'access_token': 'eyJhbGciOiJIUzI1NiJ9.$claims.synthetic-test-signature',
      'refresh_token': 'synthetic-test-refresh',
      'expires_in': 3600,
      'token_type': 'bearer',
      'user': {
        'id': actor,
        'aud': 'authenticated',
        'app_metadata': <String, Object?>{},
        'user_metadata': <String, Object?>{},
        'created_at': '2026-09-11T00:00:00Z',
      },
    };
  }

  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await container.pump();
  }

  setUp(() async {
    permissions = {};
    actor = 'owner';
    capabilityReads = 0;
    client = SupabaseClient(
      'https://example.test',
      'synthetic-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final path = request.url.path;
        Object body;
        if (path.endsWith('/token')) {
          body = session('aal1');
        } else if (path.endsWith('/verify')) {
          body = session('aal2');
        } else if (path.endsWith('/get_my_capabilities')) {
          capabilityReads++;
          body = permissions.map((p) => {'permission_code': p}).toList();
        } else if (path.endsWith('/list_my_tenants')) {
          body = [
            {
              'tenant_id': 'tenant-$actor',
              'tenant_name': 'Test tenant',
              'tenant_slug': 'test-$actor',
              'tenant_status': 'active',
              'membership_status': 'active',
            },
          ];
        } else {
          throw StateError('Unexpected mock request: $path');
        }
        return http.Response(
          jsonEncode(body),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'owner@example.test',
      password: 'synthetic-only',
    );
    gateway = SupabaseFoundationGateway(client);
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        foundationGatewayProvider.overrideWithValue(gateway),
        activeTenantContextProvider.overrideWithValue(
          const TenantContext(
            tenantId: 'tenant-owner',
            actorId: 'owner',
            legalEntityId: 'entity',
            branchId: 'branch',
          ),
        ),
      ],
    );
    container.listen(authenticatedActorProvider, (_, _) {});
    await container.read(authenticatedActorProvider.future);
  });
  tearDown(() async {
    container.dispose();
    await client.dispose();
  });

  test(
    'MFA completion reloads capabilities without changing actor or scope',
    () async {
      container.listen(businessCapabilitiesProvider, (_, _) {});
      container.listen(sessionAssuranceProvider, (_, _) {});
      expect(
        await container.read(businessCapabilitiesProvider.future),
        isEmpty,
      );
      final readsBefore = capabilityReads;
      permissions = {
        'core.setup.manage',
        'inventory.cost.view',
        'inventory.adjustments.post',
      };
      await client.auth.mfa.verify(
        factorId: 'factor',
        challengeId: 'challenge',
        code: '123456',
      );
      container.invalidate(tenantListProvider); // Existing MFA screen behavior.
      await settle();
      expect(gateway.currentAssurance(), MfaAssurance.aal2);
      expect(container.read(sessionAssuranceProvider), MfaAssurance.aal2);
      expect(container.read(authenticatedActorProvider).value, 'owner');
      expect(
        await container.read(businessCapabilitiesProvider.future),
        permissions,
      );
      expect(capabilityReads, greaterThan(readsBefore));
    },
  );

  test(
    'same-actor token refresh removes permissions revoked on the server',
    () async {
      permissions = {'core.setup.manage'};
      container.listen(businessCapabilitiesProvider, (_, _) {});
      expect(
        await container.read(businessCapabilitiesProvider.future),
        permissions,
      );
      permissions = {};
      await client.auth.refreshSession();
      await settle();
      expect(
        await container.read(businessCapabilitiesProvider.future),
        isEmpty,
      );
    },
  );

  test(
    'switching accounts reloads tenant membership instead of reusing the first owner',
    () async {
      container.listen(tenantListProvider, (_, _) {});
      expect(
        (await container.read(tenantListProvider.future)).single.id,
        'tenant-owner',
      );
      actor = 'approver';
      await client.auth.signInWithPassword(
        email: 'approver@example.test',
        password: 'synthetic-only',
      );
      await settle();
      expect(
        (await container.read(tenantListProvider.future)).single.id,
        'tenant-approver',
      );
    },
  );
}
