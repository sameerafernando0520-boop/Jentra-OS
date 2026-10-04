import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

import '../../app_providers.dart';
import '../operations/operational_read_access.dart';

final negativeStockPolicyRepositoryProvider =
    Provider<NegativeStockPolicyRepository?>((ref) => null);
final negativeStockPolicyControllerProvider =
    Provider.autoDispose<NegativeStockPolicyController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider);
      final caps = ref.watch(businessCapabilitiesProvider);
      final gateway = ref.watch(negativeStockPolicyRepositoryProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          caps.isLoading ||
          caps.hasError ||
          ![
            'inventory.stock.view',
            'inventory.stock.policy.manage',
          ].every((p) => caps.value?.contains(p) ?? false)) {
        return null;
      }
      bool online(AsyncValue<ConnectivityState> value) =>
          !value.isLoading &&
          !value.hasError &&
          value.value == ConnectivityState.online;
      final controller = NegativeStockPolicyController(
        scope: scope,
        gateway: gateway,
        drafts: QuotationDraftStore(
          ref.watch(encryptedDraftRepositoryProvider),
        ),
        online: online(ref.read(connectivityStateProvider)),
        canViewCost: caps.value!.contains('inventory.cost.view'),
      );
      ref.listen(
        connectivityStateProvider,
        (_, next) => controller.setOnline(online(next)),
      );
      ref.onDispose(controller.dispose);
      unawaited(controller.initialize());
      return controller;
    });

