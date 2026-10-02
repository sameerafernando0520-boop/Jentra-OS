import 'package:jentra_domain/jentra_receivables.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:test/test.dart';
import 'wave3_quotation_workspace_test.dart' show input;

QuotationDraft discounted({Money? amount, ExactDecimal? percent}) {
  final d = QuotationDraftCodec.fromJson(input());
  return QuotationDraft(
    customerId: d.customerId,
    quotationDate: d.quotationDate,
    validUntil: d.validUntil,
    currencyCode: d.currencyCode,
    exchangeRate: d.exchangeRate,
    rateDate: d.rateDate,
    salespersonId: d.salespersonId,
    lines: d.lines,
    headerDiscountAmount: amount,
    headerDiscountPercent: percent,
  );
}

void main() {
  test(
    'quotation pricing rejects conflicting, excessive and malformed discounts before calculation',
    () {
      final source = QuotationDraftCodec.fromJson(input()).lines.single;
      QuotationPricing price({
        List<QuotationLineDraft>? lines,
        int scale = 6,
        ExactDecimal? rate,
        Money? amount,
        ExactDecimal? percent,
      }) => QuotationPricingCalculator.calculate(
        currencyCode: 'LKR',
        baseCurrencyCode: 'LKR',
        exchangeRate: rate ?? ExactDecimal.parse('1', scale: 10),
        roundingScale: scale,
        lines: lines ?? [source],
        headerDiscountAmount: amount,
        headerDiscountPercent: percent,
      );
      expect(() => price(lines: []), throwsArgumentError);
      for (final scale in [-1, 7]) {
        expect(() => price(scale: scale), throwsRangeError);
      }
      expect(
        () => price(rate: ExactDecimal.parse('1', scale: 6)),
        throwsArgumentError,
      );
      expect(
        () => price(
          amount: Money.zero('LKR'),
          percent: ExactDecimal.zero(scale: 6),
        ),
        throwsArgumentError,
      );
      for (final amount in [Money.zero('USD'), Money.parse('-1', 'LKR')]) {
        expect(() => price(amount: amount), throwsArgumentError);
      }
      for (final percent in [
        ExactDecimal.parse('1', scale: 2),
        ExactDecimal.parse('-1', scale: 6),
        ExactDecimal.parse('101', scale: 6),
      ]) {
        expect(() => price(percent: percent), throwsArgumentError);
      }
      for (final line in [
        source.copyWith(lineId: ''),
        source.copyWith(description: ''),
        source.copyWith(unitPrice: Money.parse('-1', 'LKR')),
        source.copyWith(discountAmount: Money.zero('USD')),
        source.copyWith(discountAmount: Money.parse('-1', 'LKR')),
        source.copyWith(discountPercent: ExactDecimal.parse('-1', scale: 6)),
        source.copyWith(discountPercent: ExactDecimal.parse('101', scale: 6)),
        source.copyWith(discountPercent: ExactDecimal.parse('10', scale: 2)),
      ]) {
        expect(() => price(lines: [line]), throwsArgumentError);
      }
      expect(
        () => price(
          lines: [
            source.copyWith(
              discountAmount: source.unitPrice + Money.parse('1', 'LKR'),
            ),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => price(amount: source.unitPrice + Money.parse('1', 'LKR')),
        throwsArgumentError,
      );
      final free = source.copyWith(unitPrice: Money.zero('LKR'));
      final result = price(
        lines: [free],
        percent: ExactDecimal.parse('100', scale: 6),
      );
      expect(result.grandTotal, Money.zero('LKR'));
      expect(result.headerDiscountTotal, Money.zero('LKR'));
      expect(
        price(
          lines: [source.copyWith(discountAmount: Money.parse('1', 'LKR'))],
        ).lineDiscountTotal,
        Money.parse('1', 'LKR'),
      );
      final copied = source.copyWith(
        lineId: 'new',
        productId: 'product',
        description: ' Edited ',
        quantity: source.quantity,
        unitPrice: Money.parse('1', 'LKR'),
        taxDefinitionId: 'tax',
        previewTax: QuotationTaxSnapshot(
          definitionId: 'tax',
          code: 'ZERO',
          name: 'Zero rate',
          kind: 'output',
          rate: ExactDecimal.zero(scale: 6),
          inclusive: false,
          definitionVersion: 1,
        ),
      );
      expect(copied.toJson()['description'], 'Edited');
      expect(price(lines: [copied]).taxTotal, Money.zero('LKR'));
    },
  );

  test(
    'commercial source selection, reservations and credit previews reject incomplete context',
    () {
      for (final conversion in [
        QuotationConversionDraft(
          quotationId: '',
          quotationRevision: 1,
          promisedDate: DateTime.utc(2026, 10),
          warehouseId: 'warehouse',
        ),
        QuotationConversionDraft(
          quotationId: 'quote',
          quotationRevision: 0,
          promisedDate: DateTime.utc(2026, 10),
          warehouseId: '',
        ),
      ]) {
        expect(conversion.validate().isValid, false);
      }
      expect(
        QuotationConversionDraft(
          quotationId: 'quote',
          quotationRevision: 1,
          promisedDate: DateTime.utc(2026, 10),
          warehouseId: 'warehouse',
        ).toJson()['ship_to'],
        isEmpty,
      );
      for (final draft in [
        StockReservationDraft(
          salesOrderId: '',
          expiresAt: DateTime.utc(2026, 10),
          lines: [],
        ),
        StockReservationDraft(
          salesOrderId: 'order',
          expiresAt: DateTime.utc(2026, 10),
          lines: [
            StockReservationLineDraft(
              salesOrderLineId: '',
              requestedBaseQuantity: ExactDecimal.zero(scale: 6),
            ),
          ],
        ),
        StockReservationDraft(
          salesOrderId: 'order',
          expiresAt: DateTime.utc(2026, 10),
          lines: [
            StockReservationLineDraft(
              salesOrderLineId: 'line',
              requestedBaseQuantity: ExactDecimal.parse('1', scale: 2),
            ),
          ],
        ),
      ]) {
        expect(draft.validate().isValid, false);
      }
      expect(
        () => SalesOrderListQuery(sourceQuotationId: 'bad'),
        throwsFormatException,
      );
      expect(
        SalesOrderListQuery(
          sourceQuotationId: '11111111-1111-1111-1111-111111111111',
        ).limit,
        50,
      );
      final credit = <String, Object?>{
        'sales_order_id': 'order',
        'order_version': 1,
        'currency_code': 'LKR',
        'credit_currency_code': 'LKR',
        'credit_limit': '100',
        'due_exposure': '10',
        'overdue_exposure': '5',
        'existing_order_exposure': '20',
        'current_order_exposure': '30',
        'total_exposure': '60',
        'projection_available': true,
        'checked_at': '2026-09-30T00:00:00Z',
        'credit_as_of_at': '2026-09-30T00:00:00Z',
      };
      expect(
        SalesOrderCreditPreview.fromJson(credit).asOf,
        DateTime.utc(2026, 9, 30),
      );
      expect(
        () => SalesOrderCreditPreview.fromJson({
          ...credit,
          'total_exposure': '61',
        }),
        throwsFormatException,
      );
      expect(
        () => SalesOrderCreditPreview.fromJson({...credit, 'due_exposure': 10}),
        throwsFormatException,
      );
      final snapshot = CreditDecisionSnapshot(
        currencyCode: 'LKR',
        creditLimit: Money.parse('100', 'LKR'),
        dueExposure: Money.parse('10', 'LKR'),
        overdueExposure: Money.parse('5', 'LKR'),
        existingOrderExposure: Money.parse('20', 'LKR'),
        currentOrderExposure: Money.parse('30', 'LKR'),
        overrideApplied: false,
      );
      expect(snapshot.totalExposure.toDecimalString(), '60.000000');
      final rawLine = (input()['lines'] as List).single as Map<String, Object?>;
      for (final patch in <Map<String, Object?>>[
        {'lines': 1},
        {'lines': List.filled(501, rawLine)},
        {
          'lines': [1],
        },
        {'currency_code': 1},
        {'quotation_date': 'tomorrow'},
        {'payment_terms_days': '30'},
        {
          'lines': [
            {...rawLine, 'conversion_numerator': '0'},
          ],
        },
      ]) {
        expect(
          () => QuotationDraftCodec.fromJson({...input(), ...patch}),
          throwsFormatException,
        );
      }
      expect(
        () => QuotationListQuery(search: 'x' * 201),
        throwsFormatException,
      );
      expect(
        () => QuotationListQuery(status: 'foreign'),
        throwsFormatException,
      );
      expect(
        QuotationListQuery(
          cursor: '11111111-1111-1111-1111-111111111111',
        ).cursor,
        isNotNull,
      );
      expect(
        () => SalesOrderDraftCodec.fromJson({
          ...input(),
          'order_date': '2026-09-06',
          'promised_date': '2026-10-06',
          'warehouse_id': 1,
          'ship_to': [],
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'header discounts retain conflicting intent and report exact field errors',
    () {
      for (final amount in [
        Money.parse('-0.000001', 'LKR'),
        Money.zero('USD'),
      ]) {
        expect(
          discounted(amount: amount).validate().issues.map((i) => i.field),
          contains('header_discount_amount'),
        );
      }
      for (final percent in [
        ExactDecimal.parse('-0.000001', scale: 6),
        ExactDecimal.parse('100.000001', scale: 6),
        ExactDecimal.parse('10', scale: 2),
      ]) {
        expect(
          discounted(percent: percent).validate().issues.map((i) => i.field),
          contains('header_discount_percent'),
        );
      }
      for (final value in ['0', '100']) {
        final d = discounted(percent: ExactDecimal.parse(value, scale: 6));
        expect(d.validate().isValid, true);
        expect(d.toJson()['header_discount_percent'], '$value.000000');
      }
      expect(discounted(amount: Money.zero('LKR')).validate().isValid, true);
      final both = QuotationDraftCodec.fromJson({
        ...input(),
        'header_discount_amount': '1',
        'header_discount_percent': '10',
      });
      expect(
        both.validate().issues.map((i) => i.field),
        contains('header_discount'),
      );
      final line = (input()['lines'] as List).single as Map<String, Object?>;
      final lineBoth = QuotationDraftCodec.fromJson({
        ...input(),
        'lines': [
          {...line, 'discount_amount': '1', 'discount_percent': '10'},
        ],
      });
      expect(
        lineBoth.validate().issues.map((i) => i.field),
        contains('lines[0].discount'),
      );
      final order = SalesOrderDraftCodec.fromJson({
        ...input(),
        'order_date': '2026-09-06',
        'promised_date': '2026-10-06',
        'warehouse_id': 'warehouse',
        'ship_to': {'address': 'Customer'},
        'header_discount_amount': '1',
        'header_discount_percent': '10',
      });
      expect(
        order.validate().issues.map((i) => i.field),
        contains('header_discount'),
      );
    },
  );

  test(
    'Money preserves signed exact arithmetic and rejects currency mixing',
    () {
      final a = Money.parse('90071992547409.123456', ' lkr ');
      final unit = Money.parse('0.000001', 'LKR');
      expect(((a + unit) - a).toDecimalString(), '0.000001');
      expect((-unit).toString(), 'LKR -0.000001');
      expect(Money.parse('-0.0000005', 'LKR'), -unit);
      expect(Money.parse('0.0000004', 'LKR'), Money.zero('LKR'));
      expect(unit.multiplyRatio(-1, 2), -unit);
      expect(unit.multiplyRatio(1, -2), -unit);
      expect(unit.multiplyRatio(1, 3), Money.zero('LKR'));
      expect(() => unit.multiplyRatio(1, 0), throwsArgumentError);
      expect(a.compareTo(unit), greaterThan(0));
      expect(a.hashCode, Money.fromMinorUnits(a.minorUnits, 'LKR').hashCode);
    expect(a == ('money' as Object), false);
      expect(a == Money.parse('1', 'LKR'), false);
      expect(unit == Money.parse('0.000001', 'USD'), false);
      for (final operation in [
        () => a + Money.zero('USD'),
        () => a - Money.zero('USD'),
        () => a.compareTo(Money.zero('USD')),
      ]) {
        expect(operation, throwsStateError);
      }
      for (final value in ['', '1e6', 'NaN']) {
        expect(() => Money.parse(value, 'LKR'), throwsFormatException);
      }
      expect(() => Money.zero('LK'), throwsArgumentError);
    },
  );

  test(
    'procurement comparison detects incomplete, repeated and mismatched offers',
    () {
      SupplierComparison compare(
        Map<String, String> required,
        List<Map<String, Object?>> lines, {
        String rate = '1',
      }) => SupplierComparison(
        requiredQuantities: required,
        quotedLines: lines,
        exchangeRate: rate,
      );
      final quoted = <String, Object?>{
        'source_line_id': 'a',
        'quantity': '2',
        'line_total': '0.000001',
      };
      expect(compare({'a': '2'}, [quoted]).complete, true);
      expect(compare({'a': '2', 'b': '1'}, [quoted]).complete, false);
      expect(compare({'a': '1'}, [quoted]).complete, false);
      expect(
        compare({'a': '2'}, [quoted], rate: '2').baseTotal.toDecimalString(),
        '0.000002',
      );
      for (final required in [
        <String, String>{},
        {'a': '0'},
        {for (var i = 0; i < 501; i++) '$i': '1'},
      ]) {
        expect(() => compare(required, []), throwsFormatException);
      }
      expect(
        () => compare({'a': '1'}, List.filled(501, quoted)),
        throwsFormatException,
      );
      expect(
        () => compare({'a': '2'}, [quoted], rate: '0'),
        throwsFormatException,
      );
      for (final lines in <List<Map<String, Object?>>>[
        [quoted, quoted],
        [
          {...quoted, 'source_line_id': null},
        ],
        [
          {...quoted, 'source_line_id': 'foreign'},
        ],
        [
          {...quoted, 'quantity': '0'},
        ],
        [
          {...quoted, 'quantity': 2},
        ],
        [
          {...quoted, 'line_total': '1e6'},
        ],
      ]) {
        expect(() => compare({'a': '2'}, lines), throwsFormatException);
      }
      final raw = <String, Object?>{
        'line_id': 'line',
        'description': 'Item',
        'unit_id': 'unit',
        'quantity': '2',
        'estimated_unit_price': '0.000001',
        'conversion_numerator': '1',
        'conversion_denominator': '1',
      };
      expect(
        ProcurementLine.fromJson(raw).estimatedTotal.toDecimalString(),
        '0.000002',
      );
      final full = ProcurementLine.fromJson({
        ...raw,
        'product_id': 'product',
        'source_line_id': 'source',
      });
      expect(full.toJson()['source_line_id'], 'source');
      for (final patch in <Map<String, Object?>>[
        {'line_id': null},
        {'description': ''},
        {'description': 'x' * 1001},
        {'product_id': 1},
        {'source_line_id': ''},
        {'quantity': '0'},
        {'estimated_unit_price': 1},
        {'conversion_numerator': '0'},
        {'conversion_denominator': '3'},
        {'quantity': '99999999999999', 'conversion_numerator': '2'},
        {
          'quantity': '99999999999999',
          'estimated_unit_price': '99999999999999',
        },
      ]) {
        expect(
          () => ProcurementLine.fromJson({...raw, ...patch}),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'unit conversions and count identities reject overflow and fractional serials',
    () {
      for (final ratio in [0, '0', '9223372036854775808']) {
        expect(
          () => InventoryTransferQuantity('1', ratio, '1'),
          throwsFormatException,
        );
        expect(
          () => InventoryTransferQuantity('1', '1', ratio),
          throwsFormatException,
        );
      }
      expect(
        () => InventoryTransferQuantity('99999999999999', '2', '1'),
        throwsFormatException,
      );
      expect(
        () => InventoryTransferQuantity('0.000001', '1', '3'),
        throwsFormatException,
      );
      final q = InventoryTransferQuantity('2', '1', '1');
      q.validateSerialCount(2);
      expect(() => q.validateSerialCount(1), throwsFormatException);
      expect(q.baseQuantity, '2.000000');
      GoodsReceiptQuantity receipt(
        Object? n,
        Object? d, {
        String accepted = '1',
      }) => GoodsReceiptQuantity(
        accepted: accepted,
        rejected: '0',
        numerator: n,
        denominator: d,
      );
      for (final ratio in [1, '0', '1000000000000000000']) {
        expect(() => receipt(ratio, '1'), throwsFormatException);
        expect(() => receipt('1', ratio), throwsFormatException);
      }
      expect(
        () => receipt('2', '1', accepted: '99999999999999'),
        throwsFormatException,
      );
      expect(receipt('1', '1', accepted: '0').empty, true);
      expect(receipt('1', '1').empty, false);
      expect(
        () => stockCountIdentityTotal([
          {'id': 'a', 'counted_quantity': 1},
        ], serial: false),
        throwsFormatException,
      );
      expect(
        () => stockCountIdentityTotal([
          {'id': 'a', 'counted_quantity': '99999999999999'},
          {'id': 'b', 'counted_quantity': '1'},
        ], serial: false),
        throwsFormatException,
      );
      expect(
        stockCountIdentityTotal([
          {'id': 'a', 'counted_quantity': '0'},
          {'id': 'b', 'counted_quantity': '1'},
        ], serial: true),
        '1.000000',
      );
    },
  );

  test(
    'partial return amounts conserve the final source amount at every supported precision',
    () {
      for (final scale in [-1, 7]) {
        expect(
          () => PurchaseReturnAmount(
            originalQuantity: '3',
            consumedQuantity: '0',
            returnQuantity: '1',
            netAmount: '1',
            taxAmount: '0',
            roundingScale: scale,
          ),
          throwsFormatException,
        );
      }
      for (var scale = 0; scale <= 6; scale++) {
        var sum = BigInt.zero;
        for (var used = 0; used < 3; used++) {
          final part = PurchaseReturnAmount(
            originalQuantity: '3',
            consumedQuantity: '$used',
            returnQuantity: '1',
            netAmount: '100',
            taxAmount: '15',
            roundingScale: scale,
          );
          sum += part.total.scaledValue;
        }
        expect(sum.toString(), '115000000');
      }
    },
  );

  test(
    'receivable drafts require coherent source links, dates and immutable exact line inputs',
    () {
      final base = <String, Object?>{
        'id': 'document',
        'customer_id': 'customer',
        'currency_code': 'LKR',
        'document_date': '2026-09-30',
        'due_date': '2026-10-30',
      };
      final line = <String, Object?>{
        'line_id': 'line',
        'base_quantity': '1',
        'product_id': 'product',
        'unit_id': 'unit',
        'quantity': '1',
        'unit_price': '5',
        'conversion_numerator': '1',
        'conversion_denominator': '1',
      };
      for (final patch in <Map<String, Object?>>[
        {'id': null},
        {'customer_id': ''},
        {'currency_code': 'lkr'},
        {'document_date': 'not-date'},
        {'due_date': '2026-09-29'},
        {'due_date': '2026-02-30'},
        {'lines': null},
        {'lines': []},
        {'lines': List.filled(501, line)},
      ]) {
        expect(
          ReceivableDraft(ReceivableKind.invoice, {
            ...base,
            'lines': [line],
            ...patch,
          }).validate(),
          isNotEmpty,
        );
      }
      for (final kind in ReceivableKind.values) {
        expect(kind.canRead({}), false);
        for (final capability in [
          '${kind.permission}.view',
          kind.managePermission,
          kind.postPermission,
          'workflow.approvals.decide',
        ]) {
          expect(kind.canRead({capability}), true);
        }
      }
      expect(() => receivableMap([]), throwsFormatException);
      expect(receivableDate('2026-09-30'), true);
      expect(receivableDate('2026-13-30'), false);
      for (final patch in <Map<String, Object?>>[
        {'line_id': null},
        {'base_quantity': '0'},
        {'base_quantity': 1},
        {'unit_price': 1},
        {
          for (final key in [
            'product_id',
            'unit_id',
            'quantity',
            'unit_price',
            'conversion_numerator',
            'conversion_denominator',
          ])
            key: null,
        },
      ]) {
        expect(
          ReceivableDraft(ReceivableKind.invoice, {
            ...base,
            'lines': [
              {...line, ...patch},
            ],
          }).validate(),
          isNotEmpty,
        );
      }
      expect(
        ReceivableDraft(ReceivableKind.invoice, {
          ...base,
          'lines': [line, line],
        }).validate(),
        contains('line.1'),
      );
      expect(
        ReceivableDraft(ReceivableKind.invoice, {
          ...base,
          'lines': [line],
        }).validate(),
        isEmpty,
      );
      for (final source in ['sales_order_line_id', 'delivery_line_id']) {
        expect(
          ReceivableDraft(ReceivableKind.invoice, {
            ...base,
            'lines': [
              {...line, source: 'source'},
            ],
          }).validate(),
          isEmpty,
        );
      }
      final delivery = {
        ...base,
        'sales_order_id': 'order',
        'warehouse_id': 'warehouse',
        'lines': [
          {...line, 'sales_order_line_id': 'order-line'},
        ],
      };
      expect(
        ReceivableDraft(ReceivableKind.delivery, delivery).validate(),
        isEmpty,
      );
      expect(
        ReceivableDraft(ReceivableKind.delivery, {
          ...base,
          'lines': [line],
        }).validate(),
        isNotEmpty,
      );
      for (final source in ['sales_invoice_line_id', 'delivery_line_id']) {
        expect(
          ReceivableDraft(ReceivableKind.credit, {
            ...base,
            'reason': 'Returned',
            'lines': [
              {...line, source: 'source', 'disposition': 'no_restock'},
            ],
          }).validate(),
          isEmpty,
        );
      }
      expect(
        ReceivableDraft(ReceivableKind.credit, {
          ...base,
          'reason': 'Returned',
          'lines': [line],
        }).validate(),
        isNotEmpty,
      );
      for (final patch in <Map<String, Object?>>[
        {'amount': '-1'},
        {'amount': 1},
        {'cash_bank_account_id': null},
      ]) {
        expect(
          ReceivableDraft(ReceivableKind.receipt, {
            ...base,
            'amount': '1',
            'cash_bank_account_id': 'bank',
            ...patch,
          }).validate(),
          isNotEmpty,
        );
      }
    },
  );

  test(
    'receivable read snapshots preserve immutable totals, source inputs and receipt intent',
    () {
      final base = <String, Object?>{
        'id': 'document',
        'document_type': 'sales_invoice',
        'status': 'draft',
        'customer_id': 'customer',
        'currency_code': 'LKR',
        'document_date': '2026-09-30',
        'grand_total': '90071992547409.123456',
        'base_total': '90071992547409.123456',
        'tax_total': '0',
        'version': 1,
      };
      for (final field in [
        'id',
        'document_type',
        'status',
        'customer_id',
        'currency_code',
        'document_date',
      ]) {
        expect(
          () => ReceivableDocument({...base, field: null}),
          throwsFormatException,
        );
      }
      for (final version in [null, '1', 0]) {
        expect(
          () => ReceivableDocument({...base, 'version': version}),
          throwsFormatException,
        );
      }
      for (final field in ['grand_total', 'base_total', 'tax_total']) {
        expect(
          () => ReceivableDocument({...base, field: 1}),
          throwsFormatException,
        );
      }
      final d = ReceivableDocument(base);
      expect(
        [d.id, d.status, d.number, d.currency, d.total],
        ['document', 'draft', 'Draft', 'LKR', '90071992547409.123456'],
      );
      expect(d.version, 1);
      expect(d.editable, true);
      expect(d.lines, isEmpty);
      expect(d.kind, ReceivableKind.invoice);
      for (final kind in ReceivableKind.values) {
        final doc = ReceivableDocument({
          ...base,
          'document_type': kind.wire,
          'status': 'posted',
          'document_number': 'DOC-001',
          'lines': [
            {
              'snapshot': {'line_id': 'frozen', 'base_quantity': '1'},
            },
          ],
        });
        expect(doc.editable, false);
        expect(doc.number, 'DOC-001');
        expect(doc.toDraft()['lines'], [
          {'line_id': 'frozen', 'base_quantity': '1'},
        ]);
        if (kind == ReceivableKind.receipt) {
          expect(doc.toDraft()['amount'], doc.total);
        }
        doc.lines.clear();
        expect(doc.lines, hasLength(1));
      }
      expect(
        const ReceivableFailure('ACCESS_DENIED', 'Scope changed').toString(),
        'ACCESS_DENIED: Scope changed',
      );
    },
  );
}
