import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final client = SupabaseClient(
    'http://127.0.0.1:54321',
    'test-publishable-key',
  );
  final gateway = SupabaseLeadToCashGateway(client);

  test('quotation reads require legal-entity scope — FR-302', () async {
    const context = TenantContext(tenantId: 'tenant-1', actorId: 'user-1');

    await expectLater(
      gateway.listQuotations(context: context),
      throwsA(
        isA<DomainError>().having(
          (error) => error.code,
          'code',
          'LEGAL_ENTITY_REQUIRED',
        ),
      ),
    );
  });

  test('invalid quotation commands fail before transport — FR-395', () async {
    const context = TenantContext(
      tenantId: 'tenant-1',
      actorId: 'user-1',
      legalEntityId: 'entity-1',
    );
    final result = await gateway.upsertQuotation(
      CommandEnvelope(
        commandId: 'command-1',
        idempotencyKey: 'idempotency-1',
        context: context,
        payload: QuotationDraft(
          customerId: '',
          quotationDate: DateTime.utc(2026, 9, 5),
          validUntil: DateTime.utc(2026, 9, 4),
          currencyCode: 'LKR',
          exchangeRate: ExactDecimal.parse('1.0000000000', scale: 10),
          rateDate: DateTime.utc(2026, 9, 5),
          salespersonId: '',
          lines: const [],
        ),
      ),
    );

    expect(result.isFailure, isTrue);
    expect(result.error?.code, 'VALIDATION_ERROR');
    expect(
      result.error?.fieldDetails.keys,
      containsAll(['customer_id', 'valid_until', 'salesperson_id', 'lines']),
    );
  });

  test('invalid reservation commands fail before transport — FR-325', () async {
    const context = TenantContext(
      tenantId: 'tenant-1',
      actorId: 'user-1',
      legalEntityId: 'entity-1',
      branchId: 'branch-1',
    );
    final result = await gateway.reserveStock(
      CommandEnvelope(
        commandId: 'command-2',
        idempotencyKey: 'idempotency-2',
        context: context,
        payload: StockReservationDraft(
          salesOrderId: '',
          expiresAt: DateTime.utc(2026, 9, 5),
          lines: const [],
        ),
      ),
    );

    expect(result.isFailure, isTrue);
    expect(result.error?.code, 'VALIDATION_ERROR');
  });
}