final class NegativeStockPolicyController extends ChangeNotifier
    implements OperationalReadAccess {
  NegativeStockPolicyController({
    required this.scope,
    required this.gateway,
    required this.drafts,
    required this.online,
    required this.canViewCost,
  });
  final TenantContext scope;
  final NegativeStockPolicyRepository gateway;
  final QuotationDraftStore drafts;
  final bool canViewCost;
  static const slot = 'negative-stock-policy-editor';
  bool online, busy = false, accessDenied = false, _disposed = false;
  int _epoch = 0;
  int _inputGeneration = 0, editorEpoch = 0;
  bool _restoredInputs = false, _dirtyInputs = false, _inputSaveFailed = false;
  int? _inputExpectedVersion;
  Future<void> _savedInputs = Future.value();
  NegativeStockPolicy? policy;
  QuotationLocalDraft? local;
  Map<String, Object?> form = {'active': false, 'reason': ''};
  List<NegativeStockEvidence> rows = [];
  NegativeStockEvidenceKind section = NegativeStockEvidenceKind.deficits;
  BigInt? cursor;
  String? error, message;
  @override
  int get readAccessEpoch => _epoch;
  @override
  bool currentRead(int epoch) =>
      !_disposed && !accessDenied && online && epoch == _epoch;
  bool _localCurrent(int epoch) =>
      !_disposed && !accessDenied && epoch == _epoch;
  bool get locked => busy || accessDenied || local?.pending != null;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _clear() {
    policy = null;
    rows = [];
    cursor = null;
    form = {};
    local = null;
    message = null;
    _dirtyInputs = false;
    _inputSaveFailed = false;
    _inputExpectedVersion = null;
  }

  @override
  void denyReadAccess() {
    if (_disposed || accessDenied) return;
    accessDenied = true;
    _epoch++;
    _clear();
    _emit();
  }

  void setOnline(bool value) {
    if (_disposed) return;
    if (online && !value) {
      _epoch++;
      policy = null;
      rows = [];
      cursor = null;
      message = null;
    }
    online = value;
    _emit();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _epoch++;
    _clear();
    _disposed = true;
    notifyListeners();
    super.dispose();
  }

  bool _denial(Object problem) =>
      problem is DomainError &&
      {
        'PERMISSION_DENIED',
        'AUTHENTICATION_REQUIRED',
        'ACCESS_DENIED',
        'TENANT_ACCESS_DENIED',
        'MFA_REQUIRED',
      }.contains(problem.code);
  Future<void> _run(Future<void> Function(int epoch) action) async {
    if (_disposed || busy || accessDenied) return;
    final epoch = _epoch;
    busy = true;
    if (!_inputSaveFailed) error = null;
    _emit();
    try {
      await action(epoch);
    } on Object catch (problem) {
      if (_localCurrent(epoch)) {
        if (_denial(problem)) denyReadAccess();
        error = problem is DomainError
            ? problem.message
            : problem is FormatException
            ? problem.message
            : 'The operation could not be confirmed. Retry when ready.';
      }
    } finally {
      if (!_disposed) {
        busy = false;
        _emit();
      }
    }
  }

  Future<void> initialize() => _run((epoch) async {
    await _savedInputs;
    if (!_localCurrent(epoch)) return;
    if (!_restoredInputs && !_dirtyInputs) {
      final recovered = await drafts.load(scope, slot);
      if (!_localCurrent(epoch)) return;
      local = recovered;
      if (recovered != null) {
        form = Map.from(recovered.form);
        _dirtyInputs = true;
        _inputExpectedVersion = recovered.expectedVersion;
      }
      _restoredInputs = true;
      editorEpoch++;
    }
    if (!currentRead(epoch)) return;
    final result = await gateway.readPolicy(scope);
    if (!currentRead(epoch)) return;
    policy = result;
    if (!_dirtyInputs && local == null) {
      form = {'active': result.active, 'reason': ''};
    }
  });
  Future<void> update(Map<String, Object?> value) async {
    if (_disposed || busy || accessDenied || local?.pending != null) return;
    final epoch = _epoch, generation = ++_inputGeneration;
    final version = BigInt.from(
      _inputExpectedVersion ??
          local?.expectedVersion ??
          _commandVersion(policy?.version ?? BigInt.zero),
    );
    final expected = _commandVersion(version);
    final next = Map<String, Object?>.from(value);
    form = next;
    _dirtyInputs = true;
    _inputExpectedVersion = expected;
    _emit();
    final write = _savedInputs.then((_) async {
      try {
        await drafts.save(scope, slot, next, expectedVersion: expected);
        if (!_localCurrent(epoch) || generation != _inputGeneration) return;
        final saved = await drafts.load(scope, slot);
        if (!_localCurrent(epoch) || generation != _inputGeneration) return;
        local = saved;
        _inputSaveFailed = false;
        error = null;
        _emit();
      } on Object {
        if (_localCurrent(epoch) && generation == _inputGeneration) {
          _inputSaveFailed = true;
          error = 'Inputs could not be saved securely. Retry the edit before recording a policy.';
          _emit();
        }
      }
    });
    _savedInputs = write;
    await write;
  }

  int _commandVersion(BigInt version) {
    if (version < BigInt.zero ||
        version > BigInt.parse('9223372036854775807')) {
      throw const FormatException(
        'Policy version cannot be represented by the command contract.',
      );
    }
    return version.toInt();
  }

  Future<void> loadEvidence(
    NegativeStockEvidenceKind kind, {
    bool more = false,
  }) => _run((epoch) async {
    if (!currentRead(epoch) ||
        !canViewCost ||
        (more && (kind != section || cursor == null))) {
      return;
    }
    final after = more ? cursor : null;
    final page = await gateway.evidence(scope, kind, after: after);
    if (!currentRead(epoch)) return;
    section = kind;
    rows = [if (more) ...rows, ...page.items];
    cursor = page.nextCursor;
  });
  Future<void> configure({bool retry = false}) => _run((epoch) async {
    if (!currentRead(epoch)) return;
    await _savedInputs;
    if (!currentRead(epoch)) return;
    if (_inputSaveFailed) return;
    var pending = local?.pending;
    if (pending == null) {
      if (retry || policy == null) return;
      final reason = form['reason'];
      final active = form['active'];
      if (active is! bool ||
          reason is! String ||
          reason.trim().isEmpty ||
          reason.trim().length > 1000) {
        throw const FormatException(
          'Choose an active state and enter a reason of 1 to 1000 characters.',
        );
      }
      final expected =
          _inputExpectedVersion ??
          local?.expectedVersion ??
          _commandVersion(policy!.version);
      final payload = <String, Object?>{
        'active': active,
        'reason': reason.trim(),
      };
      await drafts.save(scope, slot, form, expectedVersion: expected);
      if (!currentRead(epoch)) return;
      pending = await drafts.prepare(
        scope,
        slot,
        verb: 'save',
        payload: payload,
        expectedVersion: expected,
      );
      if (!currentRead(epoch)) return;
      final saved = await drafts.load(scope, slot);
      if (!currentRead(epoch)) return;
      local = saved;
    }
    if (!currentRead(epoch)) return;
    final reply = await gateway.configure(pending.envelope);
    if (reply.isFailure) {
      await drafts.recordFailure(
        scope,
        slot,
        reply.error!,
        commandId: pending.envelope.commandId,
      );
      if (!currentRead(epoch)) return;
      final saved = await drafts.load(scope, slot);
      if (!currentRead(epoch)) return;
      local = saved;
      throw reply.error!;
    }
    final result = reply.entity;
    if (result == null) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'Configuration receipt is unavailable. Retry the saved request.',
      );
    }
    await drafts.complete(scope, slot, pending.envelope.commandId);
    if (_disposed) return;
    if (local?.pending?.envelope.commandId == pending.envelope.commandId) {
      local = null;
      form = {};
      _dirtyInputs = false;
      _inputSaveFailed = false;
      _inputExpectedVersion = null;
      editorEpoch++;
    }
    if (!currentRead(epoch)) return;
    policy = null;
    message = 'Policy version ${result.version} recorded.';
    try {
      final current = await gateway.readPolicy(scope);
      if (!currentRead(epoch)) return;
      policy = current;
      form = {'active': current.active, 'reason': ''};
    } on Object catch (problem) {
      if (!currentRead(epoch)) return;
      if (_denial(problem)) rethrow;
      error =
          'Policy version ${result.version} was recorded. Refresh to view the current policy before making another change.';
    }
  });
  Future<void> discard() => _run((epoch) async {
    if (local?.pending != null) return;
    await drafts.discard(scope, slot);
    if (!_localCurrent(epoch)) return;
    local = null;
    _dirtyInputs = false;
    _inputSaveFailed = false;
    _inputExpectedVersion = null;
    form = {'active': policy?.active ?? false, 'reason': ''};
    editorEpoch++;
  });
}
