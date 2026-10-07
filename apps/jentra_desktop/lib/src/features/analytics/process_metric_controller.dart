import 'package:flutter/foundation.dart';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/analytics_platform.dart';

final class ProcessMetricController extends ChangeNotifier {
  ProcessMetricController({
    required this.scope,
    required this.actorId,
    required this.repository,
    this.filters,
    this.online = true,
    DateTime Function()? clock,
  }) : clock = clock ?? (() => DateTime.now().toUtc());
  final ProcessMetricScope scope;
  final String actorId;
  final ProcessMetricRepository repository;
  final ProcessFilterStore? filters;
  final DateTime Function() clock;
  bool online, busy = false, _disposed = false;
  int _epoch = 0, _detailEpoch = 0;
  ProcessMetricFilter? filter;
  ProcessMetricSummary? summary;
  Map<String, Object?>? detail;
  String? error;
  int get epoch => _epoch;
  void clear() {
    _epoch++;
    _detailEpoch++;
    summary = null;
    detail = null;
    filter = null;
    error = null;
    busy = false;
    if (!_disposed) notifyListeners();
  }

  void setOnline(bool value) {
    if (online == value) return;
    online = value;
    clear();
  }

  void changeFilter(ProcessMetricFilter value) {
    clear();
    filter = value;
  }

  bool _current(int ticket) => !_disposed && online && ticket == _epoch;
  String _safe(Object e) => e is DomainError
      ? e.message
      : e is FormatException
      ? 'Check the UTC cohort and cutoffs.'
      : 'Process evidence is unavailable. Retry the current read.';
  Future<void> read(ProcessMetricFilter value) async {
    clear();
    filter = value;
    if (!online) {
      error = 'Reconnect to authorize a new process snapshot.';
      notifyListeners();
      return;
    }
    final ticket = _epoch;
    busy = true;
    notifyListeners();
    try {
      await repository.authorize(scope);
      if (!_current(ticket)) return;
      final snapshot = await repository.snapshot(scope, value);
      await repository.authorize(scope);
      if (!_current(ticket)) return;
      summary = snapshot.summarize(generatedAt: clock().toIso8601String());
    } catch (e) {
      if (_current(ticket)) {
        summary = null;
        detail = null;
        error = _safe(e);
      }
    } finally {
      if (_current(ticket)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> saveFilter() async {
    final value = filter;
    if (!online || value == null || filters == null) return;
    final ticket = _epoch;
    try {
      await filters!.save(scope, actorId, value);
    } catch (e) {
      if (_current(ticket)) {
        summary = null;
        detail = null;
        error = _safe(e);
        notifyListeners();
      }
    }
  }

  Future<void> restoreFilter() async {
    clear();
    if (!online || filters == null) return;
    final ticket = _epoch;
    try {
      final saved = await filters!.restore(scope, actorId);
      if (_current(ticket)) {
        filter = saved;
        notifyListeners();
      }
    } catch (e) {
      if (_current(ticket)) {
        error = _safe(e);
        notifyListeners();
      }
    }
  }

  Future<void> openEvent(String eventId) async {
    if (!online ||
        summary == null ||
        !summary!.source.sourceEventIds.contains(eventId)) {
      return;
    }
    final ticket = _epoch;
    final detailTicket = ++_detailEpoch;
    detail = null;
    notifyListeners();
    try {
      final value = await repository.event(scope, eventId);
      await repository.authorize(scope);
      if (_current(ticket) && detailTicket == _detailEpoch) {
        detail = value;
        notifyListeners();
      }
    } catch (e) {
      if (_current(ticket) &&
          (detailTicket == _detailEpoch ||
              e is DomainError && e.code == 'PERMISSION_DENIED')) {
        summary = null;
        detail = null;
        error = _safe(e);
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _epoch++;
    _disposed = true;
    summary = null;
    detail = null;
    filter = null;
    super.dispose();
  }
}
