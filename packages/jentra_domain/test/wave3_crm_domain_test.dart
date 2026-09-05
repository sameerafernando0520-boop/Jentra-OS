import 'package:jentra_domain/jentra_domain.dart';
import 'package:test/test.dart';

void main() {
  group('Wave 3 CRM read contracts — FR-313..FR-318 / NFR-302', () {
    test('parses an opportunity without crossing binary floating point', () {
      final entry = CrmPipelineEntry.fromJson({
        'entry_type': 'opportunity',
        'id': 'opportunity-1',
        'tenant_id': 'tenant-1',
        'legal_entity_id': 'entity-1',
        'branch_id': 'branch-1',
        'code': 'OPP-001',
        'name': 'Ceylon Retail rollout',
        'owner_id': 'user-1',
        'stage': 'submitted',
        'status': 'open',
        'probability': '37.50',
        'expected_value': '1200000.125000',
        'weighted_value': '450000.046875',
        'currency_code': 'LKR',
        'expected_close_date': '2026-10-31',
        'stage_entered_at': '2026-09-04T04:30:00Z',
        'created_at': '2026-09-01T03:00:00Z',
        'last_activity_at': '2026-09-04T05:00:00Z',
      });

      expect(entry.entryType, CrmEntryType.opportunity);
      expect(entry.probability?.toDecimalString(), '37.50');
      expect(entry.expectedValue.toDecimalString(), '1200000.125000');
      expect(entry.weightedValue?.toDecimalString(), '450000.046875');
      expect(entry.expectedValue.currencyCode, 'LKR');
      expect(entry.expectedCloseDate, DateTime.utc(2026, 10, 31));
      expect(entry.lastActivityAt, DateTime.utc(2026, 9, 4, 5));
    });

    test(
      'parses a lead with intentionally absent probability and weighting',
      () {
        final entry = CrmPipelineEntry.fromJson({
          'entry_type': 'lead',
          'id': 'lead-1',
          'tenant_id': 'tenant-1',
          'legal_entity_id': 'entity-1',
          'branch_id': null,
          'code': 'LEAD-001',
          'name': 'Prospective distributor',
          'owner_id': 'user-1',
          'stage': 'draft',
          'status': 'active',
          'probability': null,
          'expected_value': '8250.000000',
          'weighted_value': null,
          'currency_code': 'USD',
          'expected_close_date': '2026-11-15',
          'stage_entered_at': '2026-09-04T04:30:00+00:00',
          'created_at': '2026-09-04T04:30:00+00:00',
          'last_activity_at': null,
        });

        expect(entry.entryType, CrmEntryType.lead);
        expect(entry.probability, isNull);
        expect(entry.weightedValue, isNull);
        expect(entry.branchId, isNull);
        expect(entry.hasActivity, isFalse);
      },
    );

    test('rejects malformed numeric and entry-type boundaries', () {
      final valid = _pipelineEntryJson();

      expect(
        () => CrmPipelineEntry.fromJson({...valid, 'probability': 40.0}),
        throwsFormatException,
      );
      expect(
        () => CrmPipelineEntry.fromJson({...valid, 'entry_type': 'quote'}),
        throwsFormatException,
      );
    });

    test(
      'keeps pipeline totals separated by currency and explicit as-of date',
      () {
        final summary = CrmPipelineSummary.fromJson({
          'as_of_date': '2026-09-05',
          'currency_totals': [
            {
              'currency_code': 'LKR',
              'opportunity_count': 2,
              'expected_value': '1500.100000',
              'weighted_value': '950.200000',
            },
            {
              'currency_code': 'USD',
              'opportunity_count': 1,
              'expected_value': '500.000000',
              'weighted_value': '125.000000',
            },
          ],
          'stage_totals': [
            {
              'stage': 'submitted',
              'currency_code': 'LKR',
              'opportunity_count': 2,
              'expected_value': '1500.100000',
              'weighted_value': '950.200000',
            },
          ],
          'forecast_totals': [
            {
              'forecast_bucket': 'pipeline',
              'currency_code': 'LKR',
              'opportunity_count': 2,
              'expected_value': '1500.100000',
              'weighted_value': '950.200000',
            },
          ],
          'conversion': {
            'total_leads': 4,
            'converted_leads': 1,
            'conversion_rate': '25.000000',
          },
          'win_loss': {'won': 3, 'lost': 1, 'decided': 4},
          'activity_recency': {
            'activity_count': 7,
            'latest_activity_at': '2026-09-05T06:15:00Z',
          },
          'aging': {
            'age_basis': 'created_at',
            'stale_after_days': 90,
            'open_opportunity_count': 3,
            'average_age_days': '12.666667',
            'oldest_age_days': 31,
            'stale_opportunity_count': 0,
          },
        });

        expect(summary.asOfDate, DateTime.utc(2026, 9, 5));
        expect(summary.currencyTotals, hasLength(2));
        expect(
          summary.currencyTotalFor('LKR')?.weightedValue.toDecimalString(),
          '950.200000',
        );
        expect(
          summary.currencyTotalFor('USD')?.expectedValue.toDecimalString(),
          '500.000000',
        );
        expect(summary.conversion.rate.toDecimalString(), '25.000000');
        expect(summary.aging.averageAgeDays.toDecimalString(), '12.666667');
        expect(
          summary.activityRecency.latestActivityAt,
          DateTime.utc(2026, 9, 5, 6, 15),
        );
      },
    );

    test('normalizes and bounds stable pipeline queries', () {
      final query = CrmPipelineQuery(
        search: '  Acme%_  ',
        entryType: CrmEntryType.opportunity,
        stage: 'submitted',
        status: 'open',
        closingFrom: DateTime.utc(2026, 9, 1),
        closingTo: DateTime.utc(2026, 12, 31),
        cursor: 'opaque-cursor',
        limit: 50,
      );

      expect(query.normalizedSearch, 'Acme%_');
      expect(query.limit, 50);
      expect(query.hasFilters, isTrue);
      expect(() => CrmPipelineQuery(limit: 0), throwsArgumentError);
      expect(() => CrmPipelineQuery(limit: 201), throwsArgumentError);
      expect(
        () => CrmPipelineQuery(
          closingFrom: DateTime.utc(2026, 12, 1),
          closingTo: DateTime.utc(2026, 11, 1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('Wave 3 CRM mutation inputs — AC-302 / AC-322', () {
    test('lead draft validates required fields and emits exact values', () {
      final draft = CrmLeadDraft(
        code: 'lead-001',
        leadType: 'organization',
        name: 'Acme Trading',
        source: 'referral',
        ownerId: 'user-1',
        stage: 'draft',
        expectedValue: Money.parse('1000.100000', 'LKR'),
        expectedCloseDate: DateTime.utc(2026, 12, 31),
        qualificationData: const {},
      );

      expect(draft.validate().isValid, isTrue);
      expect(draft.toJson(), containsPair('code', 'LEAD-001'));
      expect(draft.toJson(), containsPair('expected_value', '1000.100000'));
      expect(draft.toJson(), containsPair('currency_code', 'LKR'));
      expect(draft.toJson(), containsPair('expected_close_date', '2026-12-31'));

      final invalid = CrmLeadDraft(
        code: 'x',
        leadType: 'unknown',
        name: '',
        source: '',
        ownerId: '',
        stage: 'approved',
        expectedValue: Money.zero('LKR'),
        expectedCloseDate: DateTime.utc(2026, 12, 31),
        qualificationData: const {},
      ).validate();
      expect(invalid.isValid, isFalse);
      expect(
        invalid.issues.map((issue) => issue.field),
        containsAll([
          'code',
          'lead_type',
          'name',
          'source',
          'owner_id',
          'qualification_data',
        ]),
      );
    });

    test('opportunity draft enforces probability and won/lost reasons', () {
      final valid = CrmOpportunityDraft(
        code: 'opp-001',
        prospectName: 'Acme Trading',
        ownerId: 'user-1',
        stage: 'submitted',
        probability: ExactDecimal.parse('62.50', scale: 2),
        expectedValue: Money.parse('1200.125000', 'USD'),
        expectedCloseDate: DateTime.utc(2026, 10, 31),
        forecastBucket: 'best_case',
        status: 'open',
      );

      expect(valid.validate().isValid, isTrue);
      expect(valid.toJson(), containsPair('probability', '62.50'));
      expect(valid.toJson(), containsPair('expected_value', '1200.125000'));

      final invalid = CrmOpportunityDraft(
        code: 'OPP-002',
        prospectName: 'Lost prospect',
        ownerId: 'user-1',
        stage: 'closed',
        probability: ExactDecimal.parse('100.01', scale: 2),
        expectedValue: Money.zero('USD'),
        expectedCloseDate: DateTime.utc(2026, 10, 31),
        forecastBucket: 'closed',
        status: 'lost',
      ).validate();
      expect(
        invalid.issues.map((issue) => issue.field),
        containsAll(['probability', 'won_loss_reason']),
      );
    });

    test('completed activity requires coherent time and outcome', () {
      final activity = CrmActivityDraft(
        aggregateType: CrmAggregateType.lead,
        aggregateId: 'lead-1',
        activityType: 'call',
        subject: 'Qualification call',
        ownerId: 'user-1',
        activityAt: DateTime.utc(2026, 9, 5, 9),
        dueAt: DateTime.utc(2026, 9, 5, 8),
        status: 'completed',
      );

      final validation = activity.validate();
      expect(validation.isValid, isFalse);
      expect(
        validation.issues.map((issue) => issue.field),
        containsAll(['due_at', 'completed_at', 'outcome']),
      );
    });

    test('conversion input preserves selected links and exact probability', () {
      final conversion = CrmLeadConversionDraft(
        leadId: 'lead-1',
        partyId: 'party-1',
        contactId: 'contact-1',
        opportunityCode: 'opp-001',
        probability: ExactDecimal.parse('55.00', scale: 2),
        nextAction: 'Prepare a scoped proposal',
        conversionReason: 'Qualification completed',
      );

      expect(conversion.validate().isValid, isTrue);
      expect(conversion.toJson(), containsPair('opportunity_code', 'OPP-001'));
      expect(
        conversion.toJson(),
        containsPair('opportunity_probability', '55.00'),
      );
      expect(conversion.toJson(), containsPair('party_id', 'party-1'));
    });
  });
}

Map<String, Object?> _pipelineEntryJson() => {
  'entry_type': 'opportunity',
  'id': 'opportunity-1',
  'tenant_id': 'tenant-1',
  'legal_entity_id': 'entity-1',
  'branch_id': 'branch-1',
  'code': 'OPP-001',
  'name': 'Acme',
  'owner_id': 'user-1',
  'stage': 'submitted',
  'status': 'open',
  'probability': '40.00',
  'expected_value': '1000.000000',
  'weighted_value': '400.000000',
  'currency_code': 'LKR',
  'expected_close_date': '2026-12-31',
  'stage_entered_at': '2026-09-04T04:30:00Z',
  'created_at': '2026-09-01T03:00:00Z',
  'last_activity_at': null,
};
