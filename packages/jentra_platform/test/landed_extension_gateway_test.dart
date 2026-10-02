import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/landed_extension.dart';
import 'package:jentra_platform/landed_extension_platform.dart';
import '../../jentra_domain/test/support/landed_extension_fixture.dart';
import 'support/wave4_gateway_harness.dart';

void main() {
  late Wave4GatewayHarness harness;
  late SupabaseLandedExtensionGateway gateway;
  setUp(() async {
    harness = Wave4GatewayHarness();
    await harness.initialize();
    gateway = SupabaseLandedExtensionGateway(harness.client);
  });
  tearDown(() => harness.dispose());
  test('preview binds authenticated scope and manual weights', () async {
    harness.response = landedEvidence();
    final evidence = await gateway.preview(w4Scope, landedInput());
    expect(evidence['amount'], '9007199254740.123456');
    final body = jsonDecode(harness.requests.single.body) as Map;
    expect(body['p_branch_id'], w4Scope.branchId);
    expect(body['p_payload'], landedInput());
    (harness.response as Map)['branch_id'] = w4Id;
    await expectLater(
      gateway.preview(w4Scope, landedInput()),
      throwsFormatException,
    );
  });
  test(
    'posting verifies receipt before confirming and rejects substituted scope',
    () async {
      final command = CommandEnvelope<Map<String, Object?>>(
        commandId: w4Command,
        idempotencyKey: w4Revision,
        context: w4Scope,
        clientTimestamp: DateTime.utc(2026, 9, 29),
        expectedEntityVersion: 0,
        payload: {...landedInput(), 'basis_hash': landedHash},
      );
      final entity = {
        ...landedEvidence(),
        'id': landedId,
        'status': 'posted',
        'version': 1,
        'reference': command.payload['reference'],
        'reason': command.payload['reason'],
        'journal_ids': [w4Revision],
      };
      harness.response = harness.confirmed(entity);
      expect((await gateway.post(command))['id'], landedId);
      entity['tenant_id'] = w4Id;
      await expectLater(
        gateway.post(command),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
        ),
      );
    },
  );
  test('foreign actor fails before transport', () async {
    const foreign = TenantContext(
      tenantId: 'tenant',
      actorId: 'foreign',
      legalEntityId: 'entity',
      branchId: 'branch',
    );
    await expectLater(
      gateway.preview(foreign, landedInput()),
      throwsA(isA<DomainError>()),
    );
    expect(harness.requests, isEmpty);
  });
  for (final code in [
    'PERMISSION_DENIED',
    'ACCESS_DENIED',
    'MFA_REQUIRED',
    'AUTHENTICATION_REQUIRED',
    'PGRST301',
    'PGRST302',
    'PGRST303',
    '42501',
  ]) {
    for (final kind in ['options', 'preview']) {
      test('multi-receipt $kind retains typed read denial $code', () async {
        harness.status = 403;
        harness.response = {
          'code': code.startsWith('PGRST') || code == '42501' ? code : 'P0001',
          'message': code,
        };
        final expected = code.startsWith('PGRST')
            ? 'AUTHENTICATION_REQUIRED'
            : code == '42501'
            ? 'PERMISSION_DENIED'
            : code;
        await expectLater(
          kind == 'options'
              ? gateway.options(w4Scope, 'posted')
              : gateway.preview(w4Scope, landedInput()),
          throwsA(isA<DomainError>().having((e) => e.code, 'code', expected)),
        );
      });
    }
  }
}
