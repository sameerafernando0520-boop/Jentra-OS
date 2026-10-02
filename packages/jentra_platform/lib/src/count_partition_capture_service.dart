import 'package:jentra_domain/count_partitions.dart';
import 'count_partition_gateway.dart';
import 'quotation_draft_store.dart';

/// Uses the existing AES-GCM draft repository and immutable pending envelope.
/// The slot persists the capture request and its identity, never posted totals.
final class CountPartitionCaptureService {
  CountPartitionCaptureService({
    required this.scope,
    required this.gateway,
    required this.drafts,
  });
  static const slot = 'stock-count-partition-capture';
  final TenantContext scope;
  final CountPartitionGateway gateway;
  final QuotationDraftStore drafts;

  Future<QuotationLocalDraft?> restore() => drafts.load(scope, slot);
  Future<void> saveDraft(Map<String, Object?> form) =>
      drafts.save(scope, slot, countPartitionCapturePayload(form));
  Future<void> discardDraft() => drafts.discard(scope, slot);
  Future<CountPartitionProgress> capture() async {
    final local = await restore();
    if (local == null) {
      throw const FormatException('Save a partition capture request first.');
    }
    if (local.form['confirmed_group_id'] is String) {
      return gateway.page(scope, local.form['confirmed_group_id'] as String);
    }
    final pending =
        local.pending ??
        await drafts.prepare(
          scope,
          slot,
          verb: 'save',
          payload: countPartitionCapturePayload(local.form),
        );
    CountPartitionProgress progress;
    try {
      progress = await gateway.capture(pending.envelope);
    } on DomainError catch (e) {
      await drafts.recordFailure(
        scope,
        slot,
        e,
        commandId: pending.envelope.commandId,
      );
      rethrow;
    } catch (_) {
      const error = DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Capture could not be confirmed. Retry the saved request.',
      );
      await drafts.recordFailure(
        scope,
        slot,
        error,
        commandId: pending.envelope.commandId,
      );
      throw error;
    }
    // One encrypted write replaces the sealed command only after receipt checks.
    // If this write fails, the original exact envelope remains available to replay.
    await drafts.confirm(
      scope,
      slot,
      pending.envelope.commandId,
      form: {'confirmed_group_id': progress.id},
    );
    return progress;
  }
}
