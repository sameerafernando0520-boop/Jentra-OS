import 'package:test/test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'wave3_quotation_workspace_test.dart' show input;

CrmLeadDraft lead([Map<String, Object?> p = const {}]) => CrmLeadDraft(
  code: p['code'] as String? ?? 'LEAD-001',
  leadType: p['lead_type'] as String? ?? 'organization',
  name: p['name'] as String? ?? 'Customer prospect',
  source: p['source'] as String? ?? 'Referral',
  ownerId: p['owner'] as String? ?? 'owner',
  stage: p['stage'] as String? ?? 'draft',
  expectedValue: Money.parse(
    p['amount'] as String? ?? '9007199254.740993',
    'LKR',
  ),
  expectedCloseDate: DateTime.utc(2026, 10, 1),
  id: p['id'] as String?,
  contactName: p['contact_name'] as String?,
  email: p['email'] as String?,
  phone: p['phone'] as String?,
  partyId: p['party'] as String?,
  contactId: p['contact'] as String?,
  qualificationData: (p['qualification'] as Map<String, Object?>?) ?? {},
  lossReason: p['loss_reason'] as String?,
  transitionReason: p['transition_reason'] as String?,
  status: p['status'] as String? ?? 'active',
);
CrmOpportunityDraft opportunity([Map<String, Object?> p = const {}]) =>
    CrmOpportunityDraft(
      code: p['code'] as String? ?? 'OPP-001',
      ownerId: p['owner'] as String? ?? 'owner',
      stage: p['stage'] as String? ?? 'draft',
      probability: ExactDecimal.parse(
        p['probability'] as String? ?? '50',
        scale: 2,
      ),
      expectedValue: Money.parse(p['amount'] as String? ?? '1000', 'LKR'),
      expectedCloseDate: DateTime.utc(2026, 10, 1),
      forecastBucket: p['bucket'] as String? ?? 'pipeline',
      status: p['status'] as String? ?? 'open',
      id: p['id'] as String?,
      sourceLeadId: p['source'] as String?,
      partyId: p['party'] as String?,
      contactId: p['contact'] as String?,
      prospectName: p.containsKey('prospect')
          ? p['prospect'] as String?
          : 'Prospective buyer',
      nextAction: p['next'] as String?,
      wonLossReason: p['reason'] as String?,
      transitionReason: p['transition'] as String?,
    );
CrmActivityDraft activity([Map<String, Object?> p = const {}]) =>
    CrmActivityDraft(
      aggregateType: CrmAggregateType.lead,
      aggregateId: p['aggregate'] as String? ?? 'lead',
      activityType: p['type'] as String? ?? 'call',
      subject: p['subject'] as String? ?? 'Customer call',
      ownerId: p['owner'] as String? ?? 'owner',
      activityAt: DateTime.utc(2026, 9, 29),
      status: p['status'] as String? ?? 'planned',
      id: p['id'] as String?,
      dueAt: p['due'] as DateTime?,
      completedAt: p['completed'] as DateTime?,
      outcome: p['outcome'] as String?,
      notes: p['notes'] as String?,
    );

