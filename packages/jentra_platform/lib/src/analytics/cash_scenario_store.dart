import 'dart:convert';
import 'package:jentra_domain/analytics.dart';
import '../draft_repository.dart';

final class CashScenarioStore {
  CashScenarioStore(this.drafts, this.authorize);
  final EncryptedDraftRepository drafts;
  final Future<void> Function(ProcessMetricScope, String) authorize;
  String _key(ProcessMetricScope s, String actor, {bool pending = false}) {
    ProcessMetricScope(tenantId: actor, legalEntityId: actor);
    return 'w5:cash-scenario:${pending ? 'pending:' : ''}${base64Url.encode(utf8.encode(jsonEncode([actor, s.tenantId, s.legalEntityId, s.branchId])))}';
  }

  Future<void> save(
    String actor,
    CashScenarioRevision revision, {
    bool pending = false,
  }) async {
    await authorize(revision.scope, actor);
    final payload = revision.toJson();
    if (utf8.encode(jsonEncode(payload)).length > 8388608) {
      throw const FormatException('Scenario draft limit exceeded.');
    }
    await drafts.save(
      id: _key(revision.scope, actor, pending: pending),
      tenantId: revision.scope.tenantId,
      entityType: pending
          ? 'analytics_cash_scenario_command'
          : 'analytics_cash_scenario',
      payload: payload,
      localVersion: 1,
    );
  }

  Future<CashScenarioRevision?> restore(
    ProcessMetricScope scope,
    String actor, {
    bool pending = false,
  }) async {
    await authorize(scope, actor);
    final value = await drafts.find(_key(scope, actor, pending: pending));
    await authorize(scope, actor);
    if (value == null) return null;
    if (value.tenantId != scope.tenantId ||
        value.entityType !=
            (pending
                ? 'analytics_cash_scenario_command'
                : 'analytics_cash_scenario')) {
      throw const FormatException('Saved scenario scope mismatch.');
    }
    return CashScenarioRevision.fromJson(scope, value.payload);
  }

  Future<void> removePending(ProcessMetricScope scope, String actor) async {
    await authorize(scope, actor);
    await drafts.delete(_key(scope, actor, pending: true));
  }
}
