import 'dart:async';

import 'package:flutter/foundation.dart';

import 'data/employee_gateway.dart';
import 'data/employee_storage.dart';

final class EmployeeController extends ChangeNotifier {
  EmployeeController({
    required EmployeeGateway? gateway,
    required EmployeeDraftStore draftStore,
    DateTime Function()? now,
    Duration authorizationLease = const Duration(hours: 24),
  }) : _gateway = gateway,
       // Keep the injected store private while retaining the public argument.
       // ignore: prefer_initializing_formals
       _draftStore = draftStore,
       _now = now ?? DateTime.now,
       _authorizationLease = authorizationLease {
    if (authorizationLease <= Duration.zero ||
        authorizationLease > const Duration(hours: 24)) {
      throw ArgumentError.value(
        authorizationLease,
        'authorizationLease',
        'The online authorization lease must be positive and at most 24 hours.',
      );
    }
    phase = gateway == null
        ? EmployeePhase.unconfigured
        : EmployeePhase.signedOut;
    _authSubscription = gateway?.actorChanges.listen(_authChanged);
  }
  final EmployeeGateway? _gateway;
  final EmployeeDraftStore _draftStore;
  final DateTime Function() _now;
  final Duration _authorizationLease;
  Timer? _authorizationTimer;
  DateTime? _authorizedAt;
  DateTime? _authorizationExpiresAt;
  DateTime? _lastPrivateAccessAt;
  Timer? _draftRetentionTimer;
  DateTime? _draftExpiresAt;
  StreamSubscription<String?>? _authSubscription;
  int _generation = 0;
  bool _disposed = false;
  bool _foreground = true;
  int _lifecycleGeneration = 0;
  int privateRouteVersion = 0;
  bool _logoutInProgress = false;
  bool _durableLogoutIncomplete = false;
  String? _actor;
  String? _resumeWorkspaceKey;
  EmployeePendingCommand? _pending;
  EmployeePhase phase = EmployeePhase.signedOut;
  bool busy = false;
  EmployeeFailure? error;
  String? notice;
  List<EmployeeWorkspace> workspaces = const [];
  EmployeeWorkspace? workspace;
  EmployeeIdentity? identity;
  List<EmployeeLink> links = const [];
  List<EmployeeReview> reviews = const [];
  String? reviewsCursor;
  bool reviewsLoading = false;
  EmployeeFailure? reviewsError;
  EmployeeLeaveDraft? leaveDraft;
  bool get hasPendingCommand => _pending != null;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  bool _valid(int generation) {
    if (_disposed ||
        !_foreground ||
        generation != _generation ||
        _gateway?.actorId != _actor) {
      return false;
    }
    if (_authorizedAt != null && !_checkAuthorization()) return false;
    _checkDraftRetention();
    return true;
  }

  void _cancelAuthorization() {
    _authorizationTimer?.cancel();
    _authorizationTimer = null;
    _authorizedAt = null;
    _authorizationExpiresAt = null;
    _lastPrivateAccessAt = null;
  }

  void _renewAuthorization(int generation) {
    _cancelAuthorization();
    final now = _now().toUtc();
    _authorizedAt = now;
    _lastPrivateAccessAt = now;
    _authorizationExpiresAt = now.add(_authorizationLease);
    // The timer also bounds retention when the wall clock stalls or rolls back.
    _authorizationTimer = Timer(_authorizationLease, () {
      if (_valid(generation)) _expireAuthorization();
    });
  }

  void _expireAuthorization() {
    _lockForFailure(
      const EmployeeFailure(
        'AUTHORIZATION_EXPIRED',
        'Your private access lease expired or the device clock changed. Reconnect to verify your employee access.',
      ),
    );
  }

  bool _checkAuthorization() {
    final now = _now().toUtc();
    if (_authorizedAt == null ||
        _authorizationExpiresAt == null ||
        now.isBefore(_authorizedAt!) ||
        now.isBefore(_lastPrivateAccessAt!) ||
        !now.isBefore(_authorizationExpiresAt!)) {
      _expireAuthorization();
      return false;
    }
    _lastPrivateAccessAt = now;
    return true;
  }

