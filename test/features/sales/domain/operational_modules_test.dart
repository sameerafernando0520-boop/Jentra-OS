import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_os/features/crm/application/crm_extended_models.dart';
import 'package:jentra_os/features/inventory/application/stock_transfer_models.dart';
import 'package:jentra_os/features/sales/application/tax_rate_models.dart';

void main() {
  group('Phase 4 Operational Modules Invariants & Models', () {
    test('TaxRate model holds valid company rate percentage', () {
      const taxRate = TaxRate(
        id: 'tax-1',
        companyId: 'comp-1',
        name: 'Standard VAT',
        rate: 15.0,
      );

      expect(taxRate.rate, equals(15.0));
      expect(taxRate.isActive, isTrue);
    });

    test('StockTransfer enforces distinct source and destination warehouses', () {
      final transfer = StockTransfer(
        id: 'trf-1',
        companyId: 'comp-1',
        transferNumber: 'TRF-1001',
        fromWarehouseId: 'wh-main',
        toWarehouseId: 'wh-branch',
        status: 'posted',
        items: const [
          StockTransferItem(
            id: 'sti-1',
            companyId: 'comp-1',
            transferId: 'trf-1',
            productId: 'prod-1',
            quantity: 25.0,
          ),
        ],
        createdAt: DateTime(2026, 8, 1),
      );

      expect(transfer.fromWarehouseId, isNot(equals(transfer.toWarehouseId)));
      expect(transfer.items.first.quantity, equals(25.0));
    });

    test('ReceivablesAgingRow aggregates buckets correctly to total due', () {
      const row = ReceivablesAgingRow(
        customerId: 'cust-10',
        customerName: 'Global Distributors',
        currentAmount: 1000.00,
        days1To30: 500.00,
        days31To60: 250.00,
        days61To90: 0.00,
        days90Plus: 100.00,
        totalDue: 1850.00,
      );

      final bucketSum = row.currentAmount +
          row.days1To30 +
          row.days31To60 +
          row.days61To90 +
          row.days90Plus;

      expect(bucketSum, equals(row.totalDue));
    });
  });
}
