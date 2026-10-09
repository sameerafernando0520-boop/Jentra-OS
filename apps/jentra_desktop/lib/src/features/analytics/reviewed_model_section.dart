import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/jentra_domain.dart'
    show ConnectivityState, DomainError;
import 'package:jentra_platform/analytics_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';

final reviewedModelRepositoryProvider = Provider<ReviewedModelRepository?>(
  (ref) => null,
);
final reviewedModelControllerProvider =
    Provider.autoDispose<ReviewedModelController?>((ref) {
      ref.watch(authSessionRevisionProvider);
      final repo = ref.watch(reviewedModelRepositoryProvider),
          active = ref.watch(activeTenantContextProvider),
          actor = ref.watch(authenticatedActorProvider),
          caps = ref.watch(businessCapabilitiesProvider);
      if (repo == null ||
          actor.isLoading ||
          actor.hasError ||
          actor.value == null ||
          caps.isLoading ||
          caps.hasError ||
          !(caps.value ?? {}).contains('ai.proposals.view')) {
        return null;
      }
      final scope = active?.legalEntityId == null
          ? null
          : ProcessMetricScope(
              tenantId: active!.tenantId,
              legalEntityId: active.legalEntityId!,
              branchId: active.branchId,
            );
      final controller = ReviewedModelController(
        repository: repo,
        actor: actor.value!,
        scope: scope,
        store: Wave5CommandStore(
          ref.watch(encryptedDraftRepositoryProvider),
          repo.authorizeRecovery,
          namespace: 'model',
        ),
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
      );
      ref.listen(
        connectivityStateProvider,
        (_, v) => controller.setOnline(v.value == ConnectivityState.online),
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

final class ReviewedModelController extends ChangeNotifier {
  ReviewedModelController({
    required this.repository,
    required this.actor,
    required this.scope,
    required this.store,
    this.online = true,
  });
  final ReviewedModelRepository repository;
  final String actor;
  final ProcessMetricScope? scope;
  final Wave5CommandStore store;
  bool online, busy = false, disposed = false;
  int epoch = 0;
  String? error;
  Map<String, Object?>? pending;
  VerifiedModelSuggestion? suggestion;

  bool _current(int ticket) => !disposed && online && epoch == ticket;
  void clearEvidence() {
    epoch++;
    suggestion = null;
    error = null;
    busy = false;
    if (!disposed) notifyListeners();
  }

  void setOnline(bool value) {
    if (online == value) return;
    online = value;
    pending = null;
    clearEvidence();
  }

  Future<void> _run(Future<void> Function(int) action) async {
    if (!online || busy || disposed) return;
    clearEvidence();
    final ticket = epoch;
    busy = true;
    notifyListeners();
    try {
      await action(ticket);
    } catch (e) {
      if (_current(ticket)) {
        suggestion = null;
        if (e is DomainError &&
            {
              'PERMISSION_DENIED',
              'AUTH_REQUIRED',
              'WORKER_ACCESS_DENIED',
              'SOURCE_AUTHORITY_CHANGED',
            }.contains(e.code)) {
          pending = null;
        }
        error = e is DomainError ? e.message : 'The model request could not be verified. Its saved identity remains available only with current source access.';
      }
    } finally {
      if (_current(ticket)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> restore() => _run((ticket) async {
    if (scope == null) return;
    final original = await store.restore(scope!, actor);
    if (_current(ticket)) pending = original;
  });

  Future<void> request(Map<String, Object?> parameters) => _run((ticket) async {
    if (scope == null || pending != null) return;
    final saved = await store.restore(scope!, actor);
    if (!_current(ticket)) return;
    if (saved != null) {
      pending = saved;
      error = 'Review or reopen the saved invocation before starting another model request.';
      return;
    }
    final original = <String, Object?>{
      'commandId': const Uuid().v4(),
      'idempotencyKey': const Uuid().v4(),
      'clientTimestamp': DateTime.now().toUtc().toIso8601String(),
      'action': 'suggest',
      'payload': Map<String, Object?>.unmodifiable(parameters),
    };
    store.validate(original);
    await store.save(scope!, actor, original);
    if (!_current(ticket)) return;
    pending = original;
    await _invoke(ticket, original);
  });
  Future<void> reopenOriginal() => _run((ticket) async {
    if (scope == null) return;
    final saved = await store.restore(scope!, actor);
    if (!_current(ticket) || saved == null) return;
    pending = saved;
    await _invoke(ticket, saved);
  });
  Future<void> _invoke(int ticket, Map<String, Object?> original) async {
    final result = await repository.suggestion(scope!, actor, original);
    await repository.authorizeRecovery(scope!, actor);
    if (_current(ticket)) suggestion = result;
  }

  /// Unknown outcomes cannot discard an invocation or reuse its reservation.
  Future<void> finishReview() async {
    if (suggestion == null) return;
    await _run((ticket) async {
      if (scope == null) return;
      await store.remove(scope!, actor);
      if (_current(ticket)) pending = null;
    });
  }

  @override
  void dispose() {
    disposed = true;
    epoch++;
    pending = null;
    suggestion = null;
    super.dispose();
  }
}

class ReviewedModelWorkspace extends StatefulWidget {
  const ReviewedModelWorkspace({
    super.key,
    required this.controller,
    required this.capabilities,
    required this.onHumanSource,
  });
  final ReviewedModelController controller;
  final Set<String> capabilities;
  final ValueChanged<String> onHumanSource;
  @override
  State<ReviewedModelWorkspace> createState() => _ReviewedModelWorkspaceState();
}

class _ReviewedModelWorkspaceState extends State<ReviewedModelWorkspace> {
  final source = TextEditingController(),
      maxTokens = TextEditingController(text: '2000'),
      start = TextEditingController(),
      end = TextEditingController();
  bool _hasSavedParameters = false;
  void _resetInputs() {
    source.clear();
    maxTokens.text = '2000';
    final now = DateTime.now().toUtc();
    start.text = DateTime.utc(now.year, now.month, 1).toIso8601String();
    end.text = DateTime.utc(now.year, now.month + 1, 1).toIso8601String();
    _hasSavedParameters = false;
  }

  void _syncOriginal() {
    final p = widget.controller.pending?['payload'];
    if (p is Map<String, Object?>) {
      _hasSavedParameters = true;
      for (final field in [
        (source, 'sourceId'),
        (maxTokens, 'maxTokens'),
        (start, 'periodStart'),
        (end, 'periodEnd'),
      ]) {
        final value = p[field.$2] as String;
        if (field.$1.text != value) field.$1.text = value;
      }
    } else if (_hasSavedParameters) {
      _resetInputs();
    }
  }

  @override
  void initState() {
    super.initState();
    _resetInputs();
    widget.controller.addListener(_syncOriginal);
    _syncOriginal();
  }

  @override
  void didUpdateWidget(covariant ReviewedModelWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncOriginal);
      _resetInputs();
      widget.controller.addListener(_syncOriginal);
      _syncOriginal();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncOriginal);
    for (final field in [source, maxTokens, start, end]) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller,
          output = c.suggestion,
          canRead = c.online && !c.busy && c.scope != null,
          canRequest =
              canRead &&
              c.pending == null &&
              widget.capabilities.contains('ai.proposals.manage');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reviewed model suggestion',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'The worker reads only the authorized numeric forecast. A suggestion cannot execute a command. Review it before creating a human proposal.',
          ),
          if (!c.online)
            const Text('Offline · protected model evidence cleared.'),
          if (c.busy) const LinearProgressIndicator(),
          if (c.error != null) Text(c.error!),
          for (final field in [
            (source, 'Model source forecast ID'),
            (maxTokens, 'Reviewed token reservation (1–2000)'),
            (start, 'Model quota period start UTC'),
            (end, 'Model quota period end UTC (excluded)'),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: TextField(
                controller: field.$1,
                enabled: c.pending == null && !c.busy,
                decoration: InputDecoration(labelText: field.$2),
                onChanged: (_) => c.clearEvidence(),
              ),
            ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                onPressed: canRequest
                    ? () => c.request({
                        'sourceId': source.text,
                        'maxTokens': maxTokens.text,
                        'periodStart': start.text,
                        'periodEnd': end.text,
                      })
                    : null,
                child: const Text('Request reviewed suggestion'),
              ),
              TextButton(
                onPressed: canRead ? c.restore : null,
                child: const Text('Restore saved model invocation'),
              ),
              OutlinedButton(
                onPressed: canRead && c.pending != null
                    ? c.reopenOriginal
                    : null,
                child: const Text('Reopen original model invocation'),
              ),
            ],
          ),
          if (c.pending != null) ...[
            const SizedBox(height: 12),
            SelectableText(
              'Invocation ${c.pending!['commandId']} · usage event ${c.pending!['idempotencyKey']}',
            ),
            Text('Saved parameters: ${c.pending!['payload']}'),
            const Text(
              'Reopen uses the same identities. The worker returns settled output or requires review of a pending/unknown outcome; it cannot silently send a replacement call.',
            ),
          ],
          if (output != null) ...[
            const SizedBox(height: 12),
            const Text('Verified suggestion: freeze this pipeline for review.'),
            SelectableText(
              'Forecast ${output.sourceId} · source digest ${output.sourceHash}',
            ),
            Text(
              'Horizon ${output.horizonStart} to ${output.horizonEnd} (excluded). Actual token usage is settled by the trusted worker.',
            ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(
                  onPressed:
                      canRead &&
                          widget.capabilities.contains('ai.proposals.manage')
                      ? () => widget.onHumanSource(output.sourceId)
                      : null,
                  child: const Text('Use source for a human proposal'),
                ),
                TextButton(
                  onPressed: canRead ? c.finishReview : null,
                  child: const Text('Finish suggestion review'),
                ),
              ],
            ),
          ],
          const Divider(height: 40),
        ],
      );
    },
  );
}