  bool _canUsePrivateState() {
    if (_disposed ||
        !(phase == EmployeePhase.ready ||
            phase == EmployeePhase.linkRequired)) {
      return false;
    }
    if (_gateway?.actorId != _actor) {
      _lockForFailure(
        const EmployeeFailure(
          'SESSION_CHANGED',
          'Your session changed. Sign in again.',
        ),
      );
      return false;
    }
    if (!_checkAuthorization()) return false;
    _checkDraftRetention();
    return true;
  }

  static const _accessLossCodes = {
    'AUTHENTICATION_REQUIRED',
    'PERMISSION_DENIED',
    'SELF_LINK_REQUIRED',
    'SESSION_CHANGED',
  };
  void _lockForFailure(EmployeeFailure failure) {
    lock();
    if (!_disposed) {
      error = failure;
      _emit();
    }
  }

  void _cancelDraftRetention() {
    _draftRetentionTimer?.cancel();
    _draftRetentionTimer = null;
    _draftExpiresAt = null;
  }

  void _expireDraft() {
    if (_draftExpiresAt == null) return;
    _cancelDraftRetention();
    leaveDraft = null;
    privateRouteVersion++;
    notice = 'The local leave draft expired. Create a fresh draft if you still need it.';
    _emit();
  }

  void _checkDraftRetention() {
    if (_draftExpiresAt != null && !_now().toUtc().isBefore(_draftExpiresAt!)) {
      _expireDraft();
    }
  }

  void _presentDraft(EmployeeDraftLease? lease, int generation) {
    _cancelDraftRetention();
    leaveDraft = null;
    if (lease == null) return;
    final remaining = lease.expiresAt.difference(_now().toUtc());
    if (remaining <= Duration.zero) return;
    leaveDraft = lease.draft;
    _draftExpiresAt = lease.expiresAt;
    _draftRetentionTimer = Timer(remaining, () {
      if (_valid(generation)) _expireDraft();
    });
  }

  void _mask() {
    _cancelAuthorization();
    _cancelDraftRetention();
    identity = null;
    links = const [];
    reviews = const [];
    reviewsCursor = null;
    reviewsError = null;
    reviewsLoading = false;
    leaveDraft = null;
    _pending = null;
    error = null;
    notice = null;
  }

  void _authChanged(String? actor) {
    if (_disposed || actor == _actor) return;
    final wasLocked = phase == EmployeePhase.locked;
    final previousActor = _actor;
    _generation++;
    _mask();
    workspaces = const [];
    workspace = null;
    _resumeWorkspaceKey = null;
    _actor = actor;
    busy = false;
    phase =
        !_foreground ||
            wasLocked ||
            _logoutInProgress ||
            _durableLogoutIncomplete
        ? EmployeePhase.locked
        : actor == null
        ? EmployeePhase.signedOut
        : EmployeePhase.loading;
    _emit();
    final generation = _generation;
    unawaited(_afterActorChange(previousActor, actor, generation));
  }

  Future<void> _afterActorChange(
    String? previousActor,
    String? actor,
    int generation,
  ) async {
    try {
      if (previousActor != null) {
        await _draftStore.clearActorDrafts(previousActor);
      }
      if (_valid(generation) &&
          actor != null &&
          phase != EmployeePhase.locked) {
        await start();
      }
    } on Object catch (e) {
      if (_valid(generation)) {
        error = employeeFailure(e);
        phase = EmployeePhase.locked;
        _emit();
      }
    }
  }

