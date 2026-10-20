import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_assurance.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_assurance_platform.dart';

import '../../app_providers.dart';

final assuranceMetricsGatewayProvider = Provider<AssuranceMetricsGateway?>(
  (ref) => null,
);

final assuranceMetricsControllerProvider =
    Provider.autoDispose<AssuranceMetricsController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider),
          gateway = ref.watch(assuranceMetricsGatewayProvider),
          caps = ref.watch(businessCapabilitiesProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          caps.isLoading ||
          caps.hasError ||
          !AssuranceMetricsController.canView(caps.value ?? const {})) {
        return null;
      }
      final c = AssuranceMetricsController(
        scope: scope,
        gateway: gateway,
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
      );
      ref.listen(
        connectivityStateProvider,
        (_, s) => c.setOnline(s.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      unawaited(c.load());
      return c;
    });

enum MetricsPeriod {
  month(30, '30 days'),
  quarter(90, '90 days'),
  year(365, '12 months');

  const MetricsPeriod(this.days, this.label);
  final int days;
  final String label;
}

/// Audit process metrics for a period ending today. Read-only: nothing is
/// drafted or sent, and a slower answer for an earlier period is discarded.
final class AssuranceMetricsController extends ChangeNotifier {
  AssuranceMetricsController({
    required this.scope,
    required this.gateway,
    required this.online,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static bool canView(Set<String> caps) =>
      caps.contains('assurance.evidence.view');

  final TenantContext scope;
  final AssuranceMetricsGateway gateway;
  final DateTime Function() _clock;

  bool online, busy = false, accessDenied = false;
  bool _disposed = false;
  int _epoch = 0;
  String? error;
  MetricsPeriod period = MetricsPeriod.quarter;
  AssuranceMetrics? metrics;

  /// The local calendar day today, back [MetricsPeriod.days] days inclusive.
  ({DateTime from, DateTime to}) get range {
    final now = _clock();
    final to = DateTime.utc(now.year, now.month, now.day);
    return (from: to.subtract(Duration(days: period.days - 1)), to: to);
  }

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
    final was = online;
    online = value;
    if (!value) {
      _epoch++;
      busy = false;
      metrics = null;
    }
    _emit();
    if (value && !was) unawaited(load());
  }

  Future<void> choose(MetricsPeriod p) async {
    if (p == period) return;
    period = p;
    metrics = null;
    await load();
  }

  Future<void> load() async {
    if (_disposed) return;
    final epoch = ++_epoch;
    if (!online) return _emit();
    busy = true;
    error = null;
    _emit();
    try {
      final r = range;
      final m = await gateway.metrics(scope, r.from, r.to);
      if (_disposed || epoch != _epoch) return;
      accessDenied = false;
      metrics = m;
    } catch (e) {
      if (_disposed || epoch != _epoch) return;
      if (e is DomainError &&
          const {
            'PERMISSION_DENIED',
            'AUTHENTICATION_REQUIRED',
          }.contains(e.code)) {
        accessDenied = true;
        metrics = null;
      }
      error = e is DomainError
          ? e.message
          : e is FormatException
          ? e.message
          : 'Metrics could not be loaded. Try again.';
    } finally {
      if (epoch == _epoch) {
        busy = false;
        _emit();
      }
    }
  }
}
