import 'dart:convert';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/jentra_domain.dart' show DomainError;
import '../draft_repository.dart';

/// Filters only. No process rows, totals, digests, credentials or authorizations.
final class ProcessFilterStore {
  ProcessFilterStore(this.drafts, this.authorize);
  final EncryptedDraftRepository drafts;
  final Future<void> Function(ProcessMetricScope, String) authorize;
  String _key(ProcessMetricScope s, String actor) {
    if (!RegExp(
      r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$',
    ).hasMatch(actor)) {
      throw const FormatException('Invalid actor.');
    }
    return 'w5:process-filter:${base64Url.encode(utf8.encode(jsonEncode([actor, s.tenantId, s.legalEntityId, s.branchId])))}';
  }

  Future<void> save(
    ProcessMetricScope scope,
    String actor,
    ProcessMetricFilter filter,
  ) async {
    final key = _key(scope, actor);
    await authorize(scope, actor);
    await drafts.save(
      id: key,
      tenantId: scope.tenantId,
      entityType: 'analytics_process_filter',
      payload: filter.toJson(),
      localVersion: 1,
    );
  }

  Future<ProcessMetricFilter?> restore(
    ProcessMetricScope scope,
    String actor,
  ) async {
    final key = _key(scope, actor);
    await authorize(scope, actor); // Online actor authority before decryption.
    final found = await drafts.find(key);
    await authorize(scope, actor); // Actor may change while storage is awaited.
    if (found == null) return null;
    if (found.tenantId != scope.tenantId ||
        found.entityType != 'analytics_process_filter') {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Saved filter context changed.',
      );
    }
    return ProcessMetricFilter.fromJson(found.payload);
  }
}
