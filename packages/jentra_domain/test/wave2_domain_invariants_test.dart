import 'package:jentra_domain/jentra_domain.dart';
import 'package:test/test.dart';

void main() {
  group('ExactDecimal invariants — NFR-206 / AC-203', () {
    test('constructs zero and scaled values with stable predicates', () {
      final zero = ExactDecimal.zero(scale: 6);
      final positive = ExactDecimal.fromScaledValue(BigInt.one, scale: 6);
      final negative = ExactDecimal.fromScaledValue(-BigInt.one, scale: 6);

      expect(zero.isZero, isTrue);
      expect(zero.isPositive, isFalse);
      expect(zero.isNegative, isFalse);
      expect(positive.isPositive, isTrue);
      expect(negative.isNegative, isTrue);
      expect(positive.toString(), '0.000001');
    });

    test('rejects malformed values and unsupported scales', () {
      expect(() => ExactDecimal.parse('1e3', scale: 6), throwsFormatException);
      expect(() => ExactDecimal.zero(scale: -1), throwsRangeError);
      expect(
        () => ExactDecimal.fromScaledValue(BigInt.one, scale: 19),
        throwsRangeError,
      );
    });

    test('supports exact arithmetic, ordering, and scale enforcement', () {
      final left = ExactDecimal.parse('  +2.50 ', scale: 2);
      final right = ExactDecimal.parse('1.25', scale: 2);

      expect((left + right).toDecimalString(), '3.75');
      expect((left - right).toDecimalString(), '1.25');
      expect((-right).toDecimalString(), '-1.25');
      expect(left.compareTo(right), greaterThan(0));
      expect(() => left + ExactDecimal.parse('1', scale: 3), throwsStateError);
      expect(() => left - ExactDecimal.parse('1', scale: 3), throwsStateError);
    });

    test('rescales in both directions with half-away-from-zero rounding', () {
      final value = ExactDecimal.parse('12.345', scale: 3);
      final negative = ExactDecimal.parse('-12.345', scale: 3);

      expect(identical(value.rescale(3), value), isTrue);
      expect(value.rescale(5).toDecimalString(), '12.34500');
      expect(value.rescale(2).toDecimalString(), '12.35');
      expect(negative.rescale(2).toDecimalString(), '-12.35');
      expect(
        ExactDecimal.parse('12.344', scale: 3).rescale(2).toDecimalString(),
        '12.34',
      );
      expect(() => value.rescale(20), throwsRangeError);
    });

    test('supports zero-scale formatting, value equality, and hashes', () {
      final positive = ExactDecimal.parse('8.6', scale: 0);
      final negative = ExactDecimal.parse('-8.6', scale: 0);
      final equal = ExactDecimal.fromScaledValue(BigInt.from(9), scale: 0);
      final Object differentType = '9';

      expect(positive.toDecimalString(), '9');
      expect(negative.toDecimalString(), '-9');
      expect(positive, equal);
      expect(positive.hashCode, equal.hashCode);
      expect(positive == ExactDecimal.parse('9', scale: 1), isFalse);
      expect(positive == differentType, isFalse);
    });
  });

  group('TabularDocument invariants — AC-212 / AC-213', () {
    test('maps short rows, ignores surplus cells, and reports dimensions', () {
      const document = TabularDocument(
        headers: ['code', 'name'],
        rows: [
          ['A'],
          ['B', 'Beta', 'ignored'],
        ],
      );

      expect(document.columnCount, 2);
      expect(document.rowCount, 2);
      expect(document.toRowMaps(), [
        {'code': 'A', 'name': ''},
        {'code': 'B', 'name': 'Beta'},
      ]);
    });

    test('creates a deeply immutable copy', () {
      final source = TabularDocument(
        headers: ['code'],
        rows: [
          ['A'],
        ],
      );
      final copy = source.immutableCopy();
      source.headers[0] = 'changed';
      source.rows[0][0] = 'changed';

      expect(copy.headers, ['code']);
      expect(copy.rows, [
        ['A'],
      ]);
      expect(() => copy.headers.add('name'), throwsUnsupportedError);
      expect(() => copy.rows.add(['B']), throwsUnsupportedError);
      expect(() => copy.rows.single.add('Beta'), throwsUnsupportedError);
    });

    test('compares headers and every row by value', () {
      const document = TabularDocument(
        headers: ['code'],
        rows: [
          ['A'],
        ],
      );
      const equal = TabularDocument(
        headers: ['code'],
        rows: [
          ['A'],
        ],
      );
      final Object differentType = 'table';

      expect(document == document, isTrue);
      expect(document, equal);
      expect(document.hashCode, equal.hashCode);
      expect(document == differentType, isFalse);
      expect(
        document == const TabularDocument(headers: ['code', 'name'], rows: []),
        isFalse,
      );
      expect(
        document == const TabularDocument(headers: ['name'], rows: []),
        isFalse,
      );
      expect(
        document == const TabularDocument(headers: ['code'], rows: []),
        isFalse,
      );
      expect(
        document ==
            const TabularDocument(
              headers: ['code'],
              rows: [
                ['A', 'extra'],
              ],
            ),
        isFalse,
      );
      expect(
        document ==
            const TabularDocument(
              headers: ['code'],
              rows: [
                ['B'],
              ],
            ),
        isFalse,
      );
    });
  });

  group('Setup import preview — FR-232 / AC-212', () {
    test(
      'reports normalized spreadsheet row and field errors before apply',
      () {
        const document = TabularDocument(
          headers: [
            'source_currency_code',
            'target_currency_code',
            'rate',
            'effective_date',
            'rate_type',
            'source',
            'status',
          ],
          rows: [
            ['USD', 'LKR', '312.5', '2026-09-03', 'spot', 'manual', 'active'],
            ['LKR', 'LKR', '0', 'bad-date', 'unknown', 'manual', 'active'],
          ],
        );

        final preview = SetupImportPreview.validate(
          BusinessSetupResource.exchangeRates,
          document,
        );

        expect(preview.isValid, isFalse);
        expect(preview.rowCount, 2);
        expect(preview.invalidRowCount, 1);
        expect(preview.issues.map((issue) => issue.row), everyElement(3));
        expect(
          preview.issues.map((issue) => issue.field),
          containsAll([
            'target_currency_code',
            'rate',
            'effective_date',
            'rate_type',
          ]),
        );
      },
    );

    test('allows a non-empty valid import preview', () {
      const document = TabularDocument(
        headers: ['code', 'name', 'symbol', 'category', 'precision', 'status'],
        rows: [
          ['EA', 'Each', 'ea', 'quantity', '0', 'active'],
        ],
      );

      final preview = SetupImportPreview.validate(
        BusinessSetupResource.units,
        document,
      );
      final empty = SetupImportPreview.validate(
        BusinessSetupResource.units,
        const TabularDocument(headers: ['code'], rows: []),
      );

      expect(preview.isValid, isTrue);
      expect(preview.invalidRowCount, 0);
      expect(empty.isValid, isFalse);
    });
  });

  group('Business setup metadata — FR-201 / NFR-202', () {
    test('defines complete unique API and authorization metadata', () {
      final views = <String>{};
      for (final resource in BusinessSetupResource.values) {
        expect(resource.apiView, isNotEmpty, reason: resource.name);
        expect(resource.label, isNotEmpty, reason: resource.name);
        expect(resource.singularLabel, isNotEmpty, reason: resource.name);
        expect(resource.viewPermission, isNotEmpty, reason: resource.name);
        expect(resource.managePermission, isNotEmpty, reason: resource.name);
        expect(resource.category, isA<BusinessSetupCategory>());
        expect(views.add(resource.apiView), isTrue, reason: resource.name);
        if (resource.isReadOnly) {
          expect(resource.rpcName, isNull, reason: resource.name);
        } else {
          expect(resource.rpcName, isNotNull, reason: resource.name);
        }
      }

      expect(
        BusinessSetupResource.values.where(
          (value) => value.requiresLegalEntity,
        ),
        containsAll(<BusinessSetupResource>[
          BusinessSetupResource.exchangeRates,
          BusinessSetupResource.taxDefinitions,
          BusinessSetupResource.accounts,
          BusinessSetupResource.fiscalPeriods,
          BusinessSetupResource.products,
        ]),
      );
    });
  });

  group('Business setup validation coverage — AC-202 through AC-209', () {
    test('accepts a valid payload for every setup resource', () {
      for (final resource in BusinessSetupResource.values) {
        final result = BusinessSetupValidator.validate(
          resource,
          _validPayload(resource),
        );
        expect(
          result.isValid,
          isTrue,
          reason: '${resource.name}: ${result.issues.map((e) => e.field)}',
        );
      }
    });

    test('reports required fields across the configurable resources', () {
      for (final resource in BusinessSetupResource.values.where(
        (value) => !value.isReadOnly,
      )) {
        final result = BusinessSetupValidator.validate(resource, const {});
        expect(result.isValid, isFalse, reason: resource.name);
      }
    });

    test('rejects malformed scalar values and unsupported statuses', () {
      final exchange = BusinessSetupValidator.validate(
        BusinessSetupResource.exchangeRates,
        const {
          'source_currency_code': 'USD',
          'target_currency_code': 'LKR',
          'rate': 'not-a-number',
          'effective_date': '2026-09-03',
          'rate_type': 'spot',
          'source': 'manual',
          'status': 'retired',
        },
      );
      final unit =
          BusinessSetupValidator.validate(BusinessSetupResource.units, const {
            'code': 'BOX',
            'name': 'Box',
            'symbol': 'box',
            'category': 'quantity',
            'precision': 6.9,
            'status': 'active',
          });
      final sequence = BusinessSetupValidator.validate(
        BusinessSetupResource.documentSequences,
        const {
          'document_type': 'invoice',
          'reset_policy': 'yearly',
          'padding': 'x',
          'status': 'active',
        },
      );

      expect(
        exchange.issues.map((issue) => issue.field),
        containsAll(['rate', 'status']),
      );
      expect(unit.issues.map((issue) => issue.field), contains('precision'));
      expect(sequence.issues.map((issue) => issue.field), contains('padding'));
    });

    test('rejects invalid dates and malformed workflow structures', () {
      final fiscal = BusinessSetupValidator.validate(
        BusinessSetupResource.fiscalPeriods,
        const {
          'name': 'FY 2026',
          'start_date': '2026-01-01',
          'end_date': 'not-a-date',
          'state': 'open',
          'status': 'active',
        },
      );
      final workflow = BusinessSetupValidator.validate(
        BusinessSetupResource.workflowDefinitions,
        const {
          'document_type': 'invoice',
          'name': 'Broken',
          'lifecycle': {
            'states': ['draft'],
            'transitions': [
              ['draft'],
              ['unknown', 'closed'],
              'not-a-pair',
            ],
          },
          'status': 'draft',
        },
      );

      expect(fiscal.issues.map((issue) => issue.field), contains('end_date'));
      expect(
        workflow.issues.map((issue) => issue.field),
        contains('lifecycle'),
      );
    });

    test('aligns desktop scalar choices and report bounds with Postgres', () {
      final party =
          BusinessSetupValidator.validate(BusinessSetupResource.parties, const {
            'code': 'CUS-002',
            'legal_name': 'Invalid Credit Limited',
            'display_name': 'Invalid Credit',
            'kind': 'prospect',
            'credit_limit': '-1.000000',
            'credit_currency_code': 'LK',
            'payment_terms_days': 3651,
            'country_code': 'LKA',
            'status': 'active',
          });
      final product = BusinessSetupValidator.validate(
        BusinessSetupResource.products,
        const {
          'sku': 'SVC-1',
          'name': 'Service',
          'kind': 'non_stock',
          'base_unit_id': 'unit-1',
          'tracking_mode': 'batch',
          'status': 'active',
        },
      );
      final sequence = BusinessSetupValidator.validate(
        BusinessSetupResource.documentSequences,
        const {
          'document_type': 'invoice',
          'padding': 6,
          'reset_policy': 'weekly',
          'next_value': 0,
          'status': 'active',
        },
      );
      final report = BusinessSetupValidator.validate(
        BusinessSetupResource.reportDefinitions,
        const {
          'code': 'BAD-REPORT',
          'title': 'Bad report',
          'source_view': 'parties',
          'columns': [],
          'filters': [],
          'sort': {},
          'row_limit': 201,
          'status': 'active',
        },
      );

      expect(
        party.issues.map((issue) => issue.field),
        containsAll([
          'kind',
          'credit_limit',
          'credit_currency_code',
          'payment_terms_days',
          'country_code',
        ]),
      );
      expect(
        product.issues.map((issue) => issue.field),
        containsAll(['kind', 'tracking_mode']),
      );
      expect(
        sequence.issues.map((issue) => issue.field),
        containsAll(['reset_policy', 'next_value']),
      );
      expect(
        report.issues.map((issue) => issue.field),
        containsAll(['columns', 'filters', 'sort', 'row_limit']),
      );
    });

    test('validates revisions, account currencies, and approval currency', () {
      final account = BusinessSetupValidator.validate(
        BusinessSetupResource.accounts,
        const {
          'code': '1000',
          'name': 'Cash',
          'account_type': 'asset',
          'normal_balance': 'debit',
          'currency_code': 'RUPEES',
          'status': 'active',
        },
      );
      final workflow = BusinessSetupValidator.validate(
        BusinessSetupResource.workflowDefinitions,
        {
          ..._validPayload(BusinessSetupResource.workflowDefinitions),
          'revision': 0,
        },
      );
      final approval = BusinessSetupValidator.validate(
        BusinessSetupResource.approvalMatrixSteps,
        const {
          'workflow_definition_id': 'workflow-1',
          'role_id': 'role-1',
          'step_order': 101,
          'minimum_amount': '10.000000',
          'maximum_amount': '20.000000',
          'currency_code': 'LK',
          'status': 'active',
        },
      );

      expect(
        account.issues.map((issue) => issue.field),
        contains('currency_code'),
      );
      expect(workflow.issues.map((issue) => issue.field), contains('revision'));
      expect(
        approval.issues.map((issue) => issue.field),
        containsAll(['step_order', 'currency_code']),
      );
    });

    test('allows draft status only for workflow definitions', () {
      final workflow = BusinessSetupValidator.validate(
        BusinessSetupResource.workflowDefinitions,
        _validPayload(BusinessSetupResource.workflowDefinitions),
      );
      final party = BusinessSetupValidator.validate(
        BusinessSetupResource.parties,
        {..._validPayload(BusinessSetupResource.parties), 'status': 'draft'},
      );
      final readOnly = BusinessSetupValidator.validate(
        BusinessSetupResource.notifications,
        const {'status': 'unsupported'},
      );

      expect(workflow.isValid, isTrue);
      expect(party.issues.map((issue) => issue.field), contains('status'));
      expect(readOnly.isValid, isTrue);
    });
  });

  group('Setup record and query normalization — FR-240 / NFR-202', () {
    test('parses numeric versions, dates, fallbacks, and extension fields', () {
      final fromNumber =
          SetupRecord.fromJson(BusinessSetupResource.parties, <String, Object?>{
            'id': 'party-1',
            'tenant_id': 'tenant-1',
            'legal_entity_id': null,
            'code': 'C001',
            'version': 4.9,
            'created_at': DateTime.utc(2026, 9, 3),
            'updated_at': 'invalid',
            'credit_limit': '1000.000000',
          });
      final fromString = SetupRecord.fromJson(
        BusinessSetupResource.parties,
        const {
          'id': 'party-2',
          'tenant_id': 'tenant-1',
          'code': 'C002',
          'version': '7',
        },
      );
      final fallback = SetupRecord.fromJson(
        BusinessSetupResource.parties,
        const {'id': 'party-3', 'version': 'invalid'},
      );

      expect(fromNumber.version, 4);
      expect(fromNumber.name, 'C001');
      expect(fromNumber.createdAt, DateTime.utc(2026, 9, 3));
      expect(
        fromNumber.updatedAt,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
      expect(fromNumber.fields, {'credit_limit': '1000.000000'});
      expect(fromNumber.toJson()['credit_limit'], '1000.000000');
      expect(fromString.version, 7);
      expect(fallback.version, 1);
      expect(fallback.tenantId, isEmpty);
      expect(fallback.status, 'active');
    });

    test('retains cursor, filter, and ordering options', () {
      final query = SetupListQuery(
        search: '  tea  ',
        status: 'inactive',
        cursor: 'cursor-2',
        sort: const ['-updated_at', 'id'],
      );

      expect(query.normalizedSearch, 'tea');
      expect(query.status, 'inactive');
      expect(query.cursor, 'cursor-2');
      expect(query.sort, ['-updated_at', 'id']);
      expect(() => SetupListQuery(limit: 0), throwsArgumentError);
    });
  });
}

Map<String, Object?> _validPayload(BusinessSetupResource resource) =>
    switch (resource) {
      BusinessSetupResource.warehouses => const {
        'code': 'ACPT-WH',
        'name': 'Acceptance warehouse',
        'branch_id': '579aab50-3856-4ace-a214-0d73a224a6ba',
        'status': 'active',
      },
      BusinessSetupResource.currencies => const {},
      BusinessSetupResource.exchangeRates => const {
        'source_currency_code': 'USD',
        'target_currency_code': 'LKR',
        'rate': '312.1234567891',
        'effective_date': '2026-09-03',
        'rate_type': 'spot',
        'source': 'manual',
        'status': 'active',
      },
      BusinessSetupResource.taxDefinitions => const {
        'code': 'VAT18',
        'name': 'VAT 18%',
        'rate': '18.000000',
        'kind': 'output',
        'valid_from': '2026-01-01',
        'valid_to': '2026-12-31',
        'status': 'active',
      },
      BusinessSetupResource.accounts => const {
        'code': '1000',
        'name': 'Cash',
        'account_type': 'asset',
        'normal_balance': 'debit',
        'status': 'active',
      },
      BusinessSetupResource.fiscalPeriods => const {
        'name': 'FY 2026',
        'start_date': '2026-01-01',
        'end_date': '2026-12-31',
        'state': 'open',
        'status': 'active',
      },
      BusinessSetupResource.parties => const {
        'code': 'CUS-001',
        'legal_name': 'Acme Private Limited',
        'display_name': 'Acme',
        'kind': 'customer',
        'status': 'active',
      },
      BusinessSetupResource.contacts => const {
        'party_id': 'party-1',
        'name': 'Nimal',
        'status': 'active',
      },
      BusinessSetupResource.units => const {
        'code': 'EA',
        'name': 'Each',
        'symbol': 'ea',
        'category': 'quantity',
        'precision': '0',
        'status': 'active',
      },
      BusinessSetupResource.products => const {
        'sku': 'TEA-001',
        'name': 'Ceylon tea',
        'kind': 'stocked',
        'base_unit_id': 'unit-1',
        'tracking_mode': 'none',
        'status': 'active',
      },
      BusinessSetupResource.documentSequences => const {
        'document_type': 'sales_invoice',
        'reset_policy': 'yearly',
        'padding': 6,
        'status': 'active',
      },
      BusinessSetupResource.workflowDefinitions => {
        'document_type': 'sales_invoice',
        'name': 'Sales invoice lifecycle',
        'lifecycle': {
          'states': DocumentStatus.values.map((value) => value.name).toList(),
          'transitions': const [
            ['draft', 'submitted'],
            ['submitted', 'approved'],
            ['approved', 'posted'],
            ['posted', 'settled'],
            ['settled', 'closed'],
          ],
        },
        'status': 'draft',
      },
      BusinessSetupResource.approvalMatrixSteps => const {
        'workflow_definition_id': 'workflow-1',
        'role_id': 'role-1',
        'step_order': 1,
        'minimum_amount': '0.000000',
        'maximum_amount': '1000.000000',
        'currency_code': 'LKR',
        'status': 'active',
      },
      BusinessSetupResource.attachments => const {
        'aggregate_type': 'party',
        'aggregate_id': 'party-1',
        'file_name': 'registration.pdf',
        'mime_type': 'application/pdf',
        'byte_size': 1024,
        'status': 'active',
      },
      BusinessSetupResource.notifications ||
      BusinessSetupResource.importJobs ||
      BusinessSetupResource.exportJobs => const {},
      BusinessSetupResource.reportDefinitions => const {
        'code': 'PARTY_LIST',
        'title': 'Party list',
        'source_view': 'parties',
        'columns': ['code', 'display_name'],
        'status': 'active',
      },
    };