void main() {
  test(
    'CRM lifecycle validation distinguishes required data, qualification, loss and exact exposure',
    () {
      expect(lead().validate().isValid, true);
      for (final p in <Map<String, Object?>>[
        {'code': '!'},
        {'lead_type': 'invented'},
        {'name': 'x'},
        {'name': 'x' * 181},
        {'source': ''},
        {'source': 'x' * 101},
        {'owner': ''},
        {'stage': 'unknown'},
        {'stage': 'submitted'},
        {'id': 'id', 'stage': 'approved'},
        {'id': 'id', 'stage': 'rejected'},
        {'contact': 'contact'},
        {'email': 'invalid'},
        {'amount': '-1'},
        {'status': 'retired'},
      ]) {
        expect(lead(p).validate().isValid, false, reason: p.toString());
      }
      final valid = lead({
        'id': 'id',
        'stage': 'approved',
        'qualification': <String, Object?>{'need': 'Paper'},
        'contact_name': '  Customer  ',
        'email': 'a@example.test',
        'phone': '123',
        'party': 'party',
        'contact': 'contact',
        'loss_reason': 'Lost to competitor',
        'transition_reason': 'Qualified',
      });
      expect(valid.validate().isValid, true);
      expect(valid.toJson()['contact_name'], 'Customer');
      expect(
        lead({
          'id': 'id',
          'stage': 'cancelled',
          'loss_reason': 'Withdrawn',
        }).validate().isValid,
        true,
      );
      expect(
        lead({
          'contact_name': '',
          'email': '',
          'phone': '',
          'loss_reason': '',
          'transition_reason': '',
        }).toJson().containsKey('phone'),
        false,
      );
    },
  );
  test(
    'opportunity win/loss invariants reject incomplete close decisions and preserve exact probability',
    () {
      for (final p in <Map<String, Object?>>[
        {'code': '!'},
        {'prospect': null},
        {'prospect': ''},
        {'contact': 'contact', 'prospect': ''},
        {'owner': ''},
        {'probability': '-0.01'},
        {'probability': '100.01'},
        {'amount': '-1'},
        {'bucket': 'other'},
        {'status': 'other'},
        {'status': 'won'},
        {'status': 'lost'},
        {
          'status': 'won',
          'reason': 'Won',
          'stage': 'closed',
          'probability': '99',
          'bucket': 'closed',
        },
        {
          'status': 'lost',
          'reason': 'Lost',
          'stage': 'closed',
          'probability': '1',
          'bucket': 'closed',
        },
        {
          'status': 'won',
          'reason': 'Won',
          'stage': 'closed',
          'probability': '100',
        },
        {
          'status': 'lost',
          'reason': 'Lost',
          'stage': 'closed',
          'probability': '0',
        },
        {
          'status': 'lost',
          'reason': 'Lost',
          'probability': '0',
          'bucket': 'closed',
        },
      ]) {
        expect(opportunity(p).validate().isValid, false, reason: p.toString());
      }
      for (final (status, probability) in [('won', '100'), ('lost', '0')]) {
        final draft = opportunity({
          'id': 'id',
          'source': 'lead',
          'party': 'party',
          'contact': 'contact',
          'status': status,
          'probability': probability,
          'stage': 'closed',
          'bucket': 'closed',
          'reason': 'Recorded decision',
          'next': ' Call customer ',
          'transition': ' Reviewed ',
        });
        expect(draft.validate().isValid, true);
        expect(draft.toJson()['next_action'], 'Call customer');
      }
      expect(
        opportunity({'party': 'party', 'prospect': null}).validate().isValid,
        true,
      );
      expect(
        opportunity({
          'next': '',
          'reason': '',
          'transition': '',
          'prospect': '',
        }).toJson().containsKey('next_action'),
        false,
      );
    },
  );
  test('CRM activities require accountable times and completion outcomes', () {
    for (final p in <Map<String, Object?>>[
      {'aggregate': ''},
      {'type': '!'},
      {'subject': 'x'},
      {'subject': 'x' * 181},
      {'owner': ''},
      {'due': DateTime.utc(2026, 9, 28)},
      {'status': 'other'},
      {'status': 'completed'},
      {'completed': DateTime.utc(2026, 9, 29)},
      {
        'status': 'completed',
        'completed': DateTime.utc(2026, 9, 28),
        'outcome': 'Discussed',
      },
    ]) {
      expect(activity(p).validate().isValid, false, reason: p.toString());
    }
    final draft = activity({
      'id': 'id',
      'due': DateTime.utc(2026, 9, 30),
      'status': 'completed',
      'completed': DateTime.utc(2026, 9, 29, 1),
      'outcome': ' Customer agreed ',
      'notes': ' Follow up ',
    });
    expect(draft.validate().isValid, true);
    expect(draft.toJson()['outcome'], 'Customer agreed');
    expect(
      activity({'outcome': '', 'notes': ''}).toJson().containsKey('notes'),
      false,
    );
  });
  test(
    'conversion validates selected-party context and opportunity probability boundaries',
    () {
      for (final draft in [
        CrmLeadConversionDraft(leadId: ''),
        CrmLeadConversionDraft(leadId: 'lead', contactId: 'contact'),
        CrmLeadConversionDraft(leadId: 'lead', opportunityCode: '!'),
        for (final value in ['-0.01', '100.01'])
          CrmLeadConversionDraft(
            leadId: 'lead',
            probability: ExactDecimal.parse(value, scale: 2),
          ),
      ]) {
        expect(draft.validate().isValid, false);
      }
      final draft = CrmLeadConversionDraft(
        leadId: 'lead',
        partyId: 'party',
        contactId: 'contact',
        partyCode: ' PARTY ',
        contactName: ' Person ',
        contactRole: ' Buyer ',
        opportunityCode: ' OPP-002 ',
        probability: ExactDecimal.parse('0', scale: 2),
        nextAction: ' Follow up ',
        conversionReason: ' Qualified ',
      );
      expect(draft.validate().isValid, true);
      expect(draft.toJson()['party_code'], 'PARTY');
      expect(
        CrmLeadConversionDraft(
          leadId: 'lead',
          partyCode: '',
          contactName: '',
          contactRole: '',
          opportunityCode: '',
          nextAction: '',
          conversionReason: '',
        ).toJson().containsKey('contact_name'),
        false,
      );
    },
  );
  test(
    'CRM filters restore or explicitly clear all contextual selection state',
    () {
      final all = CrmPipelineQuery(
        search: ' literal%_ ',
        entryType: CrmEntryType.lead,
        stage: 'draft',
        status: 'active',
        closingFrom: DateTime.utc(2026, 9, 1),
        closingTo: DateTime.utc(2026, 10, 1),
        cursor: 'cursor',
      );
      expect(all.copyWith().normalizedSearch, 'literal%_');
      expect(
        all
            .copyWith(
              search: '',
              clearEntryType: true,
              clearStage: true,
              clearStatus: true,
              clearClosingFrom: true,
              clearClosingTo: true,
              clearCursor: true,
            )
            .hasFilters,
        false,
      );
      for (final q in [
        CrmPipelineQuery(entryType: CrmEntryType.lead),
        CrmPipelineQuery(stage: 'draft'),
        CrmPipelineQuery(status: 'active'),
        CrmPipelineQuery(closingFrom: DateTime.utc(2026, 9, 1)),
        CrmPipelineQuery(closingTo: DateTime.utc(2026, 10, 1)),
      ]) {
        expect(q.hasFilters, true);
      }
      expect(() => CrmAggregateType.fromApi('foreign'), throwsFormatException);
      for (final value in CrmAggregateType.values) {
        expect(CrmAggregateType.fromApi(value.apiValue), value);
      }
    },
  );
  test(
    'CRM read objects reject malformed scope, exact amounts, dates and integer versions',
    () {
      final json = <String, Object?>{
        ...lead().toJson(),
        'id': 'lead',
        'tenant_id': 'tenant',
        'legal_entity_id': 'entity',
        'version': 1,
        'created_at': '2026-09-29T00:00:00Z',
        'updated_at': '2026-09-29T00:00:00Z',
      };
      for (final patch in <Map<String, Object?>>[
        {'id': ''},
        {'name': null},
        {'branch_id': 1},
        {'expected_value': 1},
        {'expected_close_date': 1},
        {'expected_close_date': 'invalid'},
        {'expected_close_date': '2026-02-30'},
        {'created_at': 1},
        {'updated_at': 'invalid'},
        {'version': 'invalid'},
        {'version': null},
      ]) {
        expect(
          () => CrmLead.fromJson({...json, ...patch}),
          throwsFormatException,
        );
      }
      for (final version in [1, '1', 1.0]) {
        expect(
          CrmLead.fromJson({
            ...json,
            'version': version,
            'branch_id': '',
            'created_at': DateTime.utc(2026, 9, 29),
          }).version,
          1,
        );
      }
      final pipeline = {
        ...json,
        'entry_type': 'lead',
        'stage_entered_at': json['created_at'],
      };
      expect(
        () => CrmPipelineEntry.fromJson({...pipeline, 'probability': 1}),
        throwsFormatException,
      );
      expect(
        () => CrmPipelineEntry.fromJson({...pipeline, 'weighted_value': 1}),
        throwsFormatException,
      );
    },
  );
  test(
    'commercial drafts revalidate exact rates, revisions, header discounts and line requirements',
    () {
      for (final patch in <Map<String, Object?>>[
        {'customer_id': ''},
        {'valid_until': '2026-01-01'},
        {'currency_code': 'lkr'},
        {'exchange_rate': '0'},
        {'payment_terms_days': -1},
        {'salesperson_id': ''},
        {'lines': []},
        {'create_revision': true},
        {'header_discount_amount': '-1'},
        {'header_discount_percent': '101'},
      ]) {
        final draft = QuotationDraftCodec.fromJson({...input(), ...patch});
        expect(draft.validate().isValid, false, reason: patch.toString());
      }
      for (final value in ['0', '-1']) {
        final quantity = CommercialQuantity(
          quantity: ExactDecimal.parse(value, scale: 6),
          unitId: '',
          baseQuantity: ExactDecimal.parse(value, scale: 6),
          conversionNumerator: BigInt.zero,
          conversionDenominator: BigInt.zero,
        );
        expect(quantity.validate().isValid, false);
      }
      for (final action in OperationalDocumentAction.values) {
        final command = OperationalDocumentTransition(
          documentType: OperationalDocumentType.salesOrder,
          documentId: 'order',
          action: action,
          reason: 'Reviewed action',
          overrideCredit: true,
          overrideReason: 'Approved exposure',
        );
        expect(command.validate().isValid, true);
        expect(command.toJson()['override_credit'], true);
      }
      expect(
        OperationalDocumentTransition(
          documentType: OperationalDocumentType.salesOrder,
          documentId: '',
          action: OperationalDocumentAction.recall,
          overrideCredit: true,
        ).validate().isValid,
        false,
      );
      for (final decision in ApprovalDecision.values) {
        final command = OperationalApprovalDecision(
          documentType: OperationalDocumentType.salesOrder,
          documentId: 'order',
          decision: decision,
          note: 'Reviewed',
        );
        expect(command.validate().isValid, true);
        expect(command.toJson()['note'], 'Reviewed');
      }
      expect(
        OperationalApprovalDecision(
          documentType: OperationalDocumentType.salesOrder,
          documentId: '',
          decision: ApprovalDecision.rejected,
        ).validate().isValid,
        false,
      );
    },
  );
}