  Future<void> start() async {
    if (_disposed || busy || !_foreground || _durableLogoutIncomplete) return;
    final gateway = _gateway;
    if (gateway == null) {
      phase = EmployeePhase.unconfigured;
      _emit();
      return;
    }
    _actor = gateway.actorId;
    if (_actor == null) {
      _mask();
      workspaces = const [];
      workspace = null;
      phase = EmployeePhase.signedOut;
      _emit();
      return;
    }
    final generation = ++_generation;
    final selected = workspace?.key ?? _resumeWorkspaceKey;
    busy = true;
    _mask();
    workspaces = const [];
    workspace = null;
    phase = EmployeePhase.loading;
    _emit();
    try {
      final choices = await gateway.listWorkspaces();
      if (!_valid(generation)) return;
      if (choices.map((w) => w.key).toSet().length != choices.length) {
        throw const EmployeeFailure(
          'INVALID_RESPONSE',
          'The workspace response is inconsistent.',
        );
      }
      workspaces = List.unmodifiable(choices);
      final previous = choices.where((w) => w.key == selected).firstOrNull;
      final value = previous ?? (choices.length == 1 ? choices.single : null);
      if (value == null) {
        phase = EmployeePhase.chooseWorkspace;
        if (choices.isEmpty) notice = 'No active employee workspace is available. Ask HR to check your existing membership.';
      } else {
        await _open(value, generation);
      }
    } on Object catch (e) {
      if (_valid(generation)) {
        _mask();
        error = employeeFailure(e);
        phase = EmployeePhase.chooseWorkspace;
      }
    } finally {
      if (_valid(generation)) {
        busy = false;
        _emit();
      }
    }
  }

  Future<void> signIn(String email, String password) async {
    if (_disposed || busy || !_foreground || _gateway == null) return;
    final lifecycle = _lifecycleGeneration;
    if (email.trim().isEmpty || password.isEmpty) {
      error = const EmployeeFailure(
        'VALIDATION_ERROR',
        'Enter your email and password.',
      );
      _emit();
      return;
    }
    busy = true;
    error = null;
    notice = null;
    _emit();
    try {
      await _gateway.signIn(email, password);
    } on Object catch (e) {
      if (!_disposed) error = employeeFailure(e);
    } finally {
      if (!_disposed) {
        busy = false;
        _emit();
      }
    }
    if (!_disposed &&
        _foreground &&
        lifecycle == _lifecycleGeneration &&
        _gateway.actorId != null) {
      await start();
    }
  }

  Future<void> signOut() async {
    if (_disposed || _gateway == null) return;
    _logoutInProgress = true;
    final previousActor = _actor ?? _gateway.actorId;
    _generation++;
    _mask();
    workspaces = const [];
    workspace = null;
    _resumeWorkspaceKey = null;
    busy = true;
    phase = EmployeePhase.locked;
    _emit();
    try {
      await _gateway.signOut();
      if (!_disposed) {
        _durableLogoutIncomplete = false;
        _actor = null;
        phase = EmployeePhase.signedOut;
      }
    } on Object catch (e) {
      if (!_disposed) {
        if (e is EmployeeFailure && e.code == 'DURABLE_LOGOUT_INCOMPLETE') {
          _durableLogoutIncomplete = true;
          error = e;
          phase = EmployeePhase.locked;
        } else if (_gateway.actorId == null) {
          // The gateway reports remote failure after verified local removal.
          _durableLogoutIncomplete = false;
          _actor = null;
          phase = EmployeePhase.signedOut;
          notice = 'Signed out on this device. Server session revocation could not be confirmed.';
        } else {
          error = employeeFailure(e);
          phase = EmployeePhase.locked;
        }
      }
    } finally {
      _logoutInProgress = false;
      if (previousActor != null) {
        try {
          await _draftStore.clearActorDrafts(previousActor);
        } on Object catch (e) {
          if (!_disposed) error = employeeFailure(e);
        }
      }
      if (!_disposed) {
        busy = false;
        _emit();
      }
    }
  }

  Future<void> selectWorkspace(EmployeeWorkspace value) async {
    if (_disposed || busy || _gateway == null || _gateway.actorId == null) {
      return;
    }
    final authorized = workspaces.where((w) => w.key == value.key).firstOrNull;
    if (authorized == null) {
      error = const EmployeeFailure(
        'INVALID_WORKSPACE',
        'Select an active authorized workspace.',
      );
      _emit();
      return;
    }
    final generation = ++_generation;
    busy = true;
    _mask();
    phase = EmployeePhase.loading;
    _emit();
    try {
      await _open(authorized, generation);
    } on Object catch (e) {
      if (_valid(generation)) {
        _mask();
        error = employeeFailure(e);
        phase = EmployeePhase.chooseWorkspace;
      }
    } finally {
      if (_valid(generation)) {
        busy = false;
        _emit();
      }
    }
  }

