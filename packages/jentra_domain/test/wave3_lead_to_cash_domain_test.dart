import 'package:jentra_domain/jentra_domain.dart';
import 'package:test/test.dart';

void main() {
  group('Wave 3 quotation pricing — AC-303 / NFR-302', () {
    test(
      'calculates exclusive and inclusive tax without binary floating point',
      () {
        final pricing = QuotationPricingCalculator.calculate(
          currencyCode: 'LKR',
          baseCurrencyCode: 'LKR',
          exchangeRate: ExactDecimal.parse('1.0000000000', scale: 10),
          roundingScale: 2,
          headerDiscountPercent: ExactDecimal.parse('10.000000', scale: 6),
          lines: [
            QuotationLineDraft(
              lineId: 'line-exclusive',
              productId: 'product-stocked',
              description: 'Stocked unit',
              quantity: CommercialQuantity(
                quantity: ExactDecimal.parse('2.000000', scale: 6),
                unitId: 'unit-each',
                baseQuantity: ExactDecimal.parse('2.000000', scale: 6),
                conversionNumerator: BigInt.one,
                conversionDenominator: BigInt.one,
              ),
              unitPrice: Money.parse('100.000000', 'LKR'),
              discountPercent: ExactDecimal.parse('10.000000', scale: 6),
              taxDefinitionId: 'tax-exclusive',
              previewTax: QuotationTaxSnapshot(
                definitionId: 'tax-exclusive',
                code: 'OUTPUT15',
                name: 'Output 15%',
                kind: 'output',
                rate: ExactDecimal.parse('15.000000', scale: 6),
                inclusive: false,
                definitionVersion: 1,
              ),
            ),
            QuotationLineDraft(
              lineId: 'line-inclusive',
              productId: 'product-service',
              description: 'Inclusive service',
              quantity: CommercialQuantity(
                quantity: ExactDecimal.parse('1.000000', scale: 6),
                unitId: 'unit-each',
                baseQuantity: ExactDecimal.parse('1.000000', scale: 6),
                conversionNumerator: BigInt.one,
                conversionDenominator: BigInt.one,
              ),
              unitPrice: Money.parse('115.000000', 'LKR'),
              taxDefinitionId: 'tax-inclusive',
              previewTax: QuotationTaxSnapshot(
                definitionId: 'tax-inclusive',
                code: 'OUTPUT15I',
                name: 'Output 15% inclusive',
                kind: 'output',
                rate: ExactDecimal.parse('15.000000', scale: 6),
                inclusive: true,
                definitionVersion: 1,
              ),
            ),
          ],
        );

        expect(pricing.subtotal.toDecimalString(), '315.000000');
        expect(pricing.lineDiscountTotal.toDecimalString(), '20.000000');
        expect(pricing.headerDiscountTotal.toDecimalString(), '29.500000');
        expect(pricing.discountTotal.toDecimalString(), '49.500000');
        expect(pricing.taxTotal.toDecimalString(), '37.800000');
        expect(pricing.grandTotal.toDecimalString(), '289.800000');
        expect(pricing.baseTotal.toDecimalString(), '289.800000');
        expect(pricing.lines[0].taxAmount.toDecimalString(), '24.300000');
        expect(pricing.lines[0].lineTotal.toDecimalString(), '186.300000');
        expect(pricing.lines[1].netAmount.toDecimalString(), '90.000000');
        expect(pricing.lines[1].taxAmount.toDecimalString(), '13.500000');
        expect(pricing.lines[1].lineTotal.toDecimalString(), '103.500000');
      },
    );

    test(
      'allocates an amount header discount exactly and preserves base rate',
      () {
        final pricing = QuotationPricingCalculator.calculate(
          currencyCode: 'USD',
          baseCurrencyCode: 'LKR',
          exchangeRate: ExactDecimal.parse('325.1250000000', scale: 10),
          roundingScale: 2,
          headerDiscountAmount: Money.parse('0.010000', 'USD'),
          lines: [
            _untaxedLine('line-a', '0.030000'),
            _untaxedLine('line-b', '0.020000'),
          ],
        );

        expect(pricing.headerDiscountTotal.toDecimalString(), '0.010000');
        expect(
          pricing.lines.map(
            (line) => line.headerDiscountAmount.toDecimalString(),
          ),
          ['0.010000', '0.000000'],
        );
        expect(pricing.grandTotal.toDecimalString(), '0.040000');
        expect(pricing.baseTotal.toDecimalString(), '13.010000');
      },
    );

    test(
      'keeps every rounded proportional discount allocation non-negative',
      () {
        final pricing = QuotationPricingCalculator.calculate(
          currencyCode: 'USD',
          baseCurrencyCode: 'USD',
          exchangeRate: ExactDecimal.parse('1.0000000000', scale: 10),
          roundingScale: 2,
          headerDiscountAmount: Money.parse('0.020000', 'USD'),
          lines: [
            _untaxedLine('line-a', '0.260000'),
            _untaxedLine('line-b', '0.260000'),
            _untaxedLine('line-c', '0.260000'),
            _untaxedLine('line-d', '0.220000'),
          ],
        );

        expect(
          pricing.lines.map(
            (line) => line.headerDiscountAmount.toDecimalString(),
          ),
          ['0.010000', '0.000000', '0.010000', '0.000000'],
        );
        expect(
          pricing.lines.every(
            (line) => line.headerDiscountAmount.minorUnits >= BigInt.zero,
          ),
          isTrue,
        );
        expect(
          pricing.lines.fold(
            Money.zero('USD'),
            (total, line) => total + line.headerDiscountAmount,
          ),
          pricing.headerDiscountTotal,
        );
      },
    );

    test('rejects incoherent units, discounts, currencies, and rates', () {
      final badQuantity = CommercialQuantity(
        quantity: ExactDecimal.parse('2.000000', scale: 6),
        unitId: 'unit-case',
        baseQuantity: ExactDecimal.parse('5.000000', scale: 6),
        conversionNumerator: BigInt.from(3),
        conversionDenominator: BigInt.one,
      );
      expect(badQuantity.validate(field: 'quantity').isValid, isFalse);

      final line = _untaxedLine('line-a', '1.000000').copyWith(
        discountAmount: Money.parse('0.100000', 'USD'),
        discountPercent: ExactDecimal.parse('10.000000', scale: 6),
      );
      expect(line.validate(currencyCode: 'USD').isValid, isFalse);

      expect(
        () => QuotationPricingCalculator.calculate(
          currencyCode: 'USD',
          baseCurrencyCode: 'LKR',
          exchangeRate: ExactDecimal.zero(scale: 10),
          roundingScale: 2,
          lines: [_untaxedLine('line-a', '1.000000')],
        ),
        throwsArgumentError,
      );
    });
  });

  group('Wave 3 quotation contracts — FR-319..FR-321', () {
    test(
      'draft emits only decimal strings and version-aware revision intent',
      () {
        final draft = QuotationDraft(
          id: 'quotation-1',
          customerId: 'customer-1',
          contactId: 'contact-1',
          opportunityId: 'opportunity-1',
          quotationDate: DateTime.utc(2026, 9, 5),
          validUntil: DateTime.utc(2026, 10, 5),
          currencyCode: 'USD',
          exchangeRateId: 'rate-1',
          exchangeRate: ExactDecimal.parse('325.1250000000', scale: 10),
          rateDate: DateTime.utc(2026, 9, 5),
          paymentTermsDays: 30,
          deliveryTerms: 'Delivered to Colombo',
          salespersonId: 'user-1',
          headerDiscountPercent: ExactDecimal.parse('5.000000', scale: 6),
          notes: 'Customer-facing note',
          createRevision: true,
          revisionReason: 'Validity extended',
          lines: [_untaxedLine('line-a', '10.000000')],
        );

        expect(draft.validate().isValid, isTrue);
        final json = draft.toJson();
        expect(json, containsPair('currency_code', 'USD'));
        expect(json, containsPair('exchange_rate', '325.1250000000'));
        expect(json, containsPair('header_discount_percent', '5.000000'));
        expect(json, containsPair('create_revision', true));
        expect((json['lines'] as List).single, isA<Map<String, Object?>>());
        expect(
          ((json['lines'] as List).single as Map)['unit_price'],
          '10.000000',
        );
      },
    );

    test('parses exact quotation and immutable revision read models', () {
      final quotation = SalesQuotation.fromJson(_quotationJson());
      final revision = SalesQuotationRevision.fromJson({
        'id': 'revision-1',
        'tenant_id': 'tenant-1',
        'legal_entity_id': 'entity-1',
        'branch_id': 'branch-1',
        'quotation_id': 'quotation-1',
        'revision_number': 2,
        'document_number': 'QUO-000001',
        'status': 'submitted',
        'reason': 'Validity extended',
        'snapshot': _quotationJson(),
        'created_by': 'user-1',
        'created_at': '2026-09-05T10:00:00Z',
      });

      expect(quotation.currentRevision, 2);
      expect(quotation.grandTotal.toDecimalString(), '289.800000');
      expect(quotation.exchangeRate.toDecimalString(), '325.1250000000');
      expect(revision.revisionNumber, 2);
      expect(revision.snapshot['grand_total'], '289.800000');
    });

    test('transition and approval decisions serialize explicit intent', () {
      final transition = OperationalDocumentTransition(
        documentType: OperationalDocumentType.salesQuotation,
        documentId: 'quotation-1',
        action: OperationalDocumentAction.accept,
        reason: 'Customer accepted by email',
      );
      final decision = OperationalApprovalDecision(
        documentType: OperationalDocumentType.salesQuotation,
        documentId: 'quotation-1',
        decision: ApprovalDecision.approved,
        note: 'Commercial terms approved',
      );

      expect(transition.validate().isValid, isTrue);
      expect(transition.toJson(), containsPair('action', 'accept'));
      expect(decision.validate().isValid, isTrue);
      expect(decision.toJson(), containsPair('decision', 'approved'));
    });
  });

  group('Wave 3 order, credit, and reservation contracts — AC-304', () {
    test('parses traced sales-order quantities as exact decimals', () {
      final order = SalesOrder.fromJson({
        'id': 'order-1',
        'tenant_id': 'tenant-1',
        'legal_entity_id': 'entity-1',
        'branch_id': 'branch-1',
        'document_number': null,
        'source_quotation_id': 'quotation-1',
        'source_quotation_revision': 2,
        'customer_id': 'customer-1',
        'contact_id': 'contact-1',
        'currency_code': 'LKR',
        'exchange_rate': '1.0000000000',
        'rate_date': '2026-09-05',
        'promised_date': '2026-09-20',
        'ship_to': {'city': 'Colombo'},
        'warehouse_id': 'warehouse-1',
        'payment_terms_days': 30,
        'delivery_terms': 'Delivered',
        'subtotal': '315.000000',
        'discount_total': '49.500000',
        'tax_total': '37.800000',
        'grand_total': '289.800000',
        'base_total': '289.800000',
        'status': 'confirmed',
        'version': 3,
        'confirmed_at': '2026-09-05T11:00:00Z',
        'created_at': '2026-09-05T10:30:00Z',
        'updated_at': '2026-09-05T11:00:00Z',
      });
      final line = SalesOrderLine.fromJson({
        'id': 'order-line-1',
        'sales_order_id': 'order-1',
        'source_quotation_line_id': 'quote-line-1',
        'source_quotation_revision': 2,
        'product_id': 'product-1',
        'description': 'Stocked unit',
        'unit_id': 'unit-1',
        'conversion_numerator': '1',
        'conversion_denominator': '1',
        'ordered_quantity': '2.000000',
        'base_ordered_quantity': '2.000000',
        'cancelled_quantity': '0.000000',
        'allocated_quantity': '1.500000',
        'delivered_quantity': '0.000000',
        'invoiced_quantity': '0.000000',
        'unit_price': '100.000000',
        'line_total': '186.300000',
        'currency_code': 'LKR',
        'version': 2,
      });

      expect(order.sourceQuotationRevision, 2);
      expect(order.grandTotal.toDecimalString(), '289.800000');
      expect(line.orderedQuantity.toDecimalString(), '2.000000');
      expect(line.remainingToReserve.toDecimalString(), '0.500000');
    });

    test('credit decision never combines different currencies', () {
      expect(
        () => CreditDecisionSnapshot(
          currencyCode: 'LKR',
          creditLimit: Money.parse('500.000000', 'LKR'),
          dueExposure: Money.parse('100.000000', 'LKR'),
          overdueExposure: Money.parse('50.000000', 'USD'),
          existingOrderExposure: Money.zero('LKR'),
          currentOrderExposure: Money.parse('289.800000', 'LKR'),
          overrideApplied: false,
        ),
        throwsStateError,
      );
    });

    test('reservation input stays bounded, online, and exact', () {
      final draft = StockReservationDraft(
        salesOrderId: 'order-1',
        expiresAt: DateTime.utc(2026, 9, 12, 12),
        lines: [
          StockReservationLineDraft(
            salesOrderLineId: 'order-line-1',
            requestedBaseQuantity: ExactDecimal.parse('2.000000', scale: 6),
          ),
        ],
      );

      expect(draft.validate().isValid, isTrue);
      expect(
        (draft.toJson()['lines'] as List).single,
        containsPair('requested_base_quantity', '2.000000'),
      );
      expect(draft.toJson()['expires_at'], '2026-09-12T12:00:00.000Z');
    });
  });
}

