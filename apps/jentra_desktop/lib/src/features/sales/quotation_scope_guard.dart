import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';

import '../../app_providers.dart';
import '../operations/operational_read_access.dart';

Future<T?> showScopedQuotationDialog<T>(
  BuildContext context, {
  required TenantContext scope,
  required Set<String> capabilities,
  required WidgetBuilder builder,
  bool requireOnline = true,
  QuotationDialogAccess? originAccess,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final access = originAccess ?? QuotationDialogAccess(context);
  access.observeScope(
    container: container,
    scope: scope,
    capabilities: capabilities,
    requireOnline: requireOnline,
  );
  try {
    return await showOperationalReadDialog<T>(context, access, builder);
  } finally {
    if (originAccess == null) access.dispose();
  }
}

final class QuotationDialogAccess extends ChangeNotifier
    implements OperationalReadAccess {
  QuotationDialogAccess(this.origin) {
    ModalRoute.of(origin)?.popped.then((_) => denyReadAccess());
  }
  final BuildContext origin;
  final _closeObservers = <VoidCallback>[];
  bool _active = true, _disposed = false, _observing = false;
  int _epoch = 0;

  /// The caller retains these observers through consuming the awaited result.
  void observeScope({
    required ProviderContainer container,
    required TenantContext scope,
    required Set<String> capabilities,
    bool requireOnline = true,
    String? permission,
  }) {
    if (_disposed || _observing) return;
    _observing = true;
    void observe() {
      if (_disposed || !_active) return;
      if (!origin.mounted) {
        denyReadAccess();
        return;
      }
      final caps = container.read(businessCapabilitiesProvider);
      final connection = container.read(connectivityStateProvider);
      if (container.read(activeTenantContextProvider) != scope ||
          caps.isLoading ||
          caps.hasError ||
          caps.value == null ||
          caps.value!.length != capabilities.length ||
          !caps.value!.containsAll(capabilities) ||
          (permission != null && !caps.value!.contains(permission)) ||
          (requireOnline &&
              (connection.isLoading ||
                  connection.hasError ||
                  connection.value != ConnectivityState.online))) {
        denyReadAccess();
      }
    }

    final scopes = container.listen(
      activeTenantContextProvider,
      (_, _) => observe(),
    );
    final caps = container.listen(
      businessCapabilitiesProvider,
      (_, _) => observe(),
    );
    final connections = container.listen(
      connectivityStateProvider,
      (_, _) => observe(),
    );
    _closeObservers.addAll([scopes.close, caps.close, connections.close]);
    observe();
  }

  @override
  int get readAccessEpoch => _epoch;
  @override
  bool currentRead(int epoch) =>
      !_disposed && _active && origin.mounted && epoch == _epoch;
  @override
  void denyReadAccess() {
    if (_disposed || !_active) return;
    _active = false;
    _epoch++;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final close in _closeObservers) {
      close();
    }
    _closeObservers.clear();
    super.dispose();
  }
}

/// Dialog routes also invalidate sensitive content when their originating scope changes.
class QuotationScopeGuard extends ConsumerStatefulWidget {
  const QuotationScopeGuard({
    required this.scope,
    required this.capabilities,
    required this.child,
    super.key,
  });
  final TenantContext scope;
  final Set<String> capabilities;
  final Widget child;
  @override
  ConsumerState<QuotationScopeGuard> createState() =>
      _QuotationScopeGuardState();
}

class _QuotationScopeGuardState extends ConsumerState<QuotationScopeGuard> {
  bool _invalidated = false, _authorizedOnce = false;
  bool capabilitiesMatch(AsyncValue<Set<String>> current) =>
      !current.isLoading &&
      !current.hasError &&
      current.value != null &&
      current.value!.length == widget.capabilities.length &&
      current.value!.containsAll(widget.capabilities);
  void observe(bool active) {
    if (active) _authorizedOnce = true;
    if (!active && _authorizedOnce && !_invalidated) {
      setState(() => _invalidated = true);
    }
  }

  @override
  void initState() {
    super.initState();
    observe(
      ref.read(activeTenantContextProvider) == widget.scope &&
          capabilitiesMatch(ref.read(businessCapabilitiesProvider)),
    );
    ref.listenManual(activeTenantContextProvider, (_, next) {
      observe(
        next == widget.scope &&
            capabilitiesMatch(ref.read(businessCapabilitiesProvider)),
      );
    });
    ref.listenManual(businessCapabilitiesProvider, (_, next) {
      observe(
        ref.read(activeTenantContextProvider) == widget.scope &&
            capabilitiesMatch(next),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(businessCapabilitiesProvider);
    final active =
        ref.watch(activeTenantContextProvider) == widget.scope &&
        capabilitiesMatch(current);
    if (active) _authorizedOnce = true;
    if (!active && _authorizedOnce) _invalidated = true;
    return active && !_invalidated
        ? widget.child
        : AlertDialog(
            title: const Text('Business scope or access changed'),
            content: const Text(
              'Close this dialog and reopen the quotation in your current scope.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
  }
}