  Future<void> _open(EmployeeWorkspace value, int generation) async {
    workspace = value;
    _resumeWorkspaceKey = value.key;
    try {
      final person = await _gateway!.resolveIdentity(value);
      if (!_valid(generation)) return;
      if (person.actorId != _actor || person.workspace.key != value.key) {
        throw const EmployeeFailure(
          'INVALID_RESPONSE',
          'The employee response belongs to a different account or workspace.',
        );
      }
      identity = person;
      phase = EmployeePhase.ready;
      _renewAuthorization(generation);
      // Opening a local draft requires a fresh online accepted-self check.
      final restoredDraft = await _draftStore.loadDraftLease(person);
      if (!_valid(generation)) return;
      _presentDraft(restoredDraft, generation);
      await _reviews(person, generation);
    } on EmployeeFailure catch (e) {
      if (e.code != 'SELF_LINK_REQUIRED') rethrow;
      final inbox = await _gateway!.listLinks(value);
      if (!_valid(generation)) return;
      links = List.unmodifiable(
        inbox.where((l) => l.expiresAt.isAfter(_now())),
      );
      identity = null;
      phase = EmployeePhase.linkRequired;
      _renewAuthorization(generation);
      if (links.isEmpty) notice = 'No pending account link is available. Ask HR to propose the exact employee link.';
    }
    if (!_valid(generation)) return;
    final restoredPending = await _draftStore.loadPending(value, _actor!);
    if (!_valid(generation)) return;
    _pending = restoredPending;
    if (_pending != null) notice = 'An earlier request needs receipt reconciliation before another action.';
  }

  Future<void> refresh() async {
    if (_disposed || busy || phase == EmployeePhase.locked) return;
    await start();
  }

  Future<void> _reviews(
    EmployeeIdentity person,
    int generation, {
    String? after,
  }) async {
    reviewsLoading = true;
    reviewsError = null;
    _emit();
    try {
      final page = await _gateway!.listReviews(person, after: after);
      if (!_valid(generation) || identity?.key != person.key) return;
      if (page.items.any(
        (r) => !{'reviewed', 'acknowledged', 'closed'}.contains(r.status),
      )) {
        throw const EmployeeFailure(
          'INVALID_RESPONSE',
          'The review response contains unpublished records.',
        );
      }
      final merged = after == null ? page.items : [...reviews, ...page.items];
      if (merged.map((r) => r.id).toSet().length != merged.length ||
          page.nextCursor == after && after != null) {
        throw const EmployeeFailure(
          'INVALID_RESPONSE',
          'The review page is inconsistent.',
        );
      }
      reviews = List.unmodifiable(merged);
      reviewsCursor = page.nextCursor;
    } on Object catch (e) {
      if (_valid(generation)) {
        reviewsError = employeeFailure(e);
        if (after == null) {
          reviews = const [];
          reviewsCursor = null;
        }
        if (_accessLossCodes.contains(reviewsError!.code)) {
          _lockForFailure(reviewsError!);
        }
      }
    } finally {
      if (_valid(generation)) {
        reviewsLoading = false;
        _emit();
      }
    }
  }

  Future<void> loadMoreReviews() async {
    if (!_canUsePrivateState()) return;
    if (_disposed ||
        busy ||
        reviewsLoading ||
        phase != EmployeePhase.ready ||
        identity == null ||
        reviewsCursor == null) {
      return;
    }
    await _reviews(identity!, _generation, after: reviewsCursor);
  }

