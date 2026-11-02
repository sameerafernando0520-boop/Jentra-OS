import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_workspace_admin.dart';
import 'package:jentra_platform/jentra_workspace_admin_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';

final workspaceAdminGatewayProvider = Provider<WorkspaceAdminRepository?>(
  (ref) => null,
);
final workspaceAdminRecoveryProvider = Provider<WorkspaceAdminRecovery>(
  (ref) => EncryptedWorkspaceAdminRecovery(
    ref.watch(encryptedDraftRepositoryProvider),
  ),
);
final workspaceAdminControllerProvider =
    Provider.autoDispose<WorkspaceAdminController?>((ref) {
      final s = ref.watch(activeTenantContextProvider),
          g = ref.watch(workspaceAdminGatewayProvider),
          caps = ref.watch(businessCapabilitiesProvider),
          revision = ref.watch(authSessionRevisionProvider);
      if (s == null ||
          g == null ||
          caps.isLoading ||
          caps.hasError ||
          revision.isLoading ||
          revision.hasError ||
          !{
            'core.tenant.manage',
            'core.roles.manage',
            'core.members.invite',
          }.any((p) => caps.value!.contains(p))) {
        return null;
      }
      final c = WorkspaceAdminController(
        scope: s,
        gateway: g,
        recovery: ref.watch(workspaceAdminRecoveryProvider),
        capabilities: caps.value!,
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
      );
      ref.listen(
        connectivityStateProvider,
        (_, next) => c.setOnline(next.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      unawaited(c.initialize());
      return c;
    });

final class WorkspaceAdminController extends ChangeNotifier {
  WorkspaceAdminController({
    required this.scope,
    required this.gateway,
    required this.recovery,
    required Set<String> capabilities,
    required this.online,
  }) : capabilities = Set.unmodifiable(capabilities);
  final TenantContext scope;
  final WorkspaceAdminRepository gateway;
  final WorkspaceAdminRecovery recovery;
  final Set<String> capabilities;
  bool online,
      busy = false,
      ready = false,
      available = false,
      _disposed = false,
      denied = false;
  int _epoch = 0;
  int get contextRevision => _epoch;
  WorkspaceAdminResource resource = WorkspaceAdminResource.entities;
  final pages = <WorkspaceAdminResource, WorkspaceAdminPage>{};
  final catalogues = <WorkspaceAdminResource, List<WorkspaceAdminRecord>>{};
  WorkspaceAdminPending? pending;
  String? error, message;
  bool get locked =>
      _disposed ||
      !ready ||
      !available ||
      !online ||
      busy ||
      pending != null ||
      denied;
  bool canRead(WorkspaceAdminResource r) =>
      capabilities.contains(r.permission) ||
      (r == WorkspaceAdminResource.entities ||
              r == WorkspaceAdminResource.branches) &&
          {
            'core.roles.manage',
            'core.members.invite',
          }.any(capabilities.contains) ||
      r == WorkspaceAdminResource.roles &&
          capabilities.contains('core.members.invite');
  List<WorkspaceAdminResource> get resources => WorkspaceAdminResource.values
      .where((r) => r != WorkspaceAdminResource.permissions && canRead(r))
      .toList();
  void emit() {
    if (!_disposed) notifyListeners();
  }

  bool current(int epoch) => !_disposed && epoch == _epoch && online;
  void setOnline(bool value) {
    if (_disposed || value == online) return;
    online = value;
    _epoch++;
    busy = false;
    pages.clear();
    catalogues.clear();
    pending = null;
    ready = false;
    available = false;
    emit();
    if (online) unawaited(initialize());
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    pages.clear();
    catalogues.clear();
    pending = null;
    super.dispose();
  }

  Future<void> initialize() async {
    if (_disposed || !online || busy) return;
    final epoch = _epoch;
    busy = true;
    error = null;
    emit();
    try {
      final restored = await recovery.load(scope);
      if (!current(epoch)) return;
      pending = restored;
      ready = true;
      resource = resources.contains(resource) ? resource : resources.first;
    } on Object {
      if (current(epoch)) {
        error =
            'Protected recovery could not be loaded. No changes can be sent.';
      }
    } finally {
      if (!_disposed && epoch == _epoch) {
        busy = false;
        emit();
      }
    }
    if (current(epoch) && ready) await load(resource);
  }

  Future<void> load(WorkspaceAdminResource target, {bool next = false}) async {
    if (_disposed || !online || busy || !canRead(target)) return;
    final epoch = _epoch, after = next ? pages[target]?.nextCursor : null;
    if (next && after == null) return;
    resource = target;
    busy = true;
    error = null;
    message = null;
    emit();
    try {
      final page = await gateway.list(scope, target, after: after);
      if (current(epoch)) {
        pages[target] = page;
        available = true;
      }
    } on Object catch (e) {
      if (current(epoch)) {
        available = false;
        pages.remove(target);
        _failure(e);
      }
    } finally {
      if (!_disposed && epoch == _epoch) {
        busy = false;
        emit();
      }
    }
  }

  Future<void> loadChoices(WorkspaceAdminResource target) async {
    if (_disposed || !online || !canRead(target)) return;
    final epoch = _epoch, records = <WorkspaceAdminRecord>[];
    String? cursor;
    do {
      final page = await gateway.list(scope, target, after: cursor, limit: 200);
      if (!current(epoch)) return;
      records.addAll(page.items);
      cursor = page.nextCursor;
      if (records.length > 1000) {
        throw const FormatException(
          'Catalogue exceeds the supported selection size.',
        );
      }
    } while (cursor != null);
    if (current(epoch)) {
      catalogues[target] = List.unmodifiable(records);
      emit();
    }
  }

  Future<bool> send(
    WorkspaceAdminAction action,
    Map<String, Object?> payload, {
    int? version,
  }) async {
    if (locked || !capabilities.contains(action.resource.permission)) {
      return false;
    }
    final epoch = _epoch;
    busy = true;
    error = null;
    message = null;
    emit();
    try {
      final p = WorkspaceAdminPending(
        action,
        CommandEnvelope(
          commandId: const Uuid().v4(),
          idempotencyKey: const Uuid().v4(),
          context: scope,
          payload: payload,
          expectedEntityVersion: version,
        ),
      );
      final stored = await recovery.seal(p);
      if (!current(epoch)) return false;
      pending = stored;
      return await _execute(epoch);
    } on Object catch (e) {
      if (current(epoch)) _failure(e);
      return false;
    } finally {
      if (!_disposed && epoch == _epoch) {
        busy = false;
        emit();
      }
    }
  }

  Future<void> retry() async {
    if (_disposed || !online || busy || pending == null || denied) return;
    final epoch = _epoch;
    busy = true;
    error = null;
    emit();
    try {
      await _execute(epoch);
    } on Object catch (e) {
      if (current(epoch)) _failure(e);
    } finally {
      if (!_disposed && epoch == _epoch) {
        busy = false;
        emit();
      }
    }
  }

  Future<bool> _execute(int epoch) async {
    final p = pending!;
    try {
      final result = await gateway.command(p.action, p.command);
      if (!current(epoch)) return false;
      if (!workspaceAdminReceiptConfirms(result, p.action, p.command)) {
        throw const DomainError(
          code: 'UNCERTAIN_RESULT',
          message: 'The confirmation could not be verified. Retry the saved request.',
        );
      }
      await recovery.complete(scope, p.command.commandId);
      if (!current(epoch)) return false;
      pending = null;
      message = 'Change confirmed. Reload the register to review its current version.';
      pages.clear();
      catalogues.clear();
      return true;
    } on DomainError catch (e) {
      if (!current(epoch)) return false;
      // Server replay occurs before mutable business validation. These known
      // rejections therefore establish that this exact command did not commit.
      if ({
        'VERSION_CONFLICT',
        'VALIDATION_ERROR',
        'CONFLICT',
        'NOT_FOUND',
      }.contains(e.code)) {
        await recovery.complete(scope, p.command.commandId);
        if (!current(epoch)) return false;
        pending = null;
      }
      _failure(e);
      return false;
    }
  }

  void _failure(Object e) {
    error = e is DomainError
        ? e.message
        : e is FormatException
        ? e.message
        : 'The result was not confirmed. Protected recovery is retained; retry the original request.';
    if (e is DomainError && e.code == 'PERMISSION_DENIED') {
      denied = true;
      available = false;
      pages.clear();
      catalogues.clear();
    }
  }
}
