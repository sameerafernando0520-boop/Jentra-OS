import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_assurance.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_assurance_platform.dart';
import 'package:jentra_platform/jentra_finance_platform.dart'
    show ReportExportFiles;
import 'package:jentra_platform/jentra_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import '../report_export/report_export_controller.dart'
    show reportExportFilesProvider;

final assuranceGatewayProvider = Provider<AssuranceGateway?>((ref) => null);
final assuranceEvidenceFilesProvider = Provider<AssuranceEvidenceFiles?>(
  (ref) => const NativeAssuranceEvidenceFiles(),
);
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
        capabilities: {...?caps.value},
        files: ref.watch(reportExportFilesProvider),
        evidenceFiles: ref.watch(assuranceEvidenceFilesProvider),
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
    this.capabilities = const {},
    this.files,
    this.evidenceFiles,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const slot = 'assurance-finding-response';
  static const commandSlot = 'assurance-auditor-command';
  static const viewCapability = 'assurance.evidence.view';
  static const respondCapability = 'assurance.response.manage';
  static const submitCapability = 'assurance.evidence.submit';
  static const evidenceSlot = 'assurance-evidence-upload';
  static const _uuid = Uuid();

  /// Ids the client generates for each auditor action, sealed with the draft
  /// so a retry reuses them.
  static const _generated = {
    'request_evidence': ['request_id'],
    'collect_system_evidence': ['evidence_id'],
    'record_exception': ['exception_id'],
    'issue_finding': ['finding_id'],
    'export_pack': ['export_id'],
    'design_test': ['procedure_id'],
    'execute_test': ['run_id'],
    'issue_report': ['report_id'],
    'retest': ['retest_id'],
  };

  /// Form fields entered as text but sent as whole numbers.
  static const _wholeNumbers = {
    'population_size',
    'sample_start',
    'items_tested',
    'exceptions_found',
  };

  final TenantContext scope;
  final AssuranceGateway gateway;
  final QuotationDraftStore drafts;
  final bool canRespond;
  final Set<String> capabilities;
  final ReportExportFiles? files;
  final AssuranceEvidenceFiles? evidenceFiles;
  final DateTime Function() _clock;

  AuditorEngagementView? view;
  Map<String, Object?> commandForm = {};
  QuotationLocalDraft? command;
  AuditPackVerification? pack;
  StoredEvidenceVerification? lastVerification;

  bool get commandPending => command?.pending != null;
  bool get commanding => commandForm['action'] is String;
  bool get commandConflicted => command?.errorCode == 'VERSION_CONFLICT';
  AuditorAction? get commandAction =>
      commanding ? AuditorAction.of(commandForm['action']! as String) : null;

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
    view = null;
    pack = null;
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
          : e is _Held
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
    command = await drafts.load(scope, commandSlot);
    if (_disposed) return;
    commandForm = command?.form ?? {};
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
    final (d, v) = await _load(engagementId);
    if (!_current(epoch)) return;
    detail = d;
    view = v;
    if (pack?.pack.engagementId != v.id) pack = null;
    section = 'detail';
  });

  /// Engagement detail and its test procedures, validated together.
  Future<(Map<String, Object?>, AuditorEngagementView)> _load(String id) async {
    final d = await gateway.engagement(scope, id);
    final tests = await gateway.tests(scope, id);
    return (d, AuditorEngagementView.fromJson(d, tests: tests));
  }

  void closeDetail() {
    detail = null;
    view = null;
    pack = null;
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

  /// Starts an auditor command on the open engagement. [prefill] carries the
  /// target ids and defaults; generated ids are sealed with the draft.
  Future<void> startCommand(String action, Map<String, Object?> prefill) =>
      _run(() async {
        final v = view, a = AuditorAction.of(action);
        if (v == null ||
            !verified ||
            commandPending ||
            !capabilities.contains(a.capability)) {
          return;
        }
        commandForm = {
          'action': action,
          'engagement_id': v.id,
          'engagement_version': v.version,
          for (final k in _generated[action] ?? const <String>[]) k: _uuid.v4(),
          ...prefill,
        };
        message = null;
        await drafts.save(
          scope,
          commandSlot,
          commandForm,
          expectedVersion: v.version,
          resolveConflict: true,
        );
        command = await drafts.load(scope, commandSlot);
      });

  void commandField(String key, Object value) {
    if (commandPending || busy || !commanding) return;
    commandForm = {...commandForm, key: value};
    _emit();
  }

  Future<void> saveCommand() => _run(() async {
    if (commandPending || !commanding) return;
    await drafts.save(
      scope,
      commandSlot,
      commandForm,
      expectedVersion: commandForm['engagement_version'] as int,
      resolveConflict: commandConflicted,
    );
    command = await drafts.load(scope, commandSlot);
  });

  Future<void> discardCommand() => _run(() async {
    if (commandPending) return;
    await drafts.discard(scope, commandSlot);
    command = null;
    commandForm = {};
  });

  Map<String, Object?> _commandPayload(AuditorAction a) => {
    for (final k in a.fields)
      if (commandForm.containsKey(k))
        k: switch (commandForm[k]) {
          final String s when _wholeNumbers.contains(k) =>
            int.tryParse(s.trim()) ?? s.trim(),
          final String s => s.trim(),
          final other => other,
        },
  };

  Future<void> submitCommand() => _run(() async {
    final a = commandAction;
    if (!online || !verified || a == null) return;
    if (!capabilities.contains(a.capability)) return;
    if (commandConflicted) {
      throw const FormatException(
        'The engagement changed. Refresh it and start again.',
      );
    }
    final epoch = _epoch;
    var request = command?.pending;
    if (request == null) {
      final version = commandForm['engagement_version'] as int;
      final payload = _commandPayload(a);
      a.validate(
        payload,
        now: _clock(),
        tenantId: scope.tenantId,
        sampleSize: view?.tests
            .where((x) => x.id == payload['procedure_id'])
            .firstOrNull
            ?.sampleSize,
      );
      await drafts.save(
        scope,
        commandSlot,
        commandForm,
        expectedVersion: version,
      );
      request = await drafts.prepare(
        scope,
        commandSlot,
        verb: 'submit',
        payload: payload,
        expectedVersion: version,
      );
      command = await drafts.load(scope, commandSlot);
    }
    if (!_current(epoch)) return;
    try {
      await gateway.auditorCommand(request.envelope);
      await drafts.complete(scope, commandSlot, request.envelope.commandId);
    } on DomainError catch (e) {
      await drafts.recordFailure(
        scope,
        commandSlot,
        e,
        commandId: request.envelope.commandId,
      );
      if (!_disposed) command = await drafts.load(scope, commandSlot);
      // MFA keeps the sealed request for an identical retry; it does not
      // withdraw workspace access.
      if (e.code == 'MFA_REQUIRED') throw _Held(e.message);
      rethrow;
    }
    if (_disposed) return;
    final payload = request.envelope.payload;
    command = null;
    commandForm = {};
    message = '${a.label} recorded.';
    if (!_current(epoch)) return;
    if (a.action == 'export_pack') {
      pack = await gateway.auditPack(scope, payload['export_id']! as String);
      if (!_current(epoch)) return;
      message = pack!.verified
          ? 'Audit pack exported and verified against its recorded digest.'
          : 'The downloaded audit pack does not match its recorded digest. Do not use it.';
    }
    final (d, v) = await _load(payload['engagement_id']! as String);
    if (!_current(epoch)) return;
    detail = d;
    view = v;
  });

  /// The request owner uploads a file for an open evidence request. The
  /// `submit_evidence` command is sealed before anything is sent, so a retry
  /// with the same file resumes the same submission; the server then hashes
  /// the stored bytes and only `verified` evidence can be accepted.
  Future<void> submitEvidence(AssuranceWorkItem item) => _run(() async {
    final f = evidenceFiles;
    if (f == null ||
        !online ||
        !verified ||
        !capabilities.contains(submitCapability) ||
        !item.canSubmitEvidence(scope.actorId)) {
      return;
    }
    final epoch = _epoch;
    final picked = await f.choose();
    if (picked == null || !_current(epoch)) return;
    var request = (await drafts.load(scope, evidenceSlot))?.pending;
    if (request != null) {
      final saved = request.envelope.payload;
      if (saved['request_id'] != item.itemId) {
        throw const _Held(
          'Finish the saved evidence upload for another request first.',
        );
      }
      if (saved['sha256'] != picked.sha256 ||
          saved['byte_size'] != picked.bytes.length) {
        throw const FormatException(
          'Choose the same file as the saved submission to finish it.',
        );
      }
    } else {
      final now = _clock();
      final evidenceId = _uuid.v4();
      final payload = manualEvidencePayload(
        tenantId: scope.tenantId,
        engagementId: item.engagementId,
        requestId: item.itemId,
        evidenceId: evidenceId,
        fileName: picked.name,
        sha256: picked.sha256,
        byteSize: picked.bytes.length,
        sourceAsOf: now,
        now: now,
      );
      await drafts.save(
        scope,
        evidenceSlot,
        {'request_id': item.itemId, 'evidence_id': evidenceId},
        expectedVersion: item.engagementVersion,
        resolveConflict: true,
      );
      request = await drafts.prepare(
        scope,
        evidenceSlot,
        verb: 'submit',
        payload: payload,
        expectedVersion: item.engagementVersion,
      );
    }
    if (!_current(epoch)) return;
    final StoredEvidenceVerification v;
    try {
      v = await gateway.submitManualEvidence(
        request.envelope,
        picked.bytes,
        picked.mime,
      );
      await drafts.complete(scope, evidenceSlot, request.envelope.commandId);
    } on DomainError catch (e) {
      await drafts.recordFailure(
        scope,
        evidenceSlot,
        e,
        commandId: request.envelope.commandId,
      );
      rethrow;
    }
    if (_disposed) return;
    lastVerification = v;
    message = v.verified
        ? 'Evidence stored and verified (SHA-256 ${v.observedSha256.substring(0, 12)}…).'
        : 'The stored file does not match the submitted digest. An auditor must reject it before you upload again.';
    if (!_current(epoch)) return;
    overview = await gateway.overview(scope);
  });

  /// Saves only a pack whose bytes hashed to the recorded digest.
  Future<void> savePack() => _run(() async {
    final p = pack, f = files;
    if (p == null || !p.verified || f == null) return;
    final path = await f.choose('audit-pack-${p.pack.exportId}.json');
    if (path == null) return;
    await f.write(path, p.bytes, 'application/json');
    message = 'Saved verified audit pack ${p.computedSha256}.';
  });

  Future<bool> canLeave() async {
    if (busy) return false;
    if (accessDenied) return true;
    if (responding && !pending) await saveResponse();
    if (error == null && commanding && !commandPending) await saveCommand();
    return error == null;
  }

  String get today => _today();
}

final class _Held implements Exception {
  const _Held(this.message);
  final String message;
}
