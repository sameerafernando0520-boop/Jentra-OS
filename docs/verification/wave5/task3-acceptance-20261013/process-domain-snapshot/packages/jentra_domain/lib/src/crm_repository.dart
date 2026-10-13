import 'commands.dart';
import 'crm.dart';
import 'pagination.dart';
import 'tenant_context.dart';

abstract interface class CrmRepository {
  Future<CursorPage<CrmPipelineEntry>> listPipeline({
    required TenantContext context,
    CrmPipelineQuery? query,
  });

  Future<List<CrmActivity>> listActivities({
    required TenantContext context,
    required CrmAggregateType aggregateType,
    required String aggregateId,
    int limit = 50,
  });

  Future<CrmLead?> findLead({
    required TenantContext context,
    required String id,
  });

  Future<CrmOpportunity?> findOpportunity({
    required TenantContext context,
    required String id,
  });

  Future<CrmPipelineSummary> getPipelineSummary({
    required TenantContext context,
    required DateTime asOfDate,
  });

  Future<CommandResult<CrmLead>> upsertLead(
    CommandEnvelope<CrmLeadDraft> command,
  );

  Future<CommandResult<CrmActivity>> recordActivity(
    CommandEnvelope<CrmActivityDraft> command,
  );

  Future<CommandResult<CrmOpportunity>> upsertOpportunity(
    CommandEnvelope<CrmOpportunityDraft> command,
  );

  Future<CommandResult<CrmLeadConversion>> convertLead(
    CommandEnvelope<CrmLeadConversionDraft> command,
  );
}
