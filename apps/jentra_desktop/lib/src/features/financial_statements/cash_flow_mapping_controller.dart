import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';

final cashFlowMappingGatewayProvider = Provider<CashFlowMappingGateway?>(
  (ref) => null,
);

final cashFlowMappingControllerProvider =
    Provider.autoDispose<CashFlowMappingController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider);
      final gateway = ref.watch(cashFlowMappingGatewayProvider);
      final access = ref.watch(businessCapabilitiesProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          access.isLoading ||
          access.hasError ||
          !const {
            'finance.view',
            'finance.cash_flow.configure',
          }.every((code) => access.value?.contains(code) ?? false)) {
        return null;
      }
      final controller = CashFlowMappingController(
        scope: scope,
        gateway: gateway,
        drafts: QuotationDraftStore(
          ref.watch(encryptedDraftRepositoryProvider),
        ),
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
      );
      ref.listen(
        connectivityStateProvider,
        (_, state) =>
            controller.setOnline(state.value == ConnectivityState.online),
      );
      ref.onDispose(controller.dispose);
      unawaited(controller.initialize());
      return controller;
    });

final class CashFlowMappingController extends ChangeNotifier {
  CashFlowMappingController({
    required this.scope,
    required this.gateway,
    required this.drafts,
    required this.online,
  });

  static const slot = 'cash-flow-mapping-editor';
  static const categories = {
    'cash': 'Cash or bank',
    'noncash_adjustment': 'Noncash adjustment',
    'working_capital': 'Working capital',
    'investing': 'Investing',
    'financing': 'Financing',
  };

  final TenantContext scope;
  final CashFlowMappingGateway gateway;
  final QuotationDraftStore drafts;
  bool online,
      busy = false,
      verified = false,
      denied = false,
      _disposed = false;
  String? error, message, cursor;
  List<Map<String, Object?>> accounts = [];
  Map<String, Object?> form = {};
  QuotationLocalDraft? local;

  String get today => DateTime.now().toUtc().toIso8601String().substring(0, 10);
  String get latestEffectiveDate => DateTime.now()
      .toUtc()
      .add(const Duration(days: 365))
      .toIso8601String()
      .substring(0, 10);
  bool get pending => local?.pending != null;
  bool get locked => busy || pending || denied || !verified;
  Map<String, Object?>? get selectedAccount {
    for (final row in accounts) {
      if (row['id'] == form['account_id']) return row;
    }
    return null;
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void setOnline(bool value) {
    online = value;
    if (!online) {
      verified = false;
      accounts = [];
      cursor = null;
    }
    _emit();
  }

  void _handle(Object failure) {
    if (failure is DomainError && failure.code == 'PERMISSION_DENIED') {
      denied = true;
      verified = false;
      accounts = [];
      cursor = null;
      form = {};
    }
    error = failure is DomainError
        ? failure.message
        : failure is FormatException
        ? failure.message
        : 'Unable to confirm the result. Your sealed request is retained.';
  }

  Future<void> _run(Future<void> Function() work) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    _emit();
    try {
      await work();
    } catch (failure) {
      _handle(failure);
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> initialize() => _run(() async {
    local = await drafts.load(scope, slot);
    if (!online) return;
    accounts = [];
    cursor = null;
    await _load();
    if (_disposed) return;
    form = local?.form ?? _newForm();
    verified = true;
    denied = false;
  });

  Map<String, Object?> _newForm() => {
    'id': const Uuid().v4(),
    'account_id': null,
    'category': null,
    'effective_date': today,
    'reason': '',
  };

  Future<void> _load({bool more = false}) async {
    if (!online) return;
    final result = await gateway.options(
      scope,
      today,
      after: more ? cursor : null,
    );
    if (_disposed) return;
    accounts = [
      if (more) ...accounts,
      for (final value in result['items'] as List)
        (value as Map).cast<String, Object?>(),
    ];
    cursor = result['next_cursor'] as String?;
  }

  Future<void> moreAccounts() => _run(() => _load(more: true));
  Future<void> refresh() => _run(() async {
    if (!online || !verified || denied) return;
    await _load();
  });

  Future<void> select(String id) => _run(() async {
    if (pending || denied || !verified) return;
    final account = accounts.where((row) => row['id'] == id).firstOrNull;
    if (account == null || account['status'] != 'active') return;
    form = {
      'id': const Uuid().v4(),
      'account_id': id,
      'category': account['category'],
      'effective_date': today,
      'reason': '',
    };
    message = null;
    await persist();
  });

  void field(String key, String? value) {
    if (locked ||
        !const {'category', 'effective_date', 'reason'}.contains(key)) {
      return;
    }
    form = {...form, key: value?.trim()};
    _emit();
  }

  Future<void> persist() async {
    await drafts.save(
      scope,
      slot,
      form,
      expectedVersion: selectedAccount?['version'] as int? ?? 0,
    );
    local = await drafts.load(scope, slot);
  }

  Future<void> save() => _run(() async {
    if (!pending && !denied && form.isNotEmpty) await persist();
  });

  Future<bool> canLeave() async {
    if (busy) return false;
    if (pending || denied || form.isEmpty) return true;
    await save();
    return error == null;
  }

  void _validate() {
    final account = selectedAccount;
    final category = form['category'];
    final date = form['effective_date'];
    final reason = form['reason'];
    if (account == null || account['status'] != 'active') {
      throw const FormatException('Choose an active posting account.');
    }
    if (!categories.containsKey(category)) {
      throw const FormatException('Choose a cash-flow category.');
    }
    if (category == 'cash' && account['account_type'] != 'asset') {
      throw const FormatException(
        'Cash classification requires an asset account.',
      );
    }
    if (date is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        DateTime.tryParse(date)?.toIso8601String().substring(0, 10) != date ||
        date.compareTo('2000-01-01') < 0 ||
        date.compareTo(latestEffectiveDate) > 0) {
      throw const FormatException(
        'Choose a valid effective date within one year.',
      );
    }
    if (reason is! String || reason.trim().length < 3 || reason.length > 1000) {
      throw const FormatException('Provide a reason of 3 to 1000 characters.');
    }
  }

  Future<void> configure() => _run(() async {
    if (!online || !verified || denied) return;
    var command = local?.pending;
    if (command == null) {
      _validate();
      await persist();
      command = await drafts.prepare(
        scope,
        slot,
        verb: 'accept',
        expectedVersion: selectedAccount?['version'] as int? ?? 0,
        payload: {
          'id': form['id'],
          'account_id': form['account_id'],
          'category': form['category'],
          'effective_date': form['effective_date'],
          'reason': (form['reason'] as String).trim(),
        },
      );
      local = await drafts.load(scope, slot);
    }
    try {
      await gateway.configure(command.envelope);
      await drafts.complete(scope, slot, command.envelope.commandId);
    } on DomainError catch (failure) {
      await drafts.recordFailure(
        scope,
        slot,
        failure,
        commandId: command.envelope.commandId,
      );
      local = await drafts.load(scope, slot);
      rethrow;
    }
    if (_disposed) return;
    local = null;
    message =
        'Dated classification recorded. Generate a new cash-flow statement.';
    form = _newForm();
    await persist();
    try {
      await _load();
    } catch (failure) {
      _handle(failure);
      if (!denied) {
        error = 'Classification confirmed. Refresh account evidence.';
      }
    }
  });

  Future<void> retry() => configure();
}
