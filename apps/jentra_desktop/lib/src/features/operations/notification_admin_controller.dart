import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';

final wave3NotificationGatewayProvider = Provider<Wave3NotificationGateway?>(
  (ref) => null,
);
final notificationAdminControllerProvider =
    Provider.autoDispose<NotificationAdminController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider),
          gateway = ref.watch(wave3NotificationGatewayProvider);
      final caps = ref.watch(businessCapabilitiesProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          caps.isLoading ||
          caps.hasError ||
          !(caps.value?.contains('core.roles.manage') ?? false)) {
        return null;
      }
      final c = NotificationAdminController(
        scope: scope,
        gateway: gateway,
        drafts: QuotationDraftStore(
          ref.watch(encryptedDraftRepositoryProvider),
        ),
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
        permissions: caps.value!,
      );
      ref.listen(
        connectivityStateProvider,
        (_, state) => c.setOnline(state.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      unawaited(c.initialize());
      return c;
    });

final class NotificationAdminController extends ChangeNotifier {
  NotificationAdminController({
    required this.scope,
    required this.gateway,
    required this.drafts,
    required this.online,
    required this.permissions,
  });
  final TenantContext scope;
  final Wave3NotificationGateway gateway;
  final QuotationDraftStore drafts;
  final Set<String> permissions;
  static const slot = 'wave3-notification-admin';
  bool online, busy = false, _disposed = false, denied = false;
  int _epoch = 0;
  String? error, message;
  QuotationLocalDraft? local;
  final pages = <String, List<Map<String, Object?>>>{};
  final cursors = <String, String?>{};
  Map<String, Object?>? scanResult;
  Map<String, Object?>? diagnosticStatus;
  bool get pending => local?.pending != null;
  bool get locked => busy || pending || denied;
  void emit() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void setOnline(bool value) {
    if (value != online) {
      online = value;
      _epoch++;
      pages.clear();
      cursors.clear();
      scanResult = null;
      diagnosticStatus = null;
    }
    emit();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    pages.clear();
    scanResult = null;
    diagnosticStatus = null;
    super.dispose();
  }

  Future<void> run(Future<void> Function() work) async {
    if (busy || _disposed) {
      return;
    }
    busy = true;
    error = null;
    emit();
    try {
      await work();
    } catch (e) {
      if (e is DomainError && e.code == 'PERMISSION_DENIED') {
        denied = true;
        pages.clear();
        scanResult = null;
        diagnosticStatus = null;
        _epoch++;
      }
      error = e is DomainError
          ? e.message
          : e is FormatException
          ? e.message
          : 'Unable to confirm this action. Saved work is retained.';
    } finally {
      busy = false;
      emit();
    }
  }

  Future<void> initialize() => run(() async {
    local = await drafts.load(scope, slot);
    if (!_disposed && online) {
      await load('members');
      await load('subscriptions');
      await loadDiagnostics();
      denied = false;
    }
  });
  Future<void> loadDiagnostics() async {
    final reader = gateway;
    if (!online || reader is! Wave3DiagnosticGateway) {
      return;
    }
    final epoch = _epoch;
    diagnosticStatus = null;
    final result = await (reader as Wave3DiagnosticGateway).diagnostics(scope);
    if (!_disposed && online && epoch == _epoch) {
      diagnosticStatus = result;
    }
  }

  Future<void> refreshDiagnostics() => run(loadDiagnostics);
  Future<void> load(String resource, {bool more = false}) async {
    if (!online) {
      return;
    }
    final epoch = _epoch;
    final result = await gateway.page(
      scope,
      resource,
      after: more ? cursors[resource] : null,
    );
    if (_disposed || epoch != _epoch || !online) {
      return;
    }
    pages[resource] = [
      if (more) ...?pages[resource],
      for (final row in result['items'] as List)
        (row as Map).cast<String, Object?>(),
    ];
    cursors[resource] = result['next_cursor'] as String?;
    denied = false;
  }

  Future<void> refresh(String resource, {bool more = false}) =>
      run(() => load(resource, more: more));
  Future<void> send(
    String operation,
    Map<String, Object?> payload, {
    int? version,
  }) => run(() async {
    if (!online || denied) {
      return;
    }
    if (pending) {
      throw const FormatException(
        'Retry the original saved action before changing it.',
      );
    }
    await drafts.save(scope, slot, {
      'operation': operation,
      'payload': payload,
    }, expectedVersion: version);
    await drafts.prepare(
      scope,
      slot,
      verb: operation == 'configure' ? 'save' : 'expire',
      payload: payload,
      expectedVersion: version,
    );
    local = await drafts.load(scope, slot);
    await executePending();
  });
  Future<void> retry() => run(executePending);
  Future<void> executePending() async {
    if (!online || denied || local?.pending == null) {
      return;
    }
    final sealed = local!.pending!;
    final operation = switch (sealed.verb) {
      'save' => 'configure',
      'expire' => 'scan',
      _ => throw const FormatException('Saved operation is invalid.'),
    };
    final epoch = _epoch;
    Map<String, Object?> result;
    try {
      result = await gateway.execute(operation, sealed.envelope);
      await drafts.confirm(
        scope,
        slot,
        sealed.envelope.commandId,
        form: {
          'operation': operation,
          'confirmed': true,
          if (operation == 'scan') 'scan_result': result,
        },
        expectedVersion: result['version'] as int?,
      );
    } on DomainError catch (e) {
      await drafts.recordFailure(
        scope,
        slot,
        e,
        commandId: sealed.envelope.commandId,
      );
      if (!_disposed) {
        local = await drafts.load(scope, slot);
      }
      rethrow;
    }
    if (_disposed) {
      return;
    }
    local = await drafts.load(scope, slot);
    if (epoch != _epoch || !online) {
      return;
    }
    message = operation == 'configure'
        ? 'Subscription action confirmed.'
        : 'Dated due scan confirmed.';
    if (operation == 'scan') {
      scanResult = result;
    }
    await load('subscriptions');
  }

  Future<void> configure(String recipient, String event) => send('configure', {
    'id': const Uuid().v4(),
    'recipient_id': recipient,
    'event_class': event,
    'enabled': true,
  }, version: 0);
  Future<void> toggle(Map<String, Object?> row) => send('configure', {
    'id': row['id'],
    'recipient_id': row['recipient_id'],
    'event_class': row['event_class'],
    'enabled': row['enabled'] != true,
  }, version: row['version'] as int);
  Future<void> scan(String kind, String cutoff, {bool more = false}) async {
    if (!permissions.contains(
      kind == 'AR' ? 'finance.receipts.view' : 'finance.payments.manage',
    )) {
      return;
    }
    if (more &&
        (scanResult?['kind'] != kind ||
            scanResult?['as_of'] != cutoff ||
            scanResult?['has_more'] != true)) {
      return;
    }
    await send('scan', {
      'kind': kind,
      'as_of': cutoff,
      if (more) 'after_id': scanResult!['next_after'],
    });
  }
}