  Future<void> respondToLink(EmployeeLink link, {required bool accept}) async {
    if (!_canUsePrivateState()) return;
    if (_disposed ||
        busy ||
        hasPendingCommand ||
        phase != EmployeePhase.linkRequired) {
      return;
    }
    final selected = links
        .where(
          (l) =>
              l.id == link.id &&
              l.employeeId == link.employeeId &&
              l.version == link.version,
        )
        .firstOrNull;
    if (selected == null || !selected.expiresAt.isAfter(_now())) {
      error = const EmployeeFailure(
        'STALE_LINK',
        'This link changed or expired. Refresh before responding.',
      );
      _emit();
      return;
    }
    await _submit(
      action: accept ? 'link_accept' : 'link_reject',
      targetId: selected.id,
      employeeId: selected.employeeId,
      version: selected.version,
    );
  }

  Future<void> acknowledgeReview(EmployeeReview review) async {
    if (!_canUsePrivateState()) return;
    if (_disposed ||
        busy ||
        hasPendingCommand ||
        phase != EmployeePhase.ready ||
        identity == null) {
      return;
    }
    final selected = reviews
        .where((r) => r.id == review.id && r.version == review.version)
        .firstOrNull;
    if (selected == null || !selected.canAcknowledge) {
      error = const EmployeeFailure(
        'STALE_REVIEW',
        'Only the current reviewed record can be acknowledged. Refresh first.',
      );
      _emit();
      return;
    }
    await _submit(
      action: 'review_acknowledge',
      targetId: selected.id,
      employeeId: identity!.employeeId,
      version: selected.version,
    );
  }

  Future<void> _submit({
    required String action,
    required String targetId,
    required String employeeId,
    required int version,
  }) async {
    if (workspace == null || _actor == null) return;
    final generation = _generation;
    busy = true;
    error = null;
    notice = null;
    _emit();
    try {
      final pending = EmployeePendingCommand.create(
        workspace: workspace!,
        actorId: _actor!,
        employeeId: employeeId,
        action: action,
        targetId: targetId,
        expectedVersion: version,
        now: _now(),
      );
      // No dispatch is allowed before durable, sealed recovery exists.
      await _draftStore.savePending(pending);
      if (!_valid(generation)) return;
      _pending = pending;
      await _dispatch(pending, generation);
    } on Object catch (e) {
      if (_valid(generation)) error = employeeFailure(e);
    } finally {
      if (_valid(generation)) {
        busy = false;
        _emit();
      }
    }
    if (_valid(generation) && !hasPendingCommand && error == null) {
      final confirmedNotice = notice;
      await start();
      if (!_disposed &&
          _foreground &&
          (phase == EmployeePhase.ready ||
              phase == EmployeePhase.linkRequired)) {
        notice = confirmedNotice;
        _emit();
      }
    }
  }

  Future<void> _dispatch(EmployeePendingCommand pending, int generation) async {
    try {
      await _gateway!.execute(pending);
      if (!_valid(generation)) return;
      await _clearPending(pending, generation);
      if (_valid(generation)) notice = 'The server confirmed your request.';
    } on Object catch (e) {
      if (!_valid(generation)) return;
      final failure = employeeFailure(e);
      if (_accessLossCodes.contains(failure.code)) {
        // Mask immediately. Only an explicit server rejection can delete the
        // persisted request; authentication/session failures remain uncertain.
        final current = workspace;
        _lockForFailure(failure);
        if (current != null &&
            {
              'PERMISSION_DENIED',
              'SELF_LINK_REQUIRED',
            }.contains(failure.code)) {
          try {
            await _draftStore.clearPending(
              current,
              pending.envelope.context.actorId,
            );
          } on Object {
            // Keep the sealed metadata if durable removal cannot be confirmed.
          }
        }
        return;
      }
      // Only explicit server rejection can release this command identity.
      if ({
        'VERSION_CONFLICT',
        'VALIDATION_ERROR',
        'PERMISSION_DENIED',
        'MFA_REQUIRED',
        'FEATURE_NOT_ENTITLED',
        'FEATURE_NOT_INSTALLED',
        'HR_LINK_ALREADY_EXISTS',
        'SELF_LINK_REQUIRED',
      }.contains(failure.code)) {
        await _clearPending(pending, generation);
      }
      if (_valid(generation)) error = failure;
    }
  }

