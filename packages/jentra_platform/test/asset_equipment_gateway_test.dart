import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_asset_equipment.dart';
import 'package:jentra_platform/jentra_asset_equipment_platform.dart';
import 'support/wave4_gateway_harness.dart';

void main() {
  late Wave4GatewayHarness h;
  late SupabaseAssetEquipmentGateway g;
  setUp(() async {
    h = Wave4GatewayHarness();
    await h.initialize();
    g = SupabaseAssetEquipmentGateway(h.client);
  });
  tearDown(() async => h.dispose());
  test('AC-401 missing named asset provider is explicit', () async {
    h.status = 404;
    h.response = {'code': 'PGRST202', 'message': 'Missing function'};
    await expectLater(
      g.sources(w4Scope),
      throwsA(
        isA<DomainError>().having(
          (e) => e.code,
          'code',
          'FEATURE_NOT_INSTALLED',
        ),
      ),
    );
  });
  test('AC-404 backend diagnostics never reach visible asset errors', () async {
    const marker = 'raw_private_constraint_detail';
    h.status = 400;
    for (final pair in {
      '42501': 'PERMISSION_DENIED',
      '40001': 'VERSION_CONFLICT',
      '23505': 'IDENTITY_EXISTS',
      'P0002': 'RESOURCE_NOT_FOUND',
      '22023': 'VALIDATION_ERROR',
      '55000': 'STATE_CONFLICT',
      'XX000': 'SERVICE_UNAVAILABLE',
    }.entries) {
      h.response = {'code': pair.key, 'message': marker};
      await expectLater(
        g.sources(w4Scope),
        throwsA(
          isA<DomainError>()
              .having((e) => e.code, 'code', pair.value)
              .having(
                (e) => e.message,
                'safe visible message',
                isNot(contains(marker)),
              ),
        ),
      );
    }
    final body = {
          'action': 'equipment',
          'id': w4Id,
          'kind': 'asset',
          'code': 'INTERNAL',
          'name': 'Internal equipment',
          'identity': 'PUMP',
          'customer_id': null,
          'provider_id': w4Revision,
          'provider_version': 1,
          'provider_digest': 'a' * 64,
          'reason': 'Governed link',
        },
        c = CommandEnvelope<Map<String, Object?>>(
          commandId: w4Command,
          idempotencyKey: w4Command,
          context: w4Scope,
          expectedEntityVersion: 0,
          clientTimestamp: DateTime.utc(2026, 10, 5),
          payload: body,
        );
    h.response = {'code': 'XX000', 'message': marker};
    await expectLater(
      g.execute('equipment', c),
      throwsA(
        isA<DomainError>()
            .having((e) => e.code, 'code', 'UNCERTAIN_RESULT')
            .having((e) => e.retryable, 'retryable', true)
            .having(
              (e) => e.message,
              'safe uncertainty',
              isNot(contains(marker)),
            ),
      ),
    );
  });
  test('AC-401 late source response cannot cross an account change', () async {
    h.gate = Completer<void>();
    final work = g.sources(w4Scope);
    while (h.requests.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    await h.client.auth.signOut();
    h.gate!.complete();
    await expectLater(
      work,
      throwsA(
        isA<DomainError>().having(
          (e) => e.code,
          'code',
          'AUTHENTICATION_REQUIRED',
        ),
      ),
    );
  });
  test(
    'AC-415 actual source and immutable link projections are strict and scoped',
    () async {
      final samples = serviceMap(
            jsonDecode(
              File(
                'test/fixtures/asset_equipment_rollback_projections.json',
              ).readAsStringSync(),
            ),
          ),
          page = serviceMap(samples['sources']),
          first = serviceMap((page['items'] as List).first),
          scope = TenantContext(
            tenantId: page['tenant_id'] as String,
            legalEntityId: page['legal_entity_id'] as String,
            branchId: page['branch_id'] as String,
            actorId: w4Scope.actorId,
          );
      h.response = page;
      final rows = await g.sources(scope);
      expect(rows.items, isNotEmpty);
      final link = serviceMap(samples['link']);
      h.response = link;
      expect(
        (await g.link(scope, link['equipment_id'] as String)).source.version,
        link['asset_version'],
      );
      h.response = {
        ...page,
        'items': [
          {...first, 'cost': '1000'},
        ],
      };
      await expectLater(g.sources(scope), throwsFormatException);
      h.response = {...page, 'next_cursor': first['id']};
      await expectLater(g.sources(scope), throwsFormatException);
    },
  );
  test(
    'AC-414 late known link result remains attributable to original scope',
    () async {
      final samples = serviceMap(
            jsonDecode(
              File(
                'test/fixtures/asset_equipment_rollback_projections.json',
              ).readAsStringSync(),
            ),
          ),
          r = serviceMap(samples['receipt']),
          e = serviceMap(r['entity']),
          l = serviceMap(samples['link']),
          source = serviceMap(l['source_basis']);
      final s = TenantContext(
            tenantId: e['tenant_id'] as String,
            legalEntityId: e['legal_entity_id'] as String,
            branchId: e['branch_id'] as String,
            actorId: w4Scope.actorId,
          ),
          c = CommandEnvelope<Map<String, Object?>>(
            commandId: r['command_id'] as String,
            idempotencyKey: w4Command,
            context: s,
            expectedEntityVersion: 0,
            clientTimestamp: DateTime.utc(2026, 10, 5),
            payload: {
              'action': 'equipment',
              'id': e['id'],
              'kind': 'asset',
              'code': 'INTERNAL',
              'name': 'Internal equipment',
              'identity': 'PUMP',
              'customer_id': null,
              'provider_id': source['id'],
              'provider_version': source['version'],
              'provider_digest': source['digest'],
              'reason': 'Governed link',
            },
          );
      h.response = r;
      h.gate = Completer<void>();
      final work = g.execute('equipment', c);
      while (h.requests.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      await h.client.auth.signOut();
      h.gate!.complete();
      expect((await work)['command_id'], c.commandId);
    },
  );
}
