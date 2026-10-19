import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_assurance.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_assurance_platform.dart';
import 'package:jentra_platform/jentra_platform.dart';

import '../../app_providers.dart';

final assuranceAccessGatewayProvider = Provider<AssuranceAccessGateway?>(
  (ref) => null,
);

final assuranceAccessControllerProvider =
    Provider.autoDispose<AssuranceAccessController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider),
          gateway = ref.watch(assuranceAccessGatewayProvider),
          caps = ref.watch(businessCapabilitiesProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          caps.isLoading ||
          caps.hasError ||
          !AssuranceAccessController.canView(caps.value ?? const {})) {
        return null;
      }
      final c = AssuranceAccessController(
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
        (_, s) => c.setOnline(s.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      unawaited(c.initialize());
      return c;
    });

/// Audit access: who holds which assurance role. A change is an encrypted
/// draft sealed with the member's access version and retried with the same
/// key after an MFA prompt or an uncertain outcome.
final class AssuranceAccessController extends ChangeNotifier {
  AssuranceAccessController({
    required this.scope,
    required this.gateway,
    required this.drafts,
    required this.online,
  });

  static const slot = 'assurance-access-command';

  /// Role management is tenant-wide; the server re-checks every call.
  static bool canView(Set<String> caps) => caps.contains('core.roles.manage');

  final TenantContext scope;
  final AssuranceAccessGateway gateway;
  final QuotationDraftStore drafts;

  bool online, busy = false, verified = false, accessDenied = false;
  bool _disposed = false;
  int _epoch = 0;
  String? error, message;
  AssuranceAccess? access;
  List<AccessMember> members = [];
  Map<String, Object?> form = {};
  QuotationLocalDraft? local;

  bool get pending => local?.pending != null;
  bool get commanding => form['membership_id'] is String;
  bool get conflicted => local?.errorCode == 'VERSION_CONFLICT';
  bool get canManage => access?.canManage ?? false;
  bool get ready => !busy && online && verified && !pending;

  AssuranceRole? get role =>
      form['role_code'] == null ? null : AssuranceRole.parse(form['role_code']);
  AccessScope? get accessScope =>
      form['scope'] == null ? null : AccessScope.parse(form['scope']);
  bool get granting => form['granted'] == true;

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
    access = null;
    members = [];
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

  Future<void> _load(int epoch) async {
    final page = await gateway.access(scope);
    if (_disposed || !online || epoch != _epoch) return;
    accessDenied = false;
    verified = true;
    access = page;
    members = page.members;
  }

  Future<void> initialize() => _run(() async {
    final epoch = _epoch;
    local = await drafts.load(scope, slot);
    if (_disposed) return;
    form = local?.form ?? {};
    if (!online) return;
    await _load(epoch);
  });

  Future<void> refresh() => initialize();

  Future<void> more() => _run(() async {
    final cursor = access?.nextCursor;
    if (!online || !verified || cursor == null) return;
    final epoch = _epoch;
    final page = await gateway.access(scope, after: cursor);
    if (!_current(epoch)) return;
    access = page;
    members = [...members, ...page.members];
  });

  /// Opens a change for [member]; the version is the member's access version.
  Future<void> startChange(
    AccessMember member,
    AssuranceRole role,
    AccessScope scope, {
    required bool grant,
  }) => _run(() async {
    if (!verified || pending || !canManage) return;
    form = {
      'membership_id': member.membershipId,
      'role_code': role.code,
      'granted': grant,
      'scope': scope.name,
      'expected_version': member.version,
      'label': member.label,
    };
    message = null;
    await drafts.save(
      this.scope,
      slot,
      form,
      expectedVersion: member.version,
      resolveConflict: true,
    );
    local = await drafts.load(this.scope, slot);
  });

  /// Adjusts the open change before it is sealed.
  void choose({AssuranceRole? role, AccessScope? scope, bool? grant}) {
    if (pending || busy || !commanding) return;
    form = {
      ...form,
      'role_code': ?role?.code,
      'scope': ?scope?.name,
      'granted': ?grant,
    };
    _emit();
  }

  Future<void> discardDraft() => _run(() async {
    if (pending) return;
    await drafts.discard(scope, slot);
    local = null;
    form = {};
  });

  Future<void> submit() => _run(() async {
    if (!online || !verified || !commanding) return;
    if (conflicted) {
      throw const FormatException(
        'This person\'s access changed. Refresh, then start again.',
      );
    }
    final epoch = _epoch;
    var request = local?.pending;
    if (request == null) {
      final version = form['expected_version']! as int;
      final payload = {
        for (final k in AssuranceAccessCommands.fields) k: form[k],
      };
      AssuranceAccessCommands.validate(payload);
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
      await gateway.setRole(request.envelope);
      await drafts.complete(scope, slot, request.envelope.commandId);
    } on DomainError catch (e) {
      await drafts.recordFailure(
        scope,
        slot,
        e,
        commandId: request.envelope.commandId,
      );
      // MFA and uncertain outcomes keep the sealed request for an identical
      // retry; only permission or authentication loss clears access data.
      if (!_disposed) local = await drafts.load(scope, slot);
      rethrow;
    }
    if (_disposed) return;
    final p = request.envelope.payload;
    final label = form['label'] ?? 'this member';
    final r = AssuranceRole.parse(p['role_code']);
    message = p['granted'] == true
        ? '${r.label} given to $label.'
        : '${r.label} removed from $label.';
    local = null;
    form = {};
    if (!_current(epoch)) return;
    await _load(epoch);
  });

  Future<bool> canLeave() async {
    if (busy) return false;
    return true;
  }
}
