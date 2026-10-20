import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_assurance.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_assurance_platform.dart';
import 'package:jentra_platform/jentra_platform.dart';

import '../../app_providers.dart';

final assuranceSettingsGatewayProvider = Provider<AssuranceSettingsGateway?>(
  (ref) => null,
);

final assuranceSettingsControllerProvider =
    Provider.autoDispose<AssuranceSettingsController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider),
          gateway = ref.watch(assuranceSettingsGatewayProvider),
          caps = ref.watch(businessCapabilitiesProvider);
      final granted = caps.value ?? const <String>{};
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          caps.isLoading ||
          caps.hasError ||
          !(granted.contains('assurance.plan.manage') ||
              granted.contains('assurance.evidence.view'))) {
        return null;
      }
      final c = AssuranceSettingsController(
        scope: scope,
        gateway: gateway,
        drafts: QuotationDraftStore(
          ref.watch(encryptedDraftRepositoryProvider),
        ),
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
        capabilities: {...granted},
      );
      ref.listen(
        connectivityStateProvider,
        (_, s) => c.setOnline(s.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      unawaited(c.initialize());
      return c;
    });

/// Audit settings: reminder bands, the finding-response deadline, rating
/// bands and monitoring thresholds for the organisation or this entity. An
/// edit is an encrypted draft sealed with the row version (0 creates it).
final class AssuranceSettingsController extends ChangeNotifier {
  AssuranceSettingsController({
    required this.scope,
    required this.gateway,
    required this.drafts,
    required this.online,
    this.capabilities = const {},
  });

  static const slot = 'assurance-settings-command';
  static const _whole = {
    'due_soon_days': (1, 30),
    'escalate_after_days': (1, 90),
    'finding_response_days': (1, 90),
    'band_critical': (2, 25),
    'band_high': (2, 25),
    'band_medium': (2, 25),
  };

  final TenantContext scope;
  final AssuranceSettingsGateway gateway;
  final QuotationDraftStore drafts;
  final Set<String> capabilities;

  bool online, busy = false, verified = false, accessDenied = false;
  bool _disposed = false;
  int _epoch = 0;
  String? error, message;
  AssuranceSettingsPage? page;
  Map<String, Object?> form = {};
  QuotationLocalDraft? local;

  bool get canEdit => capabilities.contains('assurance.plan.manage');
  bool get editing => form['level'] is String;
  bool get pending => local?.pending != null;
  bool get conflicted => local?.errorCode == 'VERSION_CONFLICT';
  bool get ready => !busy && online && verified && !pending;

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _epoch++;
    _disposed = true;
    super.dispose();
  }

  void setOnline(bool value) {
    online = value;
    if (!value) {
      _epoch++;
      verified = false;
      page = null;
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
        page = null;
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
    final p = await gateway.settings(scope);
    if (_disposed || !online || epoch != _epoch) return;
    accessDenied = false;
    verified = true;
    page = p;
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

  /// Starts editing [level] ('tenant' or 'entity') from the effective values.
  Future<void> edit(String level) => _run(() async {
    final p = page;
    if (!verified || pending || !canEdit || p == null) return;
    final s = p.effective;
    final version = p.versionFor(level);
    form = {
      'level': level,
      'expected_version': version,
      'due_soon_days': '${s.dueSoonDays}',
      'escalate_after_days': '${s.escalateAfterDays}',
      'finding_response_days': '${s.findingResponseDays}',
      'band_critical': '${s.bands.critical}',
      'band_high': '${s.bands.high}',
      'band_medium': '${s.bands.medium}',
      for (final MapEntry(key: code, value: t) in s.monitoring.entries) ...{
        'enabled.$code': t.enabled,
        'min.$code': '${t.minCount}',
      },
    };
    message = null;
    await drafts.save(
      scope,
      slot,
      form,
      expectedVersion: version,
      resolveConflict: true,
    );
    local = await drafts.load(scope, slot);
  });

  void field(String key, Object? value) {
    if (pending || busy || !editing) return;
    form = {...form, key: value};
    _emit();
  }

  int? _int(String key) => int.tryParse('${form[key] ?? ''}'.trim());

  /// Inline validation, field by field, matching the server's ranges.
  Map<String, String> get errors {
    if (!editing) return const {};
    final e = <String, String>{};
    for (final MapEntry(key: k, value: (lo, hi)) in _whole.entries) {
      final v = _int(k);
      if (v == null || v < lo || v > hi) {
        e[k] = 'Enter a whole number from $lo to $hi.';
      }
    }
    final c = _int('band_critical'),
        h = _int('band_high'),
        m = _int('band_medium');
    if (c != null && h != null && m != null && !(c > h && h > m)) {
      e.putIfAbsent(
        'band_critical',
        () => 'Each band must be higher than the next.',
      );
      e.putIfAbsent(
        'band_high',
        () => 'Each band must be higher than the next.',
      );
    }
    for (final code in assuranceMonitoringRuleCodes) {
      final v = _int('min.$code');
      if (v == null || v < 1 || v > 10000) {
        e['min.$code'] = 'Enter a whole number from 1 to 10000.';
      }
    }
    return e;
  }

  Map<String, Object?>? _payload() {
    if (!editing || errors.isNotEmpty) return null;
    return {
      'level': form['level'],
      'due_soon_days': _int('due_soon_days'),
      'escalate_after_days': _int('escalate_after_days'),
      'finding_response_days': _int('finding_response_days'),
      'rating_bands': {
        'critical': _int('band_critical'),
        'high': _int('band_high'),
        'medium': _int('band_medium'),
      },
      'monitoring': {
        for (final code in assuranceMonitoringRuleCodes)
          code: {
            'enabled': form['enabled.$code'] != false,
            'min_count': _int('min.$code'),
          },
      },
    };
  }

  /// The edited values as settings, for the live preview; null while invalid.
  AssuranceSettings? get preview {
    final p = _payload();
    return p == null
        ? null
        : AssuranceSettings.fromJson({...p, 'source': p['level']});
  }

  Future<void> discardDraft() => _run(() async {
    if (pending) return;
    await drafts.discard(scope, slot);
    local = null;
    form = {};
  });

  Future<void> submit() => _run(() async {
    if (!online || !verified || !editing || !canEdit) return;
    if (conflicted) {
      throw const FormatException(
        'These settings changed. Refresh, then edit again.',
      );
    }
    final epoch = _epoch;
    var request = local?.pending;
    if (request == null) {
      final payload = _payload();
      if (payload == null) {
        throw const FormatException('Fix the highlighted settings first.');
      }
      AssuranceSettingsCommands.validate(payload);
      final version = form['expected_version']! as int;
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
    if (_disposed || !online || epoch != _epoch || accessDenied) return;
    try {
      await gateway.saveSettings(request.envelope);
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
    message = request.envelope.payload['level'] == 'entity'
        ? 'Settings saved for this entity.'
        : 'Settings saved for the organisation.';
    local = null;
    form = {};
    await _load(epoch);
  });

  Future<bool> canLeave() async => !busy;
}
