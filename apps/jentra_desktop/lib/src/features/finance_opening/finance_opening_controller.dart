import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_finance_opening.dart';
import 'package:jentra_domain/jentra_people.dart' show CivilDate;
import 'package:jentra_platform/finance_opening.dart';
import 'package:jentra_platform/finance_opening_files.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import '../operations/operational_read_access.dart';

final financeOpeningGatewayProvider = Provider<FinanceOpeningGateway?>(
  (ref) => null,
);

bool _isOnline(AsyncValue<ConnectivityState> value) =>
    !value.isLoading &&
    !value.hasError &&
    value.value == ConnectivityState.online;

final financeOpeningControllerProvider =
    Provider.autoDispose<FinanceOpeningController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider);
      final capabilities = ref.watch(businessCapabilitiesProvider);
      final gateway = ref.watch(financeOpeningGatewayProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          capabilities.isLoading ||
          capabilities.hasError ||
          !(capabilities.value?.contains('finance.openings.view') ?? false)) {
        return null;
      }
      final controller = FinanceOpeningController(
        scope: scope,
        gateway: gateway,
        drafts: QuotationDraftStore.financeOpenings(
          ref.watch(encryptedDraftRepositoryProvider),
        ),
        permissions: capabilities.value!,
        online: _isOnline(ref.read(connectivityStateProvider)),
      );
      ref.listen(connectivityStateProvider, (_, state) {
        controller.setOnline(_isOnline(state));
      });
      ref.onDispose(controller.dispose);
      unawaited(controller.initialize());
      return controller;
    });

final financeOpeningSourceProvider = FutureProvider.autoDispose
    .family<Map<String, Object?>?, String>((ref, id) {
      final scope = ref.watch(activeTenantContextProvider);
      final gateway = ref.watch(financeOpeningGatewayProvider);
      final capabilities = ref.watch(businessCapabilitiesProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          capabilities.isLoading ||
          capabilities.hasError ||
          !(capabilities.value?.contains('finance.openings.view') ?? false) ||
          !_isOnline(ref.watch(connectivityStateProvider))) {
        return null;
      }
      return gateway.source(scope, id);
    });

