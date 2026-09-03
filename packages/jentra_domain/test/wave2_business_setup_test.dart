import 'package:jentra_domain/jentra_domain.dart';
import 'package:test/test.dart';

void main() {
  group('ExactDecimal — FR-208 / FR-210 / NFR-206', () {
    test('preserves configured fixed scale without binary floating point', () {
      final rate = ExactDecimal.parse('312.1234567891', scale: 10);

      expect(rate.toDecimalString(), '312.1234567891');
      expect(rate.scale, 10);
      expect(rate.scaledValue, BigInt.parse('3121234567891'));
    });

    test('rounds excess precision half away from zero', () {
      expect(
        ExactDecimal.parse('1.23456789015', scale: 10).toDecimalString(),
        '1.2345678902',
      );
      expect(
        ExactDecimal.parse('-1.23456789015', scale: 10).toDecimalString(),
        '-1.2345678902',
      );
    });

    test('compares only values with the same scale', () {
      final left = ExactDecimal.parse('18', scale: 6);
      final right = ExactDecimal.parse('18.000000', scale: 6);

      expect(left, right);
      expect(
        () => left.compareTo(ExactDecimal.parse('18', scale: 2)),
        throwsStateError,
      );
    });
  });

  group('BusinessSetupValidator — AC-202 through AC-209', () {
    test('accepts an exact dated cross-currency exchange rate', () {
      final result = BusinessSetupValidator.validate(
        BusinessSetupResource.exchangeRates,
        const {
          'source_currency_code': 'USD',
          'target_currency_code': 'LKR',
          'rate': '312.1234567891',
          'effective_date': '2026-09-01',
          'rate_type': 'spot',
          'source': 'manual',
          'status': 'active',
        },
      );

      expect(result.isValid, isTrue);
    });

    test('rejects same-currency and non-positive exchange rates', () {
      final result = BusinessSetupValidator.validate(
        BusinessSetupResource.exchangeRates,
        const {
          'source_currency_code': 'LKR',
          'target_currency_code': 'LKR',
          'rate': '0',
          'effective_date': '2026-09-01',
          'rate_type': 'spot',
        },
      );

      expect(
        result.issues.map((issue) => issue.field),
        containsAll(['target_currency_code', 'rate']),
      );
    });

    test('enforces tax percentage and validity bounds', () {
      final invalid = BusinessSetupValidator.validate(
        BusinessSetupResource.taxDefinitions,
        const {
          'code': 'VAT-OVER',
          'name': 'Invalid VAT',
          'rate': '100.000001',
          'kind': 'output',
          'valid_from': '2026-09-30',
          'valid_to': '2026-09-01',
          'status': 'active',
        },
      );

      expect(
        invalid.issues.map((issue) => issue.field),
        containsAll(['rate', 'valid_to']),
      );
    });

    test('rejects a self-parent account and reversed approval range', () {
      final account = BusinessSetupValidator.validate(
        BusinessSetupResource.accounts,
        const {
          'id': '10000000-0000-0000-0000-000000000001',
          'code': '1000',
          'name': 'Cash',
          'account_type': 'asset',
          'normal_balance': 'debit',
          'parent_id': '10000000-0000-0000-0000-000000000001',
          'is_posting': true,
          'status': 'active',
        },
      );
      final approval = BusinessSetupValidator.validate(
        BusinessSetupResource.approvalMatrixSteps,
        const {
          'workflow_definition_id': '20000000-0000-0000-0000-000000000001',
          'role_id': '30000000-0000-0000-0000-000000000001',
          'step_order': 1,
          'minimum_amount': '2000.000000',
          'maximum_amount': '1000.000000',
          'currency_code': 'LKR',
          'status': 'active',
        },
      );

      expect(account.issues.map((issue) => issue.field), contains('parent_id'));
      expect(
        approval.issues.map((issue) => issue.field),
        contains('maximum_amount'),
      );
    });

    test('requires scoped product and document-sequence fields', () {
      final product = BusinessSetupValidator.validate(
        BusinessSetupResource.products,
        const {
          'sku': 'SKU-1',
          'name': 'Tea pack',
          'kind': 'stocked',
          'tracking_mode': 'none',
          'can_sell': true,
          'can_purchase': true,
          'status': 'active',
        },
      );
      final sequence = BusinessSetupValidator.validate(
        BusinessSetupResource.documentSequences,
        const {
          'document_type': 'sales_invoice',
          'prefix': 'INV-',
          'padding': 13,
          'reset_policy': 'yearly',
          'next_value': 1,
          'status': 'active',
        },
      );

      expect(
        product.issues.map((issue) => issue.field),
        contains('base_unit_id'),
      );
      expect(sequence.issues.map((issue) => issue.field), contains('padding'));
    });

    test('accepts only canonical workflow states and transition pairs', () {
      final valid = BusinessSetupValidator.validate(
        BusinessSetupResource.workflowDefinitions,
        const {
          'document_type': 'purchase_order',
          'name': 'Purchase order lifecycle',
          'lifecycle': {
            'states': [
              'draft',
              'submitted',
              'approved',
              'rejected',
              'posted',
              'settled',
              'fulfilled',
              'closed',
              'cancelled',
              'reversed',
            ],
            'transitions': [
              ['draft', 'submitted'],
              ['submitted', 'approved'],
              ['approved', 'posted'],
              ['posted', 'fulfilled'],
              ['fulfilled', 'closed'],
            ],
          },
          'status': 'active',
        },
      );
      final invalid = BusinessSetupValidator.validate(
        BusinessSetupResource.workflowDefinitions,
        const {
          'document_type': 'purchase_order',
          'name': 'Unsafe lifecycle',
          'lifecycle': {
            'states': [
              'draft',
              'submitted',
              'approved',
              'rejected',
              'posted',
              'settled',
              'fulfilled',
              'closed',
              'cancelled',
              'reversed',
            ],
            'transitions': [
              ['posted', 'draft'],
            ],
          },
          'status': 'active',
        },
      );

      expect(valid.isValid, isTrue);
      expect(invalid.issues.map((issue) => issue.field), contains('lifecycle'));
    });
  });

  group('Setup contracts — FR-201 / FR-240 / NFR-202', () {
    test('resource metadata carries public API and permission contracts', () {
      expect(BusinessSetupResource.parties.apiView, 'parties');
      expect(
        BusinessSetupResource.parties.managePermission,
        'crm.parties.manage',
      );
      expect(
        BusinessSetupResource.reportDefinitions.category,
        BusinessSetupCategory.reports,
      );
    });

    test('list queries enforce a bounded cursor page', () {
      expect(() => SetupListQuery(limit: 201), throwsArgumentError);
      expect(SetupListQuery(limit: 200).limit, 200);
      final query = SetupListQuery(
        search: '  VAT [18%]  ',
        status: 'active',
        limit: 50,
        cursor: 'opaque-cursor',
      );

      expect(query.normalizedSearch, 'VAT [18%]');
      expect(query.limit, 50);
    });

    test('records preserve exact decimal strings and optimistic versions', () {
      final record =
          SetupRecord.fromJson(BusinessSetupResource.exchangeRates, const {
            'id': '40000000-0000-0000-0000-000000000001',
            'tenant_id': '50000000-0000-0000-0000-000000000001',
            'legal_entity_id': '60000000-0000-0000-0000-000000000001',
            'code': 'USD/LKR',
            'name': 'USD to LKR',
            'status': 'active',
            'version': 7,
            'rate': '312.1234567891',
            'created_at': '2026-09-01T00:00:00Z',
            'updated_at': '2026-09-01T01:00:00Z',
          });

      expect(record.version, 7);
      expect(record.fields['rate'], '312.1234567891');
      expect(record.updatedAt, DateTime.utc(2026, 9, 1, 1));
    });
  });

  group('Attachment policy — AC-210 / NFR-209', () {
    test('allows only private Wave 2 document formats under 25 MiB', () {
      expect(
        AttachmentFilePolicy.validate(
          fileName: 'invoice.pdf',
          mimeType: 'application/pdf',
          byteSize: 1024,
        ).isValid,
        isTrue,
      );
      expect(
        AttachmentFilePolicy.signedReadLifetime,
        const Duration(minutes: 15),
      );
    });

    test('rejects traversal, executable MIME, and oversized files', () {
      final invalid = AttachmentFilePolicy.validate(
        fileName: '../payload.exe',
        mimeType: 'application/x-msdownload',
        byteSize: AttachmentFilePolicy.maximumBytes + 1,
      );

      expect(
        invalid.issues.map((issue) => issue.field),
        containsAll(['file_name', 'mime_type', 'byte_size']),
      );
    });
  });
}
