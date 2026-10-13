import 'business_setup.dart';
import 'commands.dart';
import 'pagination.dart';
import 'tabular_document.dart';
import 'tenant_context.dart';

abstract interface class BusinessSetupRepository {
  Future<CursorPage<SetupRecord>> list(
    BusinessSetupResource resource, {
    required TenantContext context,
    SetupListQuery? query,
  });

  Future<SetupRecord?> findById(
    BusinessSetupResource resource, {
    required TenantContext context,
    required String id,
  });

  Future<CommandResult<SetupRecord>> upsert(
    BusinessSetupResource resource, {
    required TenantContext context,
    required Map<String, Object?> payload,
    required String idempotencyKey,
    int? expectedVersion,
  });
}

abstract interface class SetupImportExportRepository {
  Future<CommandResult<SetupRecord>> importRecords({
    required BusinessSetupResource resource,
    required TenantContext context,
    required String format,
    required String fileName,
    required int fileSize,
    required TabularDocument document,
    required String idempotencyKey,
  });

  Future<CommandResult<SetupRecord>> recordExport({
    required BusinessSetupResource resource,
    required TenantContext context,
    required String format,
    required String fileName,
    required int fileSize,
    required int rowCount,
    required List<String> columns,
    required Map<String, Object?> filters,
    required String idempotencyKey,
  });
}
