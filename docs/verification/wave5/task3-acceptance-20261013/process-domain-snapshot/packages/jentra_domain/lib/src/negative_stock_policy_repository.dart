import 'commands.dart';
import 'negative_stock_policy.dart';
import 'tenant_context.dart';

abstract interface class NegativeStockPolicyRepository {
  Future<NegativeStockPolicy> readPolicy(TenantContext scope);
  Future<NegativeStockEvidencePage> evidence(
    TenantContext scope,
    NegativeStockEvidenceKind kind, {
    BigInt? after,
  });
  Future<CommandResult<NegativeStockPolicy>> configure(
    CommandEnvelope<Map<String, Object?>> command,
  );
}
