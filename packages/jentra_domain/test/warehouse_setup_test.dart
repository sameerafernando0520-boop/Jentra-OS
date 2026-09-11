import 'package:jentra_domain/jentra_domain.dart';
import 'package:test/test.dart';

void main() {
  test('warehouse setup is scoped and uses its governed command', () {
    final warehouse = BusinessSetupResource.values
        .where((r) => r.name == 'warehouses')
        .firstOrNull;
    expect(warehouse, isNotNull);
    expect(warehouse!.apiView, 'warehouses');
    expect(warehouse.rpcName, 'upsert_warehouse');
    expect(warehouse.requiresLegalEntity, isTrue);
    expect(warehouse.managePermission, 'core.setup.manage');
  });
  test('warehouse validation requires branch and valid code and name', () {
    final warehouse = BusinessSetupResource.values.firstWhere(
      (r) => r.name == 'warehouses',
    );
    final invalid = BusinessSetupValidator.validate(warehouse, {
      'code': '!',
      'name': 'A',
    });
    expect(
      invalid.issues.map((i) => i.field),
      containsAll(['branch_id', 'code', 'name']),
    );
    expect(
      BusinessSetupValidator.validate(warehouse, {
        'code': 'ACPT-WH',
        'name': 'Acceptance warehouse',
        'branch_id': '579aab50-3856-4ace-a214-0d73a224a6ba',
        'status': 'active',
      }).isValid,
      isTrue,
    );
  });
}
