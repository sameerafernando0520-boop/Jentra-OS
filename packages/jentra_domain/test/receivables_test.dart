import 'package:jentra_domain/jentra_receivables.dart';
import 'package:test/test.dart';

void main() {
  test(
    'financial wire values never accept JSON numbers or excess precision',
    () {
      expect(() => receivableDecimal(1.1), throwsFormatException);
      expect(() => receivableDecimal('1.0000001'), throwsFormatException);
      expect(
        receivableDecimal('90071992547409.123456').toString(),
        '90071992547409.123456',
      );
    },
  );
  test('receipt input requires bank and exact positive amount', () {
    final form = <String, Object?>{
      'id': 'receipt',
      'customer_id': 'customer',
      'document_date': '2026-09-07',
      'currency_code': 'LKR',
      'amount': '180.00',
      'cash_bank_account_id': 'bank',
    };
    expect(ReceivableDraft(ReceivableKind.receipt, form).validate(), isEmpty);
    expect(
      ReceivableDraft(ReceivableKind.receipt, {
        ...form,
        'amount': '0',
      }).validate(),
      isNotEmpty,
    );
    expect(
      ReceivableDraft(ReceivableKind.receipt, {
        ...form,
        'document_date': '2026-02-30',
      }).validate(),
      isNotEmpty,
    );
  });
  test('return requires source, quantity, reason and disposition', () {
    final form = <String, Object?>{
      'id': 'return',
      'customer_id': 'customer',
      'document_date': '2026-09-07',
      'currency_code': 'LKR',
      'reason': 'Damaged packaging',
      'lines': [
        <String, Object?>{
          'line_id': 'line',
          'sales_invoice_line_id': 'original',
          'base_quantity': '1',
          'disposition': 'saleable',
        },
      ],
    };
    expect(ReceivableDraft(ReceivableKind.credit, form).validate(), isEmpty);
    expect(
      ReceivableDraft(ReceivableKind.credit, {
        ...form,
        'reason': '',
      }).validate(),
      isNotEmpty,
    );
  });
  test('permissions separate editing, posting and allocation', () {
    expect(ReceivableKind.invoice.managePermission, 'sales.invoices.manage');
    expect(ReceivableKind.invoice.postPermission, 'sales.invoices.post');
    expect(ReceivableKind.receipt.postPermission, 'finance.receipts.post');
    expect(ReceivableKind.delivery.canRead({'sales.deliveries.manage'}), true);
    expect(ReceivableKind.credit.canRead({}), false);
  });
  test('draft retains immutable exact payload', () {
    final raw = <String, Object?>{
      'lines': [
        <String, Object?>{'base_quantity': '1'},
      ],
    };
    final draft = ReceivableDraft(ReceivableKind.delivery, raw);
    (raw['lines'] as List).clear();
    expect(draft.toJson()['lines'], hasLength(1));
    (draft.toJson()['lines'] as List).clear();
    expect(draft.toJson()['lines'], hasLength(1));
  });
}
