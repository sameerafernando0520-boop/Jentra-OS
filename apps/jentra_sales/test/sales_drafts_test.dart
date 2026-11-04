import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_sales/src/data/sales_store.dart';
import 'package:jentra_sales/src/data/sales_gateway.dart';
import 'package:jentra_sales/src/models.dart';
import 'package:jentra_sales/src/sales_controller.dart';

SalesOrder draft(
  SalesController c,
  String id, {
  String quantity = '1.125',
  String discount = '0',
  String reason = '',
}) => SalesOrder(
  id: id,
  commandId: 'command-$id',
  customerId: c.customers.first.id,
  date: c.now(),
  lines: [SalesLine(c.products.first, quantity)],
  local: true,
  discount: discount,
  discountReason: reason,
  customerState: 'Not requested',
  companyState: 'Not submitted',
  deliveryState: 'Not scheduled',
);

void main() {
  test('fractional quantities keep exact half-away-from-zero money', () {
    final p = const SalesProduct(
      id: 'p',
      name: 'Product',
      code: 'P',
      category: '',
      unit: 'piece',
      price: '1.25',
      availability: '',
      symbol: 'mug',
    );
    expect(SalesLine(p, '0.1').total.toDecimalString(), '0.13');
    expect(SalesLine(p, '1.125').total.toDecimalString(), '1.41');
    for (final value in ['0', '-1', '1e3', '1,5', '.5', '1.0001', '10000000']) {
      expect(() => parseQuantity(value), throwsFormatException, reason: value);
    }
    expect(() => parseDiscount('100.01'), throwsFormatException);
    expect(money('1234567.8'), 'LKR 1,234,567.80');
  });
  test(
    'saving never implies company approval or customer acceptance',
    () async {
      final store = MemorySalesStore();
      final c = SalesController(store: store);
      await c.enterPreview();
      await c.saveDraft(draft(c, 'draft-1'));
      final again = SalesController(store: store);
      await again.enterPreview();
      final restored = again.orders.firstWhere((o) => o.id == 'draft-1');
      expect(restored.local, isTrue);
      expect(restored.commandId, 'command-draft-1');
      expect(restored.customerState, 'Not requested');
      expect(restored.companyState, 'Not submitted');
      expect(restored.deliveryState, 'Not scheduled');
      expect(restored.subtotal.toDecimalString(), '1406.25');
      c.dispose();
      again.dispose();
    },
  );
  test('storage failure does not acknowledge a saved draft', () async {
    final c = SalesController(store: _FailingStore());
    await c.enterPreview();
    expect(c.notice, isNotNull);
    await expectLater(
      c.saveDraft(draft(c, 'draft-1')),
      throwsA(isA<SalesFailure>()),
    );
    expect(c.orders.where((o) => o.local), isEmpty);
    c.dispose();
  });
  test('parallel saves retain both immutable command identities', () async {
    final store = MemorySalesStore();
    final c = SalesController(store: store);
    await c.enterPreview();
    await Future.wait([
      c.saveDraft(draft(c, 'draft-1')),
      c.saveDraft(draft(c, 'draft-2')),
    ]);
    await c.enterPreview();
    expect(c.orders.where((o) => o.local).map((o) => o.commandId).toSet(), {
      'command-draft-1',
      'command-draft-2',
    });
    c.dispose();
  });
  test(
    'expired drafts cannot be reopened and missing prices never become zero',
    () async {
      final store = MemorySalesStore();
      var time = DateTime.utc(2026, 10, 30, 8);
      final c = SalesController(store: store, now: () => time);
      await c.enterPreview();
      await c.saveDraft(draft(c, 'draft-1'));
      time = time.add(const Duration(hours: 24));
      await c.enterPreview();
      expect(c.orders.where((o) => o.local), isEmpty);
      expect(store.values.values.single, '[]');
      expect(
        () => SalesOrder.fromDraft({
          'schema': 1,
          'lines': [
            {'product_id': 'unknown', 'quantity': '1'},
          ],
        }, c.products),
        throwsFormatException,
      );
      c.dispose();
    },
  );
  test(
    'discount requests require a reason and preserve original selling price',
    () async {
      final c = SalesController(store: MemorySalesStore());
      await c.enterPreview();
      await expectLater(
        c.saveDraft(draft(c, 'draft-1', discount: '5')),
        throwsA(isA<SalesFailure>()),
      );
      await c.saveDraft(
        draft(c, 'draft-1', discount: '5', reason: 'Volume request'),
      );
      expect(c.orders.first.subtotal.toDecimalString(), '1406.25');
      c.dispose();
    },
  );
  test('missing company access never substitutes demo customers', () async {
    final c = SalesController(
      store: MemorySalesStore(),
      account: _PendingAccount(),
    );
    await c.signIn('rep@example.invalid', 'private');
    expect(c.preview, isFalse);
    expect(c.customers, isEmpty);
    expect(c.products, isEmpty);
    expect(c.notice, contains('prepared'));
    c.dispose();
  });
}

final class _FailingStore implements SalesKeyValueStore {
  @override
  Future<String?> read(String key) async =>
      throw const SalesFailure('STORAGE_UNAVAILABLE', 'Unavailable');
  @override
  Future<void> write(String key, String value) async =>
      throw const SalesFailure('STORAGE_UNAVAILABLE', 'Unavailable');
  @override
  Future<void> delete(String key) async =>
      throw const SalesFailure('STORAGE_UNAVAILABLE', 'Unavailable');
}

final class _PendingAccount implements SalesAccountGateway {
  @override
  Future<void> signIn(String email, String password) async =>
      throw const SalesFailure('PENDING', 'Workspace is being prepared.');
  @override
  Future<void> signOut() async {}
}