  Future<void> _clearPending(
    EmployeePendingCommand pending,
    int generation,
  ) async {
    final c = pending.envelope.context;
    final current = workspace;
    if (current == null ||
        current.key != '${c.tenantId}/${c.legalEntityId}/${c.branchId}') {
      return;
    }
    await _draftStore.clearPending(current, c.actorId);
    if (_valid(generation)) _pending = null;
  }

  Future<void> reconcileCommand() => _recover(retry: false);
  Future<void> retryPendingCommand() => _recover(retry: true);
  Future<void> _recover({required bool retry}) async {
    if (!_canUsePrivateState()) return;
    final pending = _pending;
    if (_disposed ||
        busy ||
        pending == null ||
        workspace == null ||
        !(phase == EmployeePhase.ready ||
            phase == EmployeePhase.linkRequired)) {
      return;
    }
    final generation = _generation;
    busy = true;
    error = null;
    notice = null;
    _emit();
    try {
      final found = await _gateway!.hasReceipt(pending);
      if (!_valid(generation)) return;
      if (found) {
        await _clearPending(pending, generation);
        if (_valid(generation)) {
          notice = 'The original request was confirmed by its own receipt.';
        }
      } else if (retry) {
        await _dispatch(pending, generation);
      } else {
        notice = 'No receipt exists yet. You can explicitly retry the exact saved request.';
      }
    } on Object catch (e) {
      if (_valid(generation)) {
        final failure = employeeFailure(e);
        if (_accessLossCodes.contains(failure.code)) {
          _lockForFailure(failure);
        } else {
          error = failure;
        }
      }
    } finally {
      if (_valid(generation)) {
        busy = false;
        _emit();
      }
    }
    if (_valid(generation) && !hasPendingCommand && error == null) {
      final confirmedNotice = notice;
      await start();
      if (!_disposed &&
          _foreground &&
          (phase == EmployeePhase.ready ||
              phase == EmployeePhase.linkRequired)) {
        notice = confirmedNotice;
        _emit();
      }
    }
  }

  Future<void> saveLeaveDraft(EmployeeLeaveDraft draft) async {
    if (!_canUsePrivateState()) return;
    final person = identity;
    if (_disposed || busy || phase != EmployeePhase.ready || person == null) {
      return;
    }
    final generation = _generation;
    busy = true;
    error = null;
    notice = null;
    _emit();
    try {
      final saved = await _draftStore.saveDraft(person, draft);
      if (_valid(generation)) {
        _presentDraft(saved, generation);
        notice = 'Draft saved on this device for up to 24 hours. It has not been submitted.';
      }
    } on Object catch (e) {
      if (_valid(generation)) error = employeeFailure(e);
    } finally {
      if (_valid(generation)) {
        busy = false;
        _emit();
      }
    }
  }

  Future<void> discardLeaveDraft() async {
    if (!_canUsePrivateState()) return;
    final person = identity;
    if (_disposed || busy || person == null || phase != EmployeePhase.ready) {
      return;
    }
    final generation = _generation;
    busy = true;
    error = null;
    _emit();
    try {
      await _draftStore.discardDraft(person);
      if (_valid(generation)) {
        _cancelDraftRetention();
        leaveDraft = null;
      }
    } on Object catch (e) {
      if (_valid(generation)) error = employeeFailure(e);
    } finally {
      if (_valid(generation)) {
        busy = false;
        _emit();
      }
    }
  }

  void background() {
    if (_disposed || _gateway == null) return;
    _foreground = false;
    lock();
  }

  void lock() {
    if (_disposed || _gateway == null) return;
    _lifecycleGeneration++;
    _resumeWorkspaceKey = workspace?.key ?? _resumeWorkspaceKey;
    _generation++;
    _mask();
    workspace = null;
    workspaces = const [];
    busy = false;
    phase = EmployeePhase.locked;
    _emit();
  }

  Future<void> resume() async {
    if (_disposed) return;
    _foreground = true;
    if (phase == EmployeePhase.locked) await start();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _mask();
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }
}
