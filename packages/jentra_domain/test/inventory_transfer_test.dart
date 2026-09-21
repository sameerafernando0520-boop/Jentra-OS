import 'package:jentra_domain/jentra_inventory.dart';
import 'package:test/test.dart';

void main() {
  test('transfer quantity remains exact above binary integer precision', () {
    final line = InventoryTransferQuantity('9007199254.740993', '3', '1');
    expect(line.baseQuantity, '27021597764.222979');
  });
  test('fractional base micro-units and numeric inputs are rejected', () {
    expect(
      () => InventoryTransferQuantity('1', '1', '3'),
      throwsFormatException,
    );
    expect(() => InventoryTransferQuantity(1, '1', '1'), throwsFormatException);
    expect(
      () => InventoryTransferQuantity('0', '1', '1'),
      throwsFormatException,
    );
    expect(
      () => InventoryTransferQuantity('-1', '1', '1'),
      throwsFormatException,
    );
  });
  test('serial count compares exact base quantity', () {
    final line = InventoryTransferQuantity('0.25', '12', '1');
    expect(line.baseQuantity, '3.000000');
    expect(() => line.validateSerialCount(2), throwsFormatException);
    line.validateSerialCount(3);
  });
}
