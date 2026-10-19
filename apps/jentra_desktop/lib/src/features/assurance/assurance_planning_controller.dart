import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_assurance.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_assurance_platform.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import 'assurance_workspace_controller.dart' show assuranceGatewayProvider;

final assurancePlanningControllerProvider =
    Provider.autoDispose<AssurancePlanningController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider),
          gateway = ref.watch(assuranceGatewayProvider),
          caps = ref.watch(businessCapabilitiesProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          caps.isLoading ||
          caps.hasError ||
          !AssurancePlanningController.canView(caps.value ?? const {})) {
        return null;
      }
      final c = AssurancePlanningController(
        scope: scope,
        gateway: gateway,
        drafts: QuotationDraftStore(
          ref.watch(encryptedDraftRepositoryProvider),
        ),
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
        capabilities: {...?caps.value},
      );
      ref.listen(
        connectivityStateProvider,
        (_, s) => c.setOnline(s.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      unawaited(c.initialize());
      return c;
    });

/// Audit planning: the audit universe with risk assessments, the plan
/// register, maker-checker plan approval and instantiation of approved
/// occurrences as engagements. Every change is an encrypted draft sealed with
/// generated ids and the aggregate version, retried with the same key on an
/// uncertain outcome.
final class AssurancePlanningController extends ChangeNotifier {
  AssurancePlanningController({
    required this.scope,
    required this.gateway,
    required this.drafts,
    required this.online,
    this.capabilities = const {},
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const slot = 'assurance-plan-command';
  static const _uuid = Uuid();

  /// Planning is read by planning managers or anyone who may view evidence,
  /// as `api.assurance_universe` and `api.assurance_plan` allow.
  static bool canView(Set<String> caps) =>
      caps.contains('assurance.plan.manage') ||
      caps.contains('assurance.evidence.view');

  static const _generated = {
    'register_item': ['item_id'],
    'assess_risk': ['assessment_id'],
    'create_plan': ['plan_id'],
    'supersede_plan': ['plan_id'],
    'add_plan_item': ['plan_item_id'],
    'instantiate_engagement': ['engagement_id'],
  };
  static const _wholeNumbers = {'likelihood', 'impact', 'occurrence'};

  final TenantContext scope;
  final AssuranceGateway gateway;
  final QuotationDraftStore drafts;
  final Set<String> capabilities;
  final DateTime Function() _clock;

  bool online, busy = false, verified = false, accessDenied = false;
  bool _disposed = false;
  int _epoch = 0;
  String section = 'universe';
  String? error, message, cursor;
  AssuranceUniverse? universe;
  List<PlanSummary> plans = [];
  AssurancePlanDetail? plan;
  Map<String, Object?> form = {};
  QuotationLocalDraft? local;

  bool get pending => local?.pending != null;
  bool get commanding => form['action'] is String;
  bool get conflicted => local?.errorCode == 'VERSION_CONFLICT';
  String get actorId => scope.actorId;
  bool _current(int epoch) =>
      !_disposed && online && epoch == _epoch && !accessDenied;

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _epoch++;
    _disposed = true;
    super.dispose();
  }

  void _clear() {
    universe = null;
    plans = [];
    cursor = null;
    plan = null;
  }

  void setOnline(bool value) {
    online = value;
    if (!value) {
      _epoch++;
      verified = false;
      _clear();
    }
    _emit();
  }

  Future<void> _run(Future<void> Function() work) async {
    if (busy || _disposed) return;
    final epoch = _epoch;
    busy = true;
    error = null;
    _emit();
    try {
      await work();
    } catch (e) {
      if (_disposed || !online || epoch != _epoch) return;
      if (e is DomainError &&
          const {
            'PERMISSION_DENIED',
            'AUTHENTICATION_REQUIRED',
          }.contains(e.code)) {
        _epoch++;
        verified = false;
        accessDenied = true;
        _clear();
      }
      error = e is DomainError
          ? e.message
          : e is FormatException
          ? e.message
          : 'Unable to complete this action. Saved requests are retained.';
    } finally {
      busy = false;
      _emit();
    }
  }

  String get today => _clock().toUtc().toIso8601String().substring(0, 10);

  Future<void> initialize() => _run(() async {
    final epoch = _epoch;
    local = await drafts.load(scope, slot);
    if (_disposed) return;
    form = local?.form ?? {};
    if (!online) return;
    final u = await gateway.universe(scope);
    if (_disposed || !online || epoch != _epoch) return;
    accessDenied = false;
    verified = true;
    universe = u;
    final page = await gateway.plans(scope);
    if (!_current(epoch)) return;
    plans = page.items;
    cursor = page.nextCursor;
    final open = plan;
    if (open != null) {
      final p = await gateway.plan(scope, open.id);
      if (!_current(epoch)) return;
      plan = p;
    }
  });

  Future<void> refresh() => initialize();

  Future<void> morePlans() => _run(() async {
    if (!online || !verified || cursor == null) return;
    final epoch = _epoch;
    final page = await gateway.plans(scope, after: cursor);
    if (!_current(epoch)) return;
    plans = [...plans, ...page.items];
    cursor = page.nextCursor;
  });

  void select(String value) {
    section = value;
    _emit();
  }

  Future<void> openPlan(String id) => _run(() async {
    if (!online || !verified) return;
    final epoch = _epoch;
    final p = await gateway.plan(scope, id);
    if (!_current(epoch)) return;
    plan = p;
    section = 'plan';
  });

  void closePlan() {
    plan = null;
    section = 'plans';
    _emit();
  }

  /// The version a command is checked against: 0 to create, otherwise the
  /// universe item's or the open plan's current version.
  int? _expectedVersion(String action, Map<String, Object?> prefill) {
    if (AssurancePlanCommands.creates(action)) return 0;
    if (action == 'assess_risk' || action == 'retire_item') {
      return universe?.items
          .where((i) => i.id == prefill['item_id'])
          .firstOrNull
          ?.version;
    }
    return plan?.version;
  }

  Future<void> startCommand(String action, Map<String, Object?> prefill) =>
      _run(() async {
        if (!verified ||
            pending ||
            !capabilities.contains(AssurancePlanCommands.capability(action))) {
          return;
        }
        final version = _expectedVersion(action, prefill);
        if (version == null) return;
        form = {
          'action': action,
          'expected_version': version,
          if (plan != null && !AssurancePlanCommands.creates(action))
            'plan_id': plan!.id,
          for (final k in _generated[action] ?? const <String>[]) k: _uuid.v4(),
          ...prefill,
        };
        message = null;
        await drafts.save(
          scope,
          slot,
          form,
          expectedVersion: version,
          resolveConflict: true,
        );
        local = await drafts.load(scope, slot);
      });

  void field(String key, Object? value) {
    if (pending || busy || !commanding) return;
    form = {...form, key: value};
    _emit();
  }

  Future<void> saveDraft() => _run(() async {
    if (pending || !commanding) return;
    await drafts.save(
      scope,
      slot,
      form,
      expectedVersion: form['expected_version'] as int,
      resolveConflict: conflicted,
    );
    local = await drafts.load(scope, slot);
  });

  Future<void> discardDraft() => _run(() async {
    if (pending) return;
    await drafts.discard(scope, slot);
    local = null;
    form = {};
  });

  Map<String, Object?> _payload(String action) => {
    for (final k in AssurancePlanCommands.fields(action))
      if (form.containsKey(k))
        k: switch (form[k]) {
          final String s when _wholeNumbers.contains(k) =>
            int.tryParse(s.trim()) ?? s.trim(),
          final String s when k == 'template_id' && s.trim().isEmpty => null,
          final String s => s.trim(),
          final other => other,
        },
  };

  Future<void> submit() => _run(() async {
    final action = form['action'] as String?;
    if (!online || !verified || action == null) return;
    if (!capabilities.contains(AssurancePlanCommands.capability(action))) {
      return;
    }
    if (conflicted) {
      throw const FormatException('This changed. Refresh and start again.');
    }
    final epoch = _epoch;
    var request = local?.pending;
    if (request == null) {
      final version = form['expected_version'] as int;
      final payload = _payload(action);
      AssurancePlanCommands.validate(action, payload);
      await drafts.save(scope, slot, form, expectedVersion: version);
      request = await drafts.prepare(
        scope,
        slot,
        verb: 'submit',
        payload: payload,
        expectedVersion: version,
      );
      local = await drafts.load(scope, slot);
    }
    if (!_current(epoch)) return;
    try {
      await gateway.planCommand(request.envelope);
      await drafts.complete(scope, slot, request.envelope.commandId);
    } on DomainError catch (e) {
      await drafts.recordFailure(
        scope,
        slot,
        e,
        commandId: request.envelope.commandId,
      );
      // MFA and uncertain outcomes keep the sealed request for an identical
      // retry; only permission or authentication loss clears planning data.
      if (!_disposed) local = await drafts.load(scope, slot);
      rethrow;
    }
    if (_disposed) return;
    final payload = request.envelope.payload;
    local = null;
    form = {};
    message = switch (action) {
      'instantiate_engagement' =>
        'Engagement created from the plan. Open it from Governance & Audit.',
      'supersede_plan' => 'Revision created as a draft. The approved plan stays in force until the revision is approved.',
      _ => 'Recorded.',
    };
    if (!_current(epoch)) return;
    universe = await gateway.universe(scope);
    final page = await gateway.plans(scope);
    if (!_current(epoch)) return;
    plans = page.items;
    cursor = page.nextCursor;
    final id = payload['plan_id'] as String?;
    if (id != null &&
        (plan?.id == id ||
            action == 'create_plan' ||
            action == 'supersede_plan')) {
      final p = await gateway.plan(scope, id);
      if (!_current(epoch)) return;
      plan = p;
      section = 'plan';
    }
  });

  Future<bool> canLeave() async {
    if (busy) return false;
    if (accessDenied || pending || !commanding) return true;
    await saveDraft();
    return error == null;
  }
}
