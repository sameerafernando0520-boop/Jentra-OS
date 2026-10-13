import 'commands.dart';
import 'lead_to_cash.dart';
import 'tenant_context.dart';

abstract interface class LeadToCashRepository {
  Future<List<SalesQuotation>> listQuotations({required TenantContext context});

  Future<SalesQuotation?> findQuotation({
    required TenantContext context,
    required String id,
  });

  Future<List<SalesOrder>> listSalesOrders({required TenantContext context});

  Future<SalesOrder?> findSalesOrder({
    required TenantContext context,
    required String id,
  });

  Future<CommandResult<SalesQuotation>> upsertQuotation(
    CommandEnvelope<QuotationDraft> command,
  );

  Future<CommandResult<SalesQuotation>> transitionQuotation(
    CommandEnvelope<OperationalDocumentTransition> command,
  );

  Future<CommandResult<SalesQuotation>> decideQuotationApproval(
    CommandEnvelope<OperationalApprovalDecision> command,
  );

  Future<CommandResult<SalesOrder>> convertQuotation(
    CommandEnvelope<QuotationConversionDraft> command,
  );

  Future<CommandResult<SalesOrder>> upsertSalesOrder(
    CommandEnvelope<SalesOrderDraft> command,
  );

  Future<CommandResult<SalesOrder>> transitionSalesOrder(
    CommandEnvelope<OperationalDocumentTransition> command,
  );

  Future<CommandResult<SalesOrder>> reserveStock(
    CommandEnvelope<StockReservationDraft> command,
  );
}
