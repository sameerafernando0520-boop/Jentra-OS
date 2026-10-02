import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:jentra_domain/jentra_assets.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_assets_platform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/wave4_gateway_harness.dart';

Map<String, Object?> basis() => {
  'residual': '100.000000',
  'remaining_months': 2,
  'method': 'straight_line',
  'convention': 'in_service_month',
  'rate_numerator': 1,
  'rate_denominator': 1,
  'precision': 2,
  'expense_account_id': w4Id,
  'cost': '1000.000000',
  'opening_accumulated': '200.000000',
  'opening_impairment': '300.000000',
  'start_date': '2026-02-01',
  'in_service': '2026-01-01',
  'currency_code': 'LKR',
};
Map<String, Object?> commandPayload() => {
  'action': 'location',
  'id': w4Id,
  'code': 'LAB',
  'name': 'Synthetic location',
  'reason': 'Synthetic configuration',
};
CommandEnvelope<Map<String, Object?>> command(Map<String, Object?> payload) =>
    CommandEnvelope(
      commandId: w4Command,
      idempotencyKey: w4Command,
      context: w4Scope,
      payload: payload,
      expectedEntityVersion: 0,
      clientTimestamp: DateTime.utc(2026, 9, 30),
    );
void main() {
  late Wave4GatewayHarness h;
  late SupabaseAssetGateway g;
  setUp(() async {
    h = Wave4GatewayHarness();
    await h.initialize();
    g = SupabaseAssetGateway(h.client);
  });
  tearDown(() async {
    await h.dispose();
  });
  for (final state in ['opening', 'active', 'impaired', 'disposed']) {
    for (final kind in AssetHistoryKind.values) {
      test(
        'actual rollback $state ${kind.name} projection crosses the typed gateway',
        () async {
          final samples =
              jsonDecode(
                    await File(
                      'test/fixtures/assets_rollback_projections.json',
                    ).readAsString(),
                  )
                  as Map;
          final row = assetMap(samples['$state.${kind.name}']);
          final scope = TenantContext(
            tenantId: row['tenant_id'] as String,
            legalEntityId: row['legal_entity_id'] as String,
            branchId: row['branch_id'] as String,
            actorId: w4Scope.actorId,
          );
          h.response = row;
          final assetId = assetMap(row['asset'])['id'] as String;
          final detail = await g.detail(scope, assetId, kind);
          expect(detail.asset.id, assetId);
          expect(detail.opening.cost.toDecimalString(), '1000.000000');
          expect(
            detail.asset.cost.minorUnits -
                detail.asset.accumulated.minorUnits -
                detail.asset.impairment.minorUnits,
            detail.asset.carrying.minorUnits,
          );
          if (state == 'opening') {
            expect(detail.proposal!.kind, 'capitalize');
          }
          if (state == 'disposed') {
            expect(detail.asset.status, 'disposed');
          }
          if (state != 'opening' && kind == AssetHistoryKind.books) {
            expect(detail.books, isNotEmpty);
          }
          if (state != 'opening' && kind == AssetHistoryKind.effects) {
            expect(detail.effects, isNotEmpty);
          }
        },
      );
    }
  }
  test(
    'a timed out issued write stays uncertain and retains its sealed identity',
    () async {
      h.response = h.confirmed({...h.scope(), 'id': w4Id, 'version': 1});
      h.gate = Completer<void>();
      g = SupabaseAssetGateway(
        h.client,
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        g.execute(command(commandPayload())),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
        ),
      );
      expect(jsonDecode(h.requests.last.body)['p_command_id'], w4Command);
      h.gate!.complete();
      await Future<void>.delayed(Duration.zero);
    },
  );
  test(
    'authorization verifies actor/scope/capability and explicit provider state',
    () async {
      h.response = {
        ...h.scope(),
        'actor_id': w4Scope.actorId,
        'authorized': true,
        'capability': 'assets.prepare',
        'procurement_provider': false,
        'stock_provider': false,
        'equipment_provider': false,
        'currency_code': 'LKR',
        'currency_precision': 2,
        'business_date': '2026-10-01',
      };
      expect(
        (await g.authorize(w4Scope, 'assets.prepare')).procurement,
        isFalse,
      );
      h.response = {...h.response as Map, 'actor_id': w4Id};
      await expectLater(
        g.authorize(w4Scope, 'assets.prepare'),
        throwsFormatException,
      );
    },
  );
  test('named scoped command freezes the body before any await', () async {
    h.response = h.confirmed({...h.scope(), 'id': w4Id, 'version': 1});
    h.gate = Completer<void>();
    final p = commandPayload(), future = g.execute(command(p));
    p['name'] = 'Changed later';
    await Future<void>.delayed(Duration.zero);
    h.gate!.complete();
    expect((await future)['entity'], containsPair('id', w4Id));
    final request = h.requests.single;
    expect(request.url.path.endsWith('/rpc/assets_command'), isTrue);
    final sent = jsonDecode(request.body) as Map;
    expect((sent['p_payload'] as Map)['name'], 'Synthetic location');
    expect(sent['p_branch_id'], w4Scope.branchId);
    expect(sent['p_expected_version'], 0);
  });
  test(
    'forged scope/version/command and unexpected financial receipt stay uncertain',
    () async {
      for (final entity in [
        {...h.scope(), 'id': w4Id, 'version': 2},
        {...h.scope(), 'id': w4Id, 'version': 1, 'branch_id': w4Id},
        {...h.scope(), 'id': w4Id, 'version': 1, 'cost': '1000'},
      ]) {
        h.response = h.confirmed(entity);
        await expectLater(
          g.execute(command(commandPayload())),
          throwsA(
            isA<DomainError>().having(
              (e) => e.code,
              'code',
              'UNCERTAIN_RESULT',
            ),
          ),
        );
      }
      h.response = {
        ...h.confirmed({...h.scope(), 'id': w4Id, 'version': 1}),
        'command_id': w4Revision,
      };
      await expectLater(
        g.execute(command(commandPayload())),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
        ),
      );
    },
  );
  test(
    'schedule page reproduces exact frozen basis and rejects altered amounts',
    () async {
      final definition = AssetBookDefinition.fromJson(basis());
      h.response = {
        ...h.scope(),
        'asset_id': w4Id,
        'book_id': w4Revision,
        'basis': basis(),
        'items': definition.schedule.periods.map((p) => p.toJson()).toList(),
        'next_cursor': null,
      };
      final page = await g.schedule(w4Scope, w4Id, w4Revision);
      expect(page.periods.last.closingCarrying.toDecimalString(), '100.000000');
      h.response = {
        ...h.response as Map,
        'items': [
          definition.schedule.periods.first.toJson()
            ..['depreciation'] = '201.000000',
        ],
      };
      await expectLater(
        g.schedule(w4Scope, w4Id, w4Revision),
        throwsFormatException,
      );
    },
  );
  test(
    'all read pages validate scope, bounds and continuation order',
    () async {
      h.response = {
        ...h.scope(),
        'kind': 'locations',
        'items': [
          {'id': w4Id, 'code': 'LAB', 'name': 'Synthetic lab'},
        ],
        'next_cursor': w4Id,
      };
      await expectLater(g.pickers(w4Scope, 'locations'), throwsFormatException);
      h.response = {
        ...h.scope(),
        'kind': 'locations',
        'items': [
          {'id': w4Id, 'code': 'LAB', 'name': 'Synthetic lab'},
        ],
        'next_cursor': null,
      };
      expect(
        (await g.pickers(w4Scope, 'locations')).items.single.name,
        'Synthetic lab',
      );
      h.response = {...h.response as Map, 'tenant_id': w4Id};
      await expectLater(g.pickers(w4Scope, 'locations'), throwsFormatException);
    },
  );
  test('late account loss keeps an issued write uncertain', () async {
    h.response = h.confirmed({...h.scope(), 'id': w4Id, 'version': 1});
    h.gate = Completer<void>();
    final future = g.execute(command(commandPayload()));
    await Future<void>.delayed(Duration.zero);
    await h.client.auth.signOut();
    h.gate!.complete();
    await expectLater(
      future,
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
      ),
    );
  });
  test(
    'server errors expose sanitized definite failures and no raw evidence',
    () async {
      h.status = 400;
      h.response = {
        'code': '55000',
        'message': 'ASSET_SOURCE_ALREADY_OWNED',
        'details': 'private source evidence',
        'hint': 'secret',
      };
      await expectLater(
        g.execute(command(commandPayload())),
        throwsA(
          isA<DomainError>()
              .having((e) => e.code, 'code', 'ASSET_SOURCE_ALREADY_OWNED')
              .having(
                (e) => e.message.contains('private source'),
                'private raw evidence',
                isFalse,
              ),
        ),
      );
    },
  );
}
