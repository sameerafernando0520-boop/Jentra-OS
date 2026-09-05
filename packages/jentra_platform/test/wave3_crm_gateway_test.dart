import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final client = SupabaseClient(
    'http://127.0.0.1:54321',
    'test-publishable-key',
  );
  final gateway = SupabaseCrmGateway(client);

  test('CRM reads require an explicit legal-entity scope — FR-388', () async {
    const context = TenantContext(tenantId: 'tenant-1', actorId: 'user-1');

    await expectLater(
      gateway.listPipeline(context: context),
      throwsA(
        isA<DomainError>().having(
          (error) => error.code,
          'code',
          'LEGAL_ENTITY_REQUIRED',
        ),
      ),
    );
  });

  test(
    'CRM activity reads enforce the bounded child-page limit — NFR-311',
    () async {
      const context = TenantContext(
        tenantId: 'tenant-1',
        actorId: 'user-1',
        legalEntityId: 'entity-1',
      );

      await expectLater(
        gateway.listActivities(
          context: context,
          aggregateType: CrmAggregateType.lead,
          aggregateId: 'lead-1',
          limit: 501,
        ),
        throwsArgumentError,
      );
    },
  );

  test('invalid CRM commands fail locally before transport — FR-395', () async {
    const context = TenantContext(
      tenantId: 'tenant-1',
      actorId: 'user-1',
      legalEntityId: 'entity-1',
    );
    final result = await gateway.upsertLead(
      CommandEnvelope(
        commandId: 'command-1',
        idempotencyKey: 'idempotency-1',
        context: context,
        payload: CrmLeadDraft(
          code: '',
          leadType: 'unknown',
          name: '',
          source: '',
          ownerId: '',
          stage: 'draft',
          expectedValue: Money.zero('LKR'),
          expectedCloseDate: DateTime.utc(2026, 9, 30),
        ),
      ),
    );

    expect(result.isFailure, isTrue);
    expect(result.error?.code, 'VALIDATION_ERROR');
    expect(result.requestId, 'idempotency-1');
  });
}