QuotationLineDraft _untaxedLine(String id, String unitPrice) =>
    QuotationLineDraft(
      lineId: id,
      description: 'Untaxed line',
      quantity: CommercialQuantity(
        quantity: ExactDecimal.parse('1.000000', scale: 6),
        unitId: 'unit-each',
        baseQuantity: ExactDecimal.parse('1.000000', scale: 6),
        conversionNumerator: BigInt.one,
        conversionDenominator: BigInt.one,
      ),
      unitPrice: Money.parse(unitPrice, 'USD'),
    );

Map<String, Object?> _quotationJson() => {
  'id': 'quotation-1',
  'tenant_id': 'tenant-1',
  'legal_entity_id': 'entity-1',
  'branch_id': 'branch-1',
  'document_number': 'QUO-000001',
  'current_revision': 2,
  'customer_id': 'customer-1',
  'contact_id': 'contact-1',
  'opportunity_id': 'opportunity-1',
  'quotation_date': '2026-09-05',
  'valid_until': '2026-10-05',
  'currency_code': 'USD',
  'base_currency_code': 'LKR',
  'exchange_rate_id': 'rate-1',
  'exchange_rate': '325.1250000000',
  'rate_date': '2026-09-05',
  'payment_terms_days': 30,
  'delivery_terms': 'Delivered to Colombo',
  'salesperson_id': 'user-1',
  'header_discount_amount': '0.000000',
  'header_discount_percent': '10.000000',
  'subtotal': '315.000000',
  'discount_total': '49.500000',
  'tax_total': '37.800000',
  'grand_total': '289.800000',
  'base_total': '94230.225000',
  'notes': 'Customer-facing note',
  'status': 'submitted',
  'workflow_definition_id': 'workflow-1',
  'workflow_revision': 3,
  'version': 4,
  'submitted_at': '2026-09-05T10:00:00Z',
  'approved_at': null,
  'accepted_at': null,
  'created_at': '2026-09-05T09:00:00Z',
  'updated_at': '2026-09-05T10:00:00Z',
};