final class FinanceOpeningController extends ChangeNotifier
    implements OperationalReadAccess {
  FinanceOpeningController({
    required this.scope,
    required this.gateway,
    required this.drafts,
    required Set<String> permissions,
    required this.online,
  }) : permissions = Set.unmodifiable(permissions);

  // A dedicated slot keeps sealed opening commands separate from other editors.
  static const _slot = 'finance-opening-import';
  static const _uuid = Uuid();
  static const _accessFailures = {
    'PERMISSION_DENIED',
    'ACCESS_DENIED',
    'AUTHENTICATION_REQUIRED',
    'MFA_REQUIRED',
    'RECENT_MFA_REQUIRED',
    'ACCESS_CHANGED',
  };
  static const _replayNotReached = {
    ..._accessFailures,
    'FEATURE_UNAVAILABLE',
    'OPENING_REVERSAL_BUSY',
  };
  static const _reversalVerbs = {
    'request_reversal',
    'approve_reversal',
    'reject_reversal',
    'cancel_reversal',
    'post_reversal',
  };

  final TenantContext scope;
  final FinanceOpeningGateway gateway;
  final QuotationDraftStore drafts;
  final Set<String> permissions;
  bool online;
  bool busy = false;
  bool accessDenied = false;
  bool hasPending = false;
  bool _disposed = false;
  bool _recoveryReady = false;
  int _epoch = 0;
  String? error;
  String? message;
  String? cursor;
  String? fileName;
  String? baseCurrencyCode;
  List<Map<String, Object?>> batches = const [];
  Map<String, Object?>? document;
  FinanceOpeningImportPreview? localPreview;
  Map<String, Object?>? serverPreview;
  Map<String, Object?>? _editor;
  Map<String, Object?>? _reviewedPayload;
  final _optionLabels = <String, String>{};

  bool get canPrepare => permissions.contains('finance.openings.prepare');
  Map<String, Object?>? get reversal {
    final value = document?['reversal'];
    return value is Map ? value.cast<String, Object?>() : null;
  }

  bool get _canUseDocument =>
      _recoveryReady &&
      currentRead(_epoch) &&
      !busy &&
      !hasPending &&
      !editing &&
      document != null;

  bool get canRequestReversal =>
      _canUseDocument &&
      canPrepare &&
      document!['status'] == 'posted' &&
      document!['reversal_supported'] == true &&
      const [null, 'rejected', 'cancelled'].contains(reversal?['status']);

  bool canActReversal(String action) {
    final request = reversal;
    if (!_canUseDocument ||
        document!['reversal_supported'] != true ||
        request == null) {
      return false;
    }
    final preparers = document!['preparer_ids'];
    final independent = ![
      request['created_by'],
      document!['created_by'],
      document!['prepared_by'],
      document!['submitted_by'],
      if (preparers is List) ...preparers,
    ].contains(scope.actorId);
    return switch (action) {
      'approve' || 'reject' =>
        permissions.contains('finance.openings.approve') &&
            request['status'] == 'pending_approval' &&
            independent,
      'cancel' =>
        canPrepare &&
            const ['pending_approval', 'approved'].contains(request['status']),
      'post' =>
        permissions.contains('finance.openings.reverse') &&
            request['status'] == 'approved',
      _ => false,
    };
  }

  bool get canStart =>
      _recoveryReady &&
      canPrepare &&
      currentRead(_epoch) &&
      !busy &&
      !hasPending;
  bool get editing => _editor != null;
  bool get hasUnsavedPreview => editing && !hasPending;
  String get kind => editorValue('kind');
  String get currencyCode => editorValue('currency_code');
  String editorValue(String key) => _editor?[key]?.toString() ?? '';
  String optionLabel(String key) => _optionLabels[key] ?? editorValue(key);
  bool get canChooseFile =>
      canStart &&
      editing &&
      baseCurrencyCode != null &&
      [
        'source_system',
        'cutoff_date',
        'currency_code',
        'control_account_id',
        'clearing_account_id',
      ].every((key) => editorValue(key).trim().isNotEmpty);

  @override
  int get readAccessEpoch => _epoch;

  @override
  bool currentRead(int epoch) =>
      !_disposed &&
      online &&
      !accessDenied &&
      permissions.contains('finance.openings.view') &&
      epoch == _epoch;

  @override
  void denyReadAccess() {
    if (_disposed) return;
    accessDenied = true;
    _epoch++;
    _clearEvidence();
    _emit();
  }

  void setOnline(bool value) {
    if (_disposed || online == value) return;
    online = value;
    _epoch++;
    _clearEvidence();
    _emit();
  }

  void _clearEvidence() {
    batches = const [];
    cursor = null;
    document = null;
    _closeEditor();
    error = null;
    message = null;
  }

  void _closeEditor() {
    _editor = null;
    baseCurrencyCode = null;
    _optionLabels.clear();
    _clearPreview();
  }

  void _clearPreview() {
    fileName = null;
    localPreview = null;
    serverPreview = null;
    _reviewedPayload = null;
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    _clearEvidence();
    // Modal reference selectors use this notification to hide stale results.
    notifyListeners();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(int epoch) operation) async {
    if (busy || _disposed) return;
    final epoch = _epoch;
    busy = true;
    error = null;
    message = null;
    _emit();
    try {
      await operation(epoch);
    } catch (failure) {
      if (_disposed || epoch != _epoch) return;
      final code = switch (failure) {
        FinanceOpeningFailure() => failure.code,
        DomainError() => failure.code,
        _ => null,
      };
      if (_accessFailures.contains(code)) denyReadAccess();
      if (code == 'COMMAND_PENDING') hasPending = true;
      if (code == 'VERSION_CONFLICT') {
        _closeEditor();
        document = null;
      }
      if (failure is FinanceOpeningFailure &&
          code == 'OPENING_VALIDATION_FAILED' &&
          editing) {
        _reviewedPayload = null;
        serverPreview = {'valid': false, 'issues': failure.issues};
      }
      error = switch (failure) {
        FinanceOpeningFailure() => failure.message,
        DomainError() => failure.message,
        FormatException() => failure.message,
        _ =>
          'Could not finish this action. Check the connection and try again.',
      };
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> initialize() => _run((epoch) async {
    await _recover(epoch);
    if (currentRead(epoch)) await _readRegister(epoch);
  });

  Future<QuotationLocalDraft?> _recover(int epoch) async {
    final stored = await drafts.load(scope, _slot);
    if (!_disposed && epoch == _epoch) {
      _recoveryReady = true;
      hasPending = stored?.pending != null;
    }
    return stored;
  }

  Future<void> refresh({bool more = false}) {
    if (!online || busy || _disposed) return Future<void>.value();
    accessDenied = false;
    return _run((epoch) async {
      await _recover(epoch);
      final id = document?['id'];
      if (!more &&
          !editing &&
          !hasPending &&
          id is String &&
          currentRead(epoch)) {
        document = null;
        final found = await _readBatch(epoch, id);
        if (currentRead(epoch)) document = found;
      }
      if (currentRead(epoch)) await _readRegister(epoch, more: more);
    });
  }

  Future<void> _readRegister(int epoch, {bool more = false}) async {
    if (more && cursor == null) return;
    final page = await gateway.batches(scope, after: more ? cursor : null);
    if (!currentRead(epoch)) return;
    final rows = openingRows(page['items']);
    batches = more ? [...batches, ...rows] : rows;
    cursor = page['next_cursor'] as String?;
  }

  Future<void> openBatch(String id) => _run((epoch) async {
    if (!currentRead(epoch) || hasPending || editing) return;
    final found = await _readBatch(epoch, id);
    if (currentRead(epoch)) document = found;
  });

  Future<Map<String, Object?>> _readBatch(int epoch, String id) async {
    final found = await gateway.detail(scope, id);
    final current = found['reversal'];
    if (!currentRead(epoch) ||
        found['reversal_supported'] != true ||
        current is! Map ||
        current['id'] is! String) {
      return found;
    }
    final detail = await gateway.reversal(scope, current['id']! as String);
    if (!currentRead(epoch)) return found;
    if (detail['id'] != current['id'] || detail['batch_id'] != id) {
      throw const FinanceOpeningFailure(
        'INVALID_RESPONSE',
        'Reversal evidence could not be read. Refresh the batch and try again.',
        definite: true,
      );
    }
    return {...found, 'reversal': detail};
  }

  Future<Map<String, Object?>> reversalHistory(
    String batchId, {
    String? after,
  }) async {
    final epoch = _epoch;
    if (!currentRead(epoch) ||
        document?['id'] != batchId ||
        document?['reversal_supported'] != true) {
      return const {};
    }
    try {
      final page = await gateway.reversals(scope, batchId, after: after);
      return currentRead(epoch) && document?['id'] == batchId ? page : const {};
    } on FinanceOpeningFailure catch (failure) {
      if (currentRead(epoch) && _accessFailures.contains(failure.code)) {
        denyReadAccess();
      }
      rethrow;
    }
  }

  void startNew() {
    if (!canStart || editing) return;
    document = null;
    error = null;
    message = null;
    _editor = {'id': _uuid.v4(), 'kind': 'AR'};
    _emit();
  }

  void editDraft() {
    if (!canStart || editing || document?['status'] != 'draft') return;
    _editor = {
      for (final key in [
        'id',
        'kind',
        'source_system',
        'cutoff_date',
        'currency_code',
        'control_account_id',
        'clearing_account_id',
      ])
        key: document![key],
    };
    baseCurrencyCode = document!['base_currency_code'] as String?;
    _emit();
  }

  void cancelEdit() {
    if (!canStart || !editing) return;
    _closeEditor();
    error = null;
    _emit();
  }

  void invalidateFilePreview() {
    if (!canStart || !editing) return;
    _clearPreview();
    _emit();
  }

  void updateField(String key, String value) {
    if (!canStart ||
        !editing ||
        !{'kind', 'source_system', 'cutoff_date'}.contains(key)) {
      return;
    }
    if (editorValue(key) == value ||
        (key == 'kind' && !{'AR', 'AP'}.contains(value))) {
      return;
    }
    _editor![key] = value;
    if (key == 'kind') _clearAccounts();
    _clearPreview();
    error = null;
    _emit();
  }

  void _clearAccounts() {
    for (final key in ['control_account_id', 'clearing_account_id']) {
      _editor?.remove(key);
      _optionLabels.remove(key);
    }
  }

  Future<Map<String, Object?>> options(String resource, {String? after}) async {
    final epoch = _epoch;
    if (!canStart || !editing) return const {};
    try {
      final page = await gateway.options(
        scope,
        kind: kind,
        currencyCode: currencyCode.isEmpty ? 'LKR' : currencyCode,
        resource: resource,
        after: after,
      );
      return currentRead(epoch) ? page : const {};
    } on FinanceOpeningFailure catch (failure) {
      if (currentRead(epoch) && _accessFailures.contains(failure.code)) {
        denyReadAccess();
      }
      rethrow;
    }
  }

  void selectOption(
    String resource,
    Map<String, Object?> row, {
    String? baseCurrencyCode,
  }) {
    if (!canStart || !editing) return;
    final key = switch (resource) {
      'currencies' => 'currency_code',
      'control_accounts' => 'control_account_id',
      'clearing_accounts' => 'clearing_account_id',
      _ => null,
    };
    if (key == null || row['id'] is! String) return;
    final id = row['id'] as String;
    if (resource == 'currencies' && currencyCode != id) _clearAccounts();
    _editor![key] = id;
    _optionLabels[key] = [
      row['code'] ?? id,
      row['name'],
    ].whereType<String>().join(' · ');
    this.baseCurrencyCode = baseCurrencyCode ?? this.baseCurrencyCode;
    _clearPreview();
    error = null;
    _emit();
  }

  Future<void> previewFile(SelectedSetupFile file) async {
    if (!canChooseFile) return;
    await _run((epoch) async {
      _clearPreview();
      final cutoff = CivilDate.parse(editorValue('cutoff_date').trim());
      final checked = FinanceOpeningFileCodec.decode(
        file.bytes,
        file.extension,
        cutoffDate: cutoff,
        currencyCode: currencyCode,
        baseCurrencyCode: baseCurrencyCode!,
      );
      if (!currentRead(epoch)) return;
      fileName = file.name;
      localPreview = checked;
      _emit();
      if (!checked.isValid) return;
      final digest = await Sha256().hash(file.bytes);
      if (!currentRead(epoch)) return;
      final payload = <String, Object?>{
        ..._editor!,
        'source_system': editorValue('source_system').trim(),
        'cutoff_date': cutoff.value,
        'file_sha256': digest.bytes
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join(),
        'lines': [for (final line in checked.lines) line.toPayload()],
      };
      final reviewed = await gateway.preview(scope, payload);
      if (!currentRead(epoch)) return;
      serverPreview = reviewed;
      if (reviewed['valid'] == true) _reviewedPayload = payload;
    });
  }

  bool canAct(String action) {
    if (!_recoveryReady || !currentRead(_epoch) || busy || hasPending) {
      return false;
    }
    if (action == 'save') {
      return canPrepare && editing && _reviewedPayload != null;
    }
    if (editing || document == null) return false;
    final status = document!['status'];
    final preparers = document!['preparer_ids'];
    final independent = ![
      document!['created_by'],
      document!['prepared_by'],
      document!['submitted_by'],
      if (preparers is List) ...preparers,
    ].contains(scope.actorId);
    return switch (action) {
      'submit' => canPrepare && status == 'draft',
      'recall' =>
        canPrepare && ['pending_approval', 'approved'].contains(status),
      'cancel' =>
        canPrepare &&
            ['draft', 'pending_approval', 'approved'].contains(status),
      'approve' || 'reject' =>
        permissions.contains('finance.openings.approve') &&
            status == 'pending_approval' &&
            independent,
      'post' =>
        permissions.contains('finance.openings.post') && status == 'approved',
      _ => false,
    };
  }

  Future<void> act(String action, {String? reason}) async {
    if (!canAct(action)) return;
    await _run((epoch) async {
      final payload = action == 'save'
          ? _reviewedPayload!
          : <String, Object?>{
              'document_id': document!['id'],
              if (action != 'post') 'action': action,
              if (reason != null && reason.trim().isNotEmpty)
                'reason': reason.trim(),
            };
      await _prepareAndSend(
        epoch,
        verb: action == 'post' ? 'accept' : action,
        payload: payload,
        expectedVersion: document?['version'] as int? ?? 0,
      );
    });
  }

  Future<void> requestReversal({
    required String postingDate,
    required String reason,
  }) async {
    if (!canRequestReversal) return;
    await _run((epoch) async {
      final date = CivilDate.parse(postingDate.trim());
      final text = reason.trim();
      if (text.length < 3 || text.length > 500) {
        throw const FormatException(
          'Enter a reason between 3 and 500 characters.',
        );
      }
      if (date.compareTo(CivilDate.parse(document!['cutoff_date']! as String)) <
          0) {
        throw const FormatException(
          'The reversal date must be on or after the opening cutoff.',
        );
      }
      await _prepareAndSend(
        epoch,
        verb: 'request_reversal',
        payload: {
          'id': _uuid.v4(),
          'document_id': document!['id'],
          'posting_date': date.value,
          'reason': text,
        },
        expectedVersion: 0,
      );
    });
  }

  Future<void> actReversal(String action, {String? reason}) async {
    if (!canActReversal(action)) return;
    final request = reversal!;
    await _run(
      (epoch) => _prepareAndSend(
        epoch,
        verb: '${action}_reversal',
        payload: {
          'document_id': request['id'],
          'batch_id': document!['id'],
          if (action != 'post') 'action': action,
          if (reason != null && reason.trim().isNotEmpty)
            'reason': reason.trim(),
        },
        expectedVersion: request['version']! as int,
      ),
    );
  }

  Future<void> _prepareAndSend(
    int epoch, {
    required String verb,
    required Map<String, Object?> payload,
    required int expectedVersion,
  }) async {
    final existing = await _recover(epoch);
    if (!currentRead(epoch) || existing?.pending != null) return;
    if (existing != null) await drafts.discard(scope, _slot);
    if (!currentRead(epoch)) return;
    final pending = await drafts.prepare(
      scope,
      _slot,
      verb: verb,
      payload: payload,
      expectedVersion: expectedVersion,
    );
    if (!_disposed) hasPending = true;
    if (currentRead(epoch)) await _send(epoch, pending);
  }

  Future<void> retry() => _run((epoch) async {
    if (!currentRead(epoch)) return;
    final pending = (await _recover(epoch))?.pending;
    if (pending == null || !currentRead(epoch)) return;
    final permission = switch (pending.verb) {
      'accept' => 'finance.openings.post',
      'post_reversal' => 'finance.openings.reverse',
      'approve' ||
      'reject' ||
      'approve_reversal' ||
      'reject_reversal' => 'finance.openings.approve',
      _ => 'finance.openings.prepare',
    };
    if (!permissions.contains(permission)) {
      throw const DomainError(
        code: 'RETRY_NOT_PERMITTED',
        message: 'Your current role cannot retry this action.',
      );
    }
    await _send(epoch, pending, recovering: true);
  });

  Future<void> _send(
    int epoch,
    QuotationPendingCommand pending, {
    bool recovering = false,
  }) async {
    final envelope = pending.envelope;
    final verb = switch (pending.verb) {
      'save' => 'save',
      'accept' => 'post',
      'request_reversal' => 'request_reversal',
      'post_reversal' => 'post_reversal',
      'approve_reversal' ||
      'reject_reversal' ||
      'cancel_reversal' => 'transition_reversal',
      _ => 'transition',
    };
    Map<String, Object?> receipt;
    try {
      receipt = await gateway.execute(verb, envelope);
    } on FinanceOpeningFailure catch (failure) {
      if (failure.definite &&
          !(recovering && _replayNotReached.contains(failure.code))) {
        // A rejection before the replay check cannot resolve a prior attempt.
        await drafts.recordFailure(
          scope,
          _slot,
          DomainError(code: 'VALIDATION_ERROR', message: failure.message),
          commandId: envelope.commandId,
        );
        if (!_disposed) hasPending = false;
      }
      rethrow;
    }
    final entity = receipt['entity'];
    final id = envelope.payload['id'] ?? envelope.payload['document_id'];
    final expectedStatus = switch (pending.verb) {
      'submit' || 'request_reversal' => 'pending_approval',
      'approve' || 'approve_reversal' => 'approved',
      'reject_reversal' => 'rejected',
      'cancel' || 'cancel_reversal' => 'cancelled',
      'accept' || 'post_reversal' => 'posted',
      _ => 'draft',
    };
    final reversing = _reversalVerbs.contains(pending.verb);
    final batchId = reversing
        ? pending.verb == 'request_reversal'
              ? envelope.payload['document_id']
              : envelope.payload['batch_id']
        : id;
    if (id is! String ||
        entity is! Map ||
        entity['id'] != id ||
        entity['version'] != (envelope.expectedEntityVersion ?? 0) + 1 ||
        entity['status'] != expectedStatus ||
        (reversing && (batchId is! String || entity['batch_id'] != batchId))) {
      throw const FormatException(
        'The result could not be confirmed. Retry the saved request.',
      );
    }
    await drafts.complete(scope, _slot, envelope.commandId);
    if (!_disposed) hasPending = false;
    if (!currentRead(epoch)) return;
    document = null;
    _closeEditor();
    message = switch (pending.verb) {
      'request_reversal' => 'Reversal requested for independent approval.',
      'approve_reversal' => 'Opening reversal approved.',
      'reject_reversal' => 'Opening reversal rejected.',
      'cancel_reversal' => 'Opening reversal cancelled.',
      'post_reversal' =>
        'Opening reversal posted with its linked accounting records.',
      'reject' => 'Opening batch returned to the preparer.',
      'recall' => 'Opening batch recalled to draft.',
      _ => switch (entity['status']) {
        'posted' => 'Opening batch posted.',
        'pending_approval' =>
          'Opening batch submitted for independent approval.',
        'approved' => 'Opening batch approved.',
        'cancelled' => 'Opening batch cancelled.',
        _ => 'Opening batch saved as a draft.',
      },
    };
    // Replayed receipts describe the original operation, which can precede
    // later actions by another user. Read the current batch after confirmation.
    final current = await _readBatch(epoch, batchId! as String);
    if (!currentRead(epoch)) return;
    document = current;
    await _readRegister(epoch);
  }
}

List<Map<String, Object?>> openingRows(Object? value) => [
  if (value is List)
    for (final row in value)
      if (row is Map) row.cast<String, Object?>(),
];
