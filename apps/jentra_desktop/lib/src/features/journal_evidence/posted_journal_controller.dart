import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';

import '../../app_providers.dart';

typedef PostedJournalTarget = ({
  String tenantId,
  String entityId,
  String branchId,
  String journalId,
});

final postedJournalGatewayProvider = Provider<PostedJournalGateway?>(
  (ref) => null,
);
final postedJournalControllerProvider = Provider.autoDispose
    .family<PostedJournalController?, PostedJournalTarget>((ref, target) {
      final scope = ref.watch(activeTenantContextProvider);
      final caps = ref.watch(businessCapabilitiesProvider);
      final gateway = ref.watch(postedJournalGatewayProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          caps.isLoading ||
          caps.hasError ||
          !(caps.value?.contains('finance.view') ?? false)) {
        return null;
      }
      final c = PostedJournalController(
        scope: scope,
        gateway: gateway,
        target: target,
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
      );
      ref.listen(
        connectivityStateProvider,
        (_, v) => c.setOnline(v.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      unawaited(c.refresh());
      return c;
    });

final class PostedJournalController extends ChangeNotifier {
  PostedJournalController({
    required this.scope,
    required this.gateway,
    required this.target,
    required this.online,
  });
  final TenantContext scope;
  final PostedJournalGateway gateway;
  final PostedJournalTarget target;
  bool online, busy = false, verified = false, _disposed = false;
  int _epoch = 0, afterLine = 0;
  int? nextCursor;
  String? error;
  Map<String, Object?> journal = {};
  List<Map<String, Object?>> rows = [];
  List<int> previousPages = [];
  bool get matchingScope =>
      target.tenantId == scope.tenantId &&
      target.entityId == scope.legalEntityId &&
      target.branchId == scope.branchId &&
      target.journalId.isNotEmpty;
  bool current(int epoch) => !_disposed && online && epoch == _epoch;
  void emit() {
    if (!_disposed) notifyListeners();
  }

  void clear() {
    verified = false;
    journal = {};
    rows = [];
    nextCursor = null;
  }

  void setOnline(bool value) {
    if (online == value) return;
    online = value;
    if (!value) {
      _epoch++;
      busy = false;
      clear();
      previousPages = [];
      afterLine = 0;
    }
    emit();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    clear();
    super.dispose();
  }

  Future<void> read(int cursor, List<int> previous) async {
    if (_disposed || busy) return;
    clear();
    error = null;
    if (!matchingScope) {
      error = 'This destination is unavailable in the selected tenant, entity and branch.';
      emit();
      return;
    }
    if (!online) {
      error = 'Connect to verify current journal access.';
      emit();
      return;
    }
    busy = true;
    final epoch = ++_epoch;
    emit();
    try {
      final r = await gateway.page(scope, target.journalId, afterLine: cursor);
      if (!current(epoch)) return;
      journal = (r['journal'] as Map).cast<String, Object?>();
      rows = (r['items'] as List)
          .map((r) => (r as Map).cast<String, Object?>())
          .toList();
      nextCursor = r['next_cursor'] as int?;
      afterLine = cursor;
      previousPages = previous;
      verified = true;
    } catch (e) {
      if (!current(epoch)) return;
      clear();
      previousPages = [];
      afterLine = 0;
      error = e is DomainError
          ? (e.code == 'PERMISSION_DENIED'
                ? 'This journal is unavailable with your current access.'
                : e.message)
          : e is FormatException
          ? e.message
          : 'Journal evidence could not be verified. Refresh to try again.';
    } finally {
      if (current(epoch)) {
        busy = false;
        emit();
      }
    }
  }

  Future<void> refresh() => read(0, []);
  Future<void> next() async {
    if (verified && nextCursor != null) {
      await read(nextCursor!, [...previousPages, afterLine]);
    }
  }

  Future<void> previous() async {
    if (verified && previousPages.isNotEmpty) {
      await read(
        previousPages.last,
        previousPages.sublist(0, previousPages.length - 1),
      );
    }
  }
}
