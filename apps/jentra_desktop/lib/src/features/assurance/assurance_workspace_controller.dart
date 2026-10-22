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
import 'assurance_people_provider.dart';
import 'reminder_scan_log.dart';

export 'reminder_scan_log.dart';
import '../report_export/report_export_controller.dart'
    show reportExportFilesProvider;

final assuranceGatewayProvider = Provider<AssuranceGateway?>((ref) => null);
final assuranceReminderGatewayProvider = Provider<AssuranceReminderGateway?>(
  (ref) => null,
);
final assuranceEvidenceDownloadGatewayProvider =
    Provider<AssuranceEvidenceDownloadGateway?>((ref) => null);
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
        downloads: ref.watch(assuranceEvidenceDownloadGatewayProvider),
        reminders: ref.watch(assuranceReminderGatewayProvider),
        scanLog: ref.watch(reminderScanLogProvider),
        people: ref.watch(assurancePeopleGatewayProvider),
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
    this.downloads,
    this.reminders,
    this.scanLog,
    AssurancePeopleGateway? people,
    DateTime Function()? clock,
  }) : _peopleGateway = people,
       _clock = clock ?? DateTime.now;

  /// Reminder delivery is for engagement managers (A10).
  static const remindCapability = 'assurance.engagement.manage';

  /// Pages of 100 items; a scope larger than this is finished next time.
  static const _maxReminderPages = 20;

  static String scopeKey(TenantContext s) =>
      '${s.tenantId}:${s.legalEntityId}:${s.branchId}';

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
    'map_control': ['control_id'],
    'place_hold': ['hold_id'],
    'carry_forward': ['finding_id', 'exception_id'],
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
  final AssuranceEvidenceDownloadGateway? downloads;
  final AssuranceReminderGateway? reminders;
  final ReminderScanLog? scanLog;
  final AssurancePeopleGateway? _peopleGateway;
  final DateTime Function() _clock;

  AssurancePeople? people;
  String? peopleError;

  String personLabel(String userId) =>
      people?.labelOf(userId) ??
      'Member ····${userId.substring(userId.length - 4)}';

  /// The installed detail API exposes membership events, not a team roster.
  /// Keep this labelled as history; roles and expiry are not inferred.
  List<AssuranceEvent> get membershipEvents => [
    for (final row in detail?['events'] as List? ?? const [])
      if (row is Map &&
          const {
            'add_team_member',
            'revoke_team_member',
          }.contains(row['action']))
        AssuranceEvent.fromJson(row.cast<String, Object?>()),
  ];

  Set<String> get _everTeamIds => {
    ?view?.leadAuditorId,
    for (final event in membershipEvents) event.aggregateId,
  };

  List<AssurancePerson> setupChoices(String action) {
    final members = people?.members ?? const <AssurancePerson>[];
    final v = view;
    if (v == null) return const [];
    final owners = {
      for (final control in v.controls) control.ownerId,
      for (final request in v.requests) request.ownerId,
    };
    if (action == 'map_control') {
      return members.where((p) => !_everTeamIds.contains(p.userId)).toList();
    }
    if (action == 'add_team_member') {
      return members
          .where(
            (p) =>
                !owners.contains(p.userId) && !_everTeamIds.contains(p.userId),
          )
          .toList();
    }
    final membership = <String, bool>{};
    for (final event in membershipEvents) {
      membership[event.aggregateId] = event.action == 'add_team_member';
    }
    return members
        .where(
          (p) => p.userId != v.leadAuditorId && membership[p.userId] == true,
        )
        .toList();
  }

  bool sendingReminders = false;
  List<AssuranceEvent> get activeHolds {
    final holds = <String, AssuranceEvent>{};
    for (final row in detail?['events'] as List? ?? const []) {
      if (row is! Map) continue;
      if (row['action'] == 'place_hold') {
        final event = AssuranceEvent.fromJson(row.cast<String, Object?>());
        holds[event.aggregateId] = event;
      } else if (row['action'] == 'release_hold') {
        holds.remove(row['aggregate_id']);
      }
    }
    return holds.values.toList();
  }

  AuditorEngagementView? carrySource;
  String? carrySourceName;

  List<AssuranceEngagementSummary> get carrySources => engagements
      .where(
        (e) =>
            e.id != view?.id &&
            const {
              EngagementStatus.issued,
              EngagementStatus.archived,
            }.contains(e.status),
      )
      .toList();

  List<AuditorFinding> get carryFindings =>
      (carrySource?.findings ?? const <AuditorFinding>[])
          .where(
            (f) =>
                f.status != FindingStatus.closed &&
                f.status != FindingStatus.riskAccepted &&
                !_everTeamIds.contains(f.ownerId),
          )
          .toList();

  Future<void> loadCarrySource(String id) => _run(() async {
    if (!verified ||
        !online ||
        commandPending ||
        commandForm['action'] != 'carry_forward' ||
        !carrySources.any((e) => e.id == id)) {
      return;
    }
    final epoch = _epoch;
    final data = await gateway.engagement(scope, id);
    final source = AuditorEngagementView.fromJson(data);
    if (!_current(epoch) || commandForm['action'] != 'carry_forward') return;
    if (!const {
      EngagementStatus.issued,
      EngagementStatus.archived,
    }.contains(source.status)) {
      throw const FormatException(
        'Choose an issued or archived source engagement.',
      );
    }
    carrySource = source;
    carrySourceName = (data['engagement'] as Map)['name'] as String;
    commandForm = {
      ...commandForm,
      'source_engagement_id': id,
      'source_finding_id': '',
    };
  });

  Future<void> startRemediation(AssuranceWorkItem item) async {
    if (busy ||
        !verified ||
        !online ||
        item.kind != 'finding' ||
        item.status != 'remediating' ||
        item.ownerId != scope.actorId ||
        !capabilities.contains('assurance.remediation.manage')) {
      return;
    }
    await open(item.engagementId);
    if (!verified || view?.id != item.engagementId) return;
    final finding = view!.findings
        .where((f) => f.id == item.itemId)
        .firstOrNull;
    if (finding == null ||
        !view!.canSubmitRemediation(capabilities, finding, scope.actorId)) {
      return;
    }
    await startCommand('submit_remediation', {
      'finding_id': finding.id,
      'evidence_sha256': '',
      'note': '',
      'label': finding.title,
    });
  }

  Future<void> chooseCommandWorkpaper(String digestField) => _run(() async {
    if (!verified ||
        !online ||
        commandPending ||
        !commanding ||
        evidenceFiles == null ||
        !const {'evidence_sha256', 'workpaper_sha256'}.contains(digestField) ||
        !commandAction!.fields.contains(digestField)) {
      return;
    }
    final epoch = _epoch;
    final picked = await evidenceFiles!.choose();
    if (picked == null || !_current(epoch)) return;
    commandForm = {
      ...commandForm,
      digestField: picked.sha256,
      '${digestField}_file_name': picked.name,
      // Recreate only the field changed by the picker. Manual typing keeps
      // its editor and selection while this programmatic value is displayed.
      '${digestField}_editor_revision': _uuid.v4(),
    };
  });
  String? reminderMessage, reminderError;

  bool get canSendReminders =>
      reminders != null && capabilities.contains(remindCapability);

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
    people = null;
    peopleError = null;
    carrySource = null;
    carrySourceName = null;
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
    await _restoreCarryForward(epoch);
    if (!_current(epoch)) return;
    if (capabilities.contains('assurance.engagement.manage')) {
      final directory = _peopleGateway;
      try {
        final found = await directory?.people(scope);
        if (!_current(epoch)) return;
        people = found;
        peopleError = found == null
            ? 'The member list is unavailable. Refresh before changing controls or team access.'
            : null;
      } catch (_) {
        if (!_current(epoch)) return;
        people = null;
        peopleError = 'The member list could not be loaded. Refresh to choose people by name.';
      }
    }
    // A lead's first visit of the day reminds the scope; it never blocks the
    // queue and a failure is shown, not retried.
    final log = scanLog;
    if (canSendReminders &&
        log != null &&
        await log.lastScan(scopeKey(scope)) != _today()) {
      await _remind(epoch);
    }
    final link = _pendingLink;
    if (link != null && _current(epoch)) {
      _pendingLink = null;
      await _open(link);
    }
  });

  Future<void> refresh() => initialize();

  /// A saved carry-forward draft needs its verified target controls and source
  /// findings before it can be edited again. Loading this context must never
  /// rewrite the saved form or the payload of an uncertain command.
  Future<void> _restoreCarryForward(int epoch) async {
    if (commandForm['action'] != 'carry_forward') return;
    carrySource = null;
    carrySourceName = null;
    final targetId = commandForm['engagement_id'];
    if (targetId is! String) return;
    final (targetDetail, targetView) = await _load(targetId);
    if (!_current(epoch) || commandForm['engagement_id'] != targetId) return;
    detail = targetDetail;
    view = targetView;
    final sourceId = commandForm['source_engagement_id'];
    if (sourceId is! String || sourceId.isEmpty || sourceId == targetId) return;
    final sourceDetail = await gateway.engagement(scope, sourceId);
    final source = AuditorEngagementView.fromJson(sourceDetail);
    if (!_current(epoch) || commandForm['source_engagement_id'] != sourceId) {
      return;
    }
    if (!const {
      EngagementStatus.issued,
      EngagementStatus.archived,
    }.contains(source.status)) {
      throw const FormatException(
        'The saved source engagement is no longer issued or archived. Choose another source.',
      );
    }
    carrySource = source;
    carrySourceName = (sourceDetail['engagement'] as Map)['name'] as String;
  }

  /// Sends reminders for every due-soon, overdue and escalated item in scope.
  Future<void> sendReminders() async {
    if (!canSendReminders || sendingReminders || !online || !verified) return;
    await _remind(_epoch);
    _emit();
  }

  Future<void> _remind(int epoch) async {
    final gateway = reminders;
    if (gateway == null || _disposed) return;
    sendingReminders = true;
    reminderError = null;
    _emit();
    try {
      var sent = 0;
      String? after;
      for (var page = 0; page < _maxReminderPages; page++) {
        final r = await gateway.scan(scope, _uuid.v4(), after: after);
        if (!_current(epoch)) return;
        sent += r.emitted;
        if (!r.hasMore) break;
        after = r.nextAfter;
      }
      reminderMessage = switch (sent) {
        0 => 'Everyone is already reminded.',
        1 => 'Sent 1 reminder.',
        _ => 'Sent $sent reminders.',
      };
      await scanLog?.record(scopeKey(scope), _today());
    } catch (e) {
      reminderError = e is DomainError
          ? 'Reminders were not sent: ${e.message}'
          : 'Reminders were not sent. Try again from the workspace.';
    } finally {
      sendingReminders = false;
    }
  }

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

  Future<void> open(String engagementId) => _run(() => _open(engagementId));

  Future<void> _open(String engagementId) async {
    if (!online || !verified) return;
    final epoch = _epoch;
    final (d, v) = await _load(engagementId);
    if (!_current(epoch)) return;
    detail = d;
    view = v;
    if (pack?.pack.engagementId != v.id) pack = null;
    section = 'detail';
  }

  String? _linked, _pendingLink;

  /// Opens an engagement named in a link (a reminder notice) once access is
  /// verified; the same link opens only once.
  void openWhenReady(String engagementId) {
    if (_linked == engagementId) return;
    _linked = engagementId;
    if (verified && !busy) {
      unawaited(open(engagementId));
    } else {
      _pendingLink = engagementId;
    }
  }

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
  Future<void> startCommand(
    String action,
    Map<String, Object?> prefill,
  ) => _run(() async {
    final v = view, a = AuditorAction.of(action);
    if (v == null ||
        !verified ||
        commandPending ||
        !capabilities.contains(a.capability)) {
      return;
    }
    if ((action == 'map_control' && !v.canMapControl(capabilities)) ||
        (action == 'add_team_member' && !v.canAddTeamMember(capabilities)) ||
        (action == 'revoke_team_member' &&
            !v.canRevokeTeamMember(capabilities))) {
      return;
    }
    if (action == 'submit_remediation') {
      final finding = v.findings
          .where((f) => f.id == prefill['finding_id'])
          .firstOrNull;
      if (finding == null ||
          !v.canSubmitRemediation(capabilities, finding, scope.actorId)) {
        return;
      }
    }
    if (action == 'cancel_request' || action == 'run_monitoring') {
      final request = v.requests
          .where(
            (r) => action == 'cancel_request'
                ? r.id == prefill['request_id']
                : r.evidenceId == prefill['evidence_id'] &&
                      r.controlId == prefill['control_id'],
          )
          .firstOrNull;
      if (request == null ||
          (action == 'cancel_request'
              ? !v.canCancelRequest(capabilities, request)
              : !v.canRunMonitoring(capabilities, request))) {
        return;
      }
    }
    if (action == 'carry_forward' && !v.canCarryForward(capabilities)) return;
    if (action == 'release_hold' &&
        !activeHolds.any(
          (h) =>
              h.aggregateId == prefill['hold_id'] && h.actorId != scope.actorId,
        )) {
      return;
    }
    commandForm = {
      'action': action,
      'engagement_id': v.id,
      'engagement_version': v.version,
      for (final k in _generated[action] ?? const <String>[]) k: _uuid.v4(),
      ...prefill,
    };
    carrySource = null;
    carrySourceName = null;
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
    if (commandForm['action'] == 'add_team_member' && key == 'role') {
      commandForm.remove('expires_at');
      if (value == 'external') {
        commandForm['expires_at'] = _clock()
            .toUtc()
            .add(const Duration(days: 30))
            .toIso8601String()
            .substring(0, 10);
      }
    }
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
          final String s
              when a.action == 'add_team_member' && k == 'expires_at' =>
            '${s.trim()}T00:00:00Z',
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
      if (a.action == 'carry_forward' &&
          !carryFindings.any(
            (finding) => finding.id == payload['source_finding_id'],
          )) {
        throw const FormatException(
          'Choose an open finding from the selected source engagement.',
        );
      }
      if (a.action == 'release_hold' &&
          !activeHolds.any(
            (hold) =>
                hold.aggregateId == payload['hold_id'] &&
                hold.actorId != scope.actorId,
          )) {
        throw const FormatException(
          'A retention hold must be released by someone other than the person who placed it.',
        );
      }
      if (const {
        'map_control',
        'add_team_member',
        'revoke_team_member',
      }.contains(a.action)) {
        final key = a.action == 'map_control' ? 'owner_id' : 'user_id';
        if (!setupChoices(a.action).any((p) => p.userId == payload[key])) {
          throw const FormatException(
            'Choose an eligible person from the current member list. Refresh if membership has changed.',
          );
        }
      }
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
    if (const {'submit_remediation', 'cancel_request'}.contains(a.action)) {
      final updated = await gateway.overview(scope);
      if (!_current(epoch)) return;
      overview = updated;
    }
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

  /// Asks the server to hash a submitted upload again (request owner or
  /// audit team) and reports what the stored bytes contain.
  Future<void> verifyStoredEvidence(AuditorRequest r) => _run(() async {
    final v = view, id = r.evidenceId;
    if (!online || !verified || v == null || id == null) return;
    if (!v.canVerifyStored(capabilities, r, scope.actorId)) return;
    final epoch = _epoch;
    final result = await gateway.verifyEvidence(scope, v.id, id);
    if (!_current(epoch)) return;
    lastVerification = result;
    message = result.verified
        ? 'Stored file verified (SHA-256 ${result.observedSha256.substring(0, 12)}…). It can now be accepted.'
        : 'The stored file does not match its submitted digest. Return it for rework so the owner can upload it again.';
  });

  /// Downloads verified evidence and saves it only when its bytes hash, on
  /// this device, to the recorded digest the reviewer saw.
  Future<void> downloadEvidence(AuditorRequest r) => _run(() async {
    final d = downloads, f = files, v = view, id = r.evidenceId;
    if (d == null || f == null || !online || !verified || v == null) return;
    if (id == null || !v.canDownload(capabilities, r)) return;
    final epoch = _epoch;
    final name = assuranceEvidenceFileName(r.fileName ?? '', id);
    final path = await f.choose(name);
    if (path == null || !_current(epoch)) return;
    final file = await d.download(
      scope,
      v.id,
      id,
      expectedSha256: r.evidenceSha256,
    );
    if (!_current(epoch)) return;
    await f.write(path, file.bytes, 'application/octet-stream');
    message =
        'Saved $name. It matches the recorded SHA-256 ${file.sha256.substring(0, 12)}….';
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
