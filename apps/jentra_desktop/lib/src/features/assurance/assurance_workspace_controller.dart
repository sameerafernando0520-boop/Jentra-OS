import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_assurance.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_assurance_platform.dart';
import 'package:jentra_platform/jentra_platform.dart';

import '../../app_providers.dart';

final assuranceGatewayProvider = Provider<AssuranceGateway?>((ref) => null);
final assuranceWorkspaceControllerProvider =
    Provider.autoDispose<AssuranceWorkspaceController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider),
          gateway = ref.watch(assuranceGatewayProvider),
          caps = ref.watch(businessCapabilitiesProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          caps.isLoading ||
          caps.hasError ||
          !(caps.value?.contains(AssuranceWorkspaceController.viewCapability) ??
              false)) {
        return null;
      }
      final c = AssuranceWorkspaceController(
        scope: scope,
        gateway: gateway,
        drafts: QuotationDraftStore(
          ref.watch(encryptedDraftRepositoryProvider),
        ),
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
        canRespond:
            caps.value?.contains(
              AssuranceWorkspaceController.respondCapability,
            ) ??
            false,
      );
      ref.listen(
        connectivityStateProvider,
        (_, s) => c.setOnline(s.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      unawaited(c.initialize());
      return c;
    });

/// Governance & Audit workspace: the caller's work queue with reminder and
/// escalation levels, the engagement register, read-only engagement detail and
/// the finding owner's management response. The response is a sealed,
/// encrypted request: an uncertain outcome is retried with the same key.
final class AssuranceWorkspaceController extends ChangeNotifier {
  AssuranceWorkspaceController({
    required this.scope,
    required this.gateway,
    required this.drafts,
    required this.online,
    this.canRespond = false,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const slot = 'assurance-finding-response';
  static const viewCapability = 'assurance.evidence.view';
  static const respondCapability = 'assurance.response.manage';

  final TenantContext scope;
  final AssuranceGateway gateway;
  final QuotationDraftStore drafts;
  final bool canRespond;
  final DateTime Function() _clock;

  bool online, busy = false, verified = false, accessDenied = false;
  bool _disposed = false;
  int _epoch = 0;
  String section = 'work';
  String? error, message, cursor;
  AssuranceOverview? overview;
  List<AssuranceEngagementSummary> engagements = [];
  Map<String, Object?>? detail;
  Map<String, Object?> form = {};
  QuotationLocalDraft? local;

  bool get pending => local?.pending != null;
  bool get responding => form['finding_id'] is String;
  bool get conflicted => local?.errorCode == 'VERSION_CONFLICT';
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
    overview = null;
    engagements = [];
    cursor = null;
    detail = null;
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

  void _deny(Object e) {
    if (e is DomainError &&
        const {
          'PERMISSION_DENIED',
          'MFA_REQUIRED',
          'AUTHENTICATION_REQUIRED',
        }.contains(e.code)) {
      _epoch++;
      verified = false;
      accessDenied = true;
      _clear();
    }
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
      _deny(e);
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

  String _today() => _clock().toUtc().toIso8601String().substring(0, 10);

  /// Loads the encrypted response draft, then rechecks authority before any
  /// audit data is shown.
  Future<void> initialize() => _run(() async {
    final epoch = _epoch;
    local = await drafts.load(scope, slot);
    if (_disposed) return;
    form = local?.form ?? {};
    if (!online) return;
    final o = await gateway.overview(scope);
    if (_disposed || !online || epoch != _epoch) return;
    accessDenied = false;
    verified = true;
    overview = o;
    final page = await gateway.engagements(scope);
    if (!_current(epoch)) return;
    engagements = page.items;
    cursor = page.nextCursor;
  });

  Future<void> refresh() => initialize();

  Future<void> moreEngagements() => _run(() async {
    if (!online || !verified || cursor == null) return;
    final epoch = _epoch;
    final page = await gateway.engagements(scope, after: cursor);
    if (!_current(epoch)) return;
    engagements = [...engagements, ...page.items];
    cursor = page.nextCursor;
  });

  void select(String value) {
    section = value;
    _emit();
  }

  Future<void> open(String engagementId) => _run(() async {
    if (!online || !verified) return;
    final epoch = _epoch;
    final d = await gateway.engagement(scope, engagementId);
    if (!_current(epoch)) return;
    detail = d;
    section = 'detail';
  });

  void closeDetail() {
    detail = null;
    section = 'engagements';
    _emit();
  }

  /// Starts a response to an issued finding the caller owns. A stored request
  /// that has not been resolved blocks a new response.
  Future<void> startResponse(AssuranceWorkItem item) => _run(() async {
    if (!canRespond || pending || !item.canRespond(scope.actorId)) return;
    final due = _clock().toUtc().add(const Duration(days: 30));
    form = {
      'engagement_id': item.engagementId,
      'engagement_version': item.engagementVersion,
      'engagement_name': item.engagementName,
      'finding_id': item.itemId,
      'finding_title': item.title,
      'response': '',
      'due_date': due.toIso8601String().substring(0, 10),
      'accept_risk': false,
    };
    message = null;
    await drafts.save(
      scope,
      slot,
      form,
      expectedVersion: item.engagementVersion,
      resolveConflict: true,
    );
    local = await drafts.load(scope, slot);
  });

  void field(String key, Object value) {
    if (pending || busy || !responding) return;
    form = {...form, key: value};
    _emit();
  }

  Future<void> saveResponse() => _run(() async {
    if (pending || !responding) return;
    await drafts.save(
      scope,
      slot,
      form,
      expectedVersion: form['engagement_version'] as int,
      resolveConflict: conflicted,
    );
    local = await drafts.load(scope, slot);
  });

  Future<void> discardResponse() => _run(() async {
    if (pending) return;
    await drafts.discard(scope, slot);
    local = null;
    form = {};
  });

  Map<String, Object?> _payload() => {
    'action': 'respond',
    'engagement_id': form['engagement_id'],
    'finding_id': form['finding_id'],
    'response': (form['response'] as String? ?? '').trim(),
    'due_date': form['due_date'],
    'accept_risk': form['accept_risk'] == true,
  };

  Future<void> submitResponse() => _run(() async {
    if (!online || !verified || !canRespond || !responding) return;
    if (conflicted) {
      throw const FormatException(
        'The engagement changed. Refresh and start the response again.',
      );
    }
    final epoch = _epoch;
    var request = local?.pending;
    if (request == null) {
      final version = form['engagement_version'] as int;
      final payload = _payload();
      AssuranceCommands.validate(
        'respond',
        payload,
        now: _clock(),
        tenantId: scope.tenantId,
      );
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
      await gateway.respond(request.envelope);
      // The confirmation is recorded even if the route closes meanwhile.
      await drafts.complete(scope, slot, request.envelope.commandId);
    } on DomainError catch (e) {
      await drafts.recordFailure(
        scope,
        slot,
        e,
        commandId: request.envelope.commandId,
      );
      if (!_disposed) local = await drafts.load(scope, slot);
      rethrow;
    }
    if (_disposed) return;
    local = null;
    form = {};
    message =
        'Response recorded. The finding now follows its remediation due date.';
    if (!_current(epoch)) return;
    overview = await gateway.overview(scope);
  });

  Future<bool> canLeave() async {
    if (busy) return false;
    if (accessDenied || pending || !responding) return true;
    await saveResponse();
    return error == null;
  }

  String get today => _today();
}
