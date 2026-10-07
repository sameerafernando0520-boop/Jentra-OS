import 'package:test/test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_asset_equipment.dart';

const scope = TenantContext(
  tenantId: '11111111-1111-4111-a111-111111111111',
  actorId: '22222222-2222-4222-a222-222222222222',
  legalEntityId: '33333333-3333-4333-a333-333333333333',
  branchId: '44444444-4444-4444-a444-444444444444',
);
Map<String, Object?> source() => {
  'id': '55555555-5555-4555-a555-555555555555',
  'tenant_id': scope.tenantId,
  'legal_entity_id': scope.legalEntityId,
  'branch_id': scope.branchId,
  'code': 'PUMP',
  'name': 'Internal pump',
  'ownership': 'Company owned',
  'in_service': '2026-01-01',
  'location_id': '66666666-6666-4666-a666-666666666666',
  'location_name': 'Workshop',
  'custodian_id': null,
  'custodian_name': null,
  'status': 'active',
  'version': 3,
  'digest': 'a' * 64,
};
void main() {
  test(
    'AC-401 operational source rejects another scope or private book facts',
    () {
      expect(
        () =>
            AssetEquipmentSource.fromJson({...source(), 'cost': '1000'}, scope),
        throwsFormatException,
      );
      expect(
        () => AssetEquipmentSource.fromJson({
          ...source(),
          'branch_id': '77777777-7777-4777-a777-777777777777',
        }, scope),
        throwsFormatException,
      );
    },
  );
  test(
    'AC-414 source must be active with exact integer version and digest',
    () {
      for (final fields in <Map<String, Object?>>[
        {'status': 'disposed'},
        {'version': 3.0},
        {'digest': 'x'},
      ]) {
        expect(
          () => AssetEquipmentSource.fromJson({...source(), ...fields}, scope),
          throwsFormatException,
        );
      }
    },
  );
  test('AC-415 immutable source copies cannot change linked basis', () {
    final item = AssetEquipmentSource.fromJson(source(), scope),
        copy = AssetEquipmentSource.fromJson(source(), scope).toJson();
    copy['name'] = 'Changed';
    expect(item.toJson()['name'], 'Internal pump');
    final link = {
      'equipment_id': '77777777-7777-4777-a777-777777777777',
      'tenant_id': scope.tenantId,
      'legal_entity_id': scope.legalEntityId,
      'branch_id': scope.branchId,
      'asset_id': item.id,
      'asset_version': 3,
      'source_digest': item.digest,
      'source_basis': source(),
      'reason': 'Governed maintenance',
      'created_by': scope.actorId,
      'created_at': '2026-10-05T00:00:00Z',
    };
    expect(
      AssetEquipmentLink.fromJson(link, scope).source.name,
      'Internal pump',
    );
    expect(
      () => AssetEquipmentLink.fromJson({...link, 'asset_version': 4}, scope),
      throwsFormatException,
    );
  });
  test(
    'AC-414 link commands retain selected source and reject invented customer',
    () {
      final body = {
        'action': 'equipment',
        'id': '77777777-7777-4777-a777-777777777777',
        'kind': 'asset',
        'code': 'INTERNAL',
        'name': 'Internal equipment',
        'identity': 'PUMP',
        'customer_id': null,
        'provider_id': source()['id'],
        'provider_version': 3,
        'provider_digest': 'a' * 64,
        'reason': 'Internal maintenance',
      };
      AssetEquipmentCommands.validate('equipment', body);
      expect(
        () => AssetEquipmentCommands.validate('equipment', {
          ...body,
          'customer_id': source()['id'],
        }),
        throwsFormatException,
      );
      expect(
        () => AssetEquipmentCommands.validate('equipment', {
          ...body,
          'provider_version': null,
        }),
        throwsFormatException,
      );
    },
  );
}
