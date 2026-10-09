import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart' show ConnectivityState;
import 'package:jentra_domain/analytics.dart';
import 'package:uuid/uuid.dart';
import 'package:jentra_platform/analytics_platform.dart';

import '../../app_providers.dart';

final integrationRpcProvider = Provider<ProcessMetricRpc?>((ref) => null);
final integrationListProvider = FutureProvider.autoDispose
    .family<Map<String, Object?>, (String?, String?)>((ref, cursors) async {
      ref.watch(authSessionRevisionProvider);
      final actor = await ref.watch(authenticatedActorProvider.future),
          scope = ref.watch(activeTenantContextProvider);
      final caps = await ref.watch(businessCapabilitiesProvider.future),
          online = await ref.watch(connectivityStateProvider.future);
      final rpc = ref.watch(integrationRpcProvider);
      if (actor == null ||
          actor != scope?.actorId ||
          scope?.legalEntityId == null ||
          !caps.contains('integrations.manage') ||
          online != ConnectivityState.online ||
          rpc == null) {
        throw StateError('Current online integration authority required.');
      }
      final raw = await rpc('wave5_integration_list', {
        'p_tenant_id': scope!.tenantId,
        'p_legal_entity_id': scope.legalEntityId,
        'p_branch_id': scope.branchId,
        'p_subscription_after': cursors.$1,
        'p_delivery_after': cursors.$2,
      });
      if (raw is! Map<String, Object?> ||
          raw.length != 5 ||
          raw['contractRevision'] != 1 ||
          raw['subscriptions'] is! List ||
          (raw['subscriptions'] as List).length > 50 ||
          raw['deliveries'] is! List ||
          (raw['deliveries'] as List).length > 50) {
        throw const FormatException('Invalid subscription projection.');
      }
      for (final field in ['subscriptionNext', 'deliveryNext']) {
        final cursor = raw[field];
        if (cursor != null) {
          ProcessMetricScope(tenantId: cursor as String, legalEntityId: cursor);
        }
      }
      if (await rpc('wave5_integration_authorize', {
            'p_tenant_id': scope.tenantId,
            'p_legal_entity_id': scope.legalEntityId,
            'p_branch_id': scope.branchId,
          }) !=
          actor) {
        throw StateError('Current MFA integration authority required.');
      }
      return raw;
    });

class IntegrationScreen extends ConsumerStatefulWidget {
  const IntegrationScreen({super.key});
  @override
  ConsumerState<IntegrationScreen> createState() => _IntegrationScreenState();
}

class _IntegrationScreenState extends ConsumerState<IntegrationScreen> {
  (String?, String?) cursors = (null, null);
  final previous = <(String?, String?)>[];
  final actions = GlobalKey<_IntegrationActionsState>();
  void next((String?, String?) value) => setState(() {
    previous.add(cursors);
    cursors = value;
  });
  @override
  Widget build(BuildContext context) {
    ref.listen(activeTenantContextProvider, (_, _) {
      setState(() {
        cursors = (null, null);
        previous.clear();
      });
    });
    final list = ref.watch(integrationListProvider(cursors));
    final controller = ref.watch(integrationControllerProvider);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Integrations', style: Theme.of(context).textTheme.headlineMedium),
        const Text(
          'Scoped webhook subscriptions. Registration, vault-key rotation and reviewed replay require MFA and a reviewed destination.',
        ),
        if (controller != null)
          _IntegrationActions(key: actions, controller: controller),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: () => ref.invalidate(integrationListProvider),
            child: const Text('Refresh subscriptions'),
          ),
        ),
        list.when(
          skipLoadingOnRefresh: false,
          skipLoadingOnReload: false,
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => const Text(
            'Integration storage or current authority is unavailable.',
          ),
          data: (value) => Column(
            children: [
              const Text(
                'Up to 50 subscriptions and 50 delivery outcomes per page',
              ),
              for (final row in value['subscriptions'] as List)
                ListTile(
                  onTap: () => actions.currentState?.selectSubscription(
                    row.cast<String, Object?>(),
                  ),
                  title: Text((row as Map)['url'] as String),
                  subtitle: Text(
                    'Revision ${row['version']} · key ${row['keyVersion']} · ${row['enabled'] == true ? 'enabled' : 'revoked'}',
                  ),
                ),
              for (final row in value['deliveries'] as List)
                ListTile(
                  onTap: () =>
                      actions.currentState?.selectDelivery(row['id'] as String),
                  title: SelectableText('Delivery ${(row as Map)['id']}'),
                  subtitle: Text(
                    '${row['state']} · attempt ${row['attempt']} · generation ${row['generation']}',
                  ),
                ),
              Wrap(
                spacing: 12,
                children: [
                  TextButton(
                    onPressed: previous.isEmpty
                        ? null
                        : () => setState(() {
                            cursors = previous.removeLast();
                          }),
                    child: const Text('Previous page'),
                  ),
                  TextButton(
                    onPressed: value['subscriptionNext'] == null
                        ? null
                        : () => next((
                            value['subscriptionNext'] as String,
                            cursors.$2,
                          )),
                    child: const Text('Next subscriptions'),
                  ),
                  TextButton(
                    onPressed: value['deliveryNext'] == null
                        ? null
                        : () => next((
                            cursors.$1,
                            value['deliveryNext'] as String,
                          )),
                    child: const Text('Next delivery outcomes'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

final integrationControllerProvider =
    Provider.autoDispose<IntegrationController?>((ref) {
      ref.watch(authSessionRevisionProvider);
      final actor = ref.watch(authenticatedActorProvider),
          context = ref.watch(activeTenantContextProvider),
          caps = ref.watch(businessCapabilitiesProvider),
          rpc = ref.watch(integrationRpcProvider);
      if (actor.isLoading ||
          actor.hasError ||
          actor.value == null ||
          actor.value != context?.actorId ||
          context?.legalEntityId == null ||
          rpc == null ||
          caps.isLoading ||
          caps.hasError ||
          !{
            'analytics.view',
            'integrations.manage',
          }.every((p) => caps.value?.contains(p) ?? false)) {
        return null;
      }
      final scope = ProcessMetricScope(
        tenantId: context!.tenantId,
        legalEntityId: context.legalEntityId!,
        branchId: context.branchId,
      );
      Future<void> authorize(ProcessMetricScope s, String a) async {
        if (await rpc('wave5_integration_authorize', {
              'p_tenant_id': s.tenantId,
              'p_legal_entity_id': s.legalEntityId,
              'p_branch_id': s.branchId,
            }) !=
            a) {
          throw StateError('Current MFA actor required.');
        }
      }

      final c = IntegrationController(
        scope,
        actor.value!,
        rpc,
        Wave5CommandStore(
          ref.watch(encryptedDraftRepositoryProvider),
          authorize,
          namespace: 'integration',
        ),
        authorize,
      );
      c.setOnline(
        ref.read(connectivityStateProvider).value == ConnectivityState.online,
      );
      ref.listen(
        connectivityStateProvider,
        (_, v) => c.setOnline(v.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      return c;
    });

final class IntegrationController extends ChangeNotifier {
  IntegrationController(
    this.scope,
    this.actor,
    this.rpc,
    this.store,
    this.authorize,
  );
  final ProcessMetricScope scope;
  final String actor;
  final ProcessMetricRpc rpc;
  final Wave5CommandStore store;
  final Future<void> Function(ProcessMetricScope, String) authorize;
  bool online = true, busy = false, dead = false;
  int epoch = 0;
  Map<String, Object?>? pending, receipt;
  String? error;
  void setOnline(bool value) {
    if (online == value) return;
    online = value;
    epoch++;
    pending = null;
    receipt = null;
    error = null;
    busy = false;
    notifyListeners();
  }

  bool current(int t) => !dead && online && t == epoch;
  Future<void> restore() async {
    if (busy || !online || dead) return;
    final t = ++epoch;
    busy = true;
    error = null;
    receipt = null;
    notifyListeners();
    try {
      final found = await store.restore(scope, actor);
      if (current(t)) pending = found;
    } catch (_) {
      if (current(t)) error = 'Saved integration request is unavailable under current MFA access.';
    } finally {
      if (current(t)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> submit(String action, Map<String, String> payload) async {
    if (busy || !online || dead || pending != null) return;
    await restore();
    if (busy || !online || dead || error != null || pending != null) return;
    final id = const Uuid().v4();
    pending = {
      'commandId': id,
      'idempotencyKey': id,
      'clientTimestamp': DateTime.now().toUtc().toIso8601String(),
      'action': action,
      'payload': payload,
    };
    await retry();
  }

  Future<void> retry() async {
    if (busy || !online || dead || pending == null) return;
    final t = ++epoch, request = Map<String, Object?>.from(pending!);
    busy = true;
    error = null;
    receipt = null;
    notifyListeners();
    try {
      store.validate(request);
      await store.save(scope, actor, request);
      await authorize(scope, actor);
      final action = request['action'] as String,
          p = (request['payload'] as Map).cast<String, Object?>();
      final s = {
        'p_tenant_id': scope.tenantId,
        'p_legal_entity_id': scope.legalEntityId,
        'p_branch_id': scope.branchId,
      };
      final raw = action.startsWith('credential_')
          ? await rpc('wave5_credential_manage', {
              ...s,
              'p_action': action == 'credential_register'
                  ? 'register'
                  : 'revoke',
              'p_id': p['id'],
              'p_payload': action == 'credential_register'
                  ? {
                      'tokenHash': p['tokenHash'],
                      'startsAt': p['startsAt'],
                      'expiresAt': p['expiresAt'],
                    }
                  : <String, Object?>{},
            })
          : action == 'review'
          ? await rpc('wave5_delivery_review', {
              ...s,
              'p_delivery_id': p['deliveryId'],
              'p_review_id': request['commandId'],
              'p_action': p['decision'],
              'p_reason': p['reason'],
            })
          : await rpc('wave5_integration_manage', {
              ...s,
              'p_action': action,
              'p_id': p['id'],
              'p_expected_version': p['expectedVersion'],
              'p_payload': action == 'register'
                  ? {'url': p['url'], 'keyRef': p['keyRef']}
                  : action == 'rotate'
                  ? {'keyRef': p['keyRef']}
                  : <String, Object?>{},
            });
      await authorize(scope, actor);
      if (raw is! Map<String, Object?> || raw['id'] is! String) {
        throw const FormatException('Invalid integration receipt.');
      }
      await store.remove(scope, actor);
      if (current(t)) {
        pending = null;
        receipt = raw;
      }
    } catch (_) {
      if (current(t)) error = 'Request could not be confirmed. Restore or retry its original identity after checking MFA, destination review and version.';
    } finally {
      if (current(t)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    dead = true;
    epoch++;
    pending = null;
    receipt = null;
    super.dispose();
  }
}

class _IntegrationActions extends StatefulWidget {
  const _IntegrationActions({super.key, required this.controller});
  final IntegrationController controller;
  @override
  State<_IntegrationActions> createState() => _IntegrationActionsState();
}

class _IntegrationActionsState extends State<_IntegrationActions> {
  final url = TextEditingController(),
      keyRef = TextEditingController(),
      id = TextEditingController(),
      version = TextEditingController(text: '0'),
      delivery = TextEditingController(),
      reason = TextEditingController(),
      credential = TextEditingController(),
      digest = TextEditingController(),
      starts = TextEditingController(),
      expires = TextEditingController();
  String decision = 'not_sent';
  void selectSubscription(Map<String, Object?> row) {
    if (!widget.controller.online ||
        widget.controller.busy ||
        widget.controller.pending != null) {
      return;
    }
    id.text = row['id'] as String;
    version.text = row['version'] as String;
    url.text = row['url'] as String;
    keyRef.clear();
  }

  void selectDelivery(String value) {
    if (!widget.controller.online ||
        widget.controller.busy ||
        widget.controller.pending != null) {
      return;
    }
    delivery.text = value;
    reason.clear();
  }

  @override
  void didUpdateWidget(covariant _IntegrationActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    for (final c in [
      url,
      keyRef,
      id,
      version,
      delivery,
      reason,
      credential,
      digest,
      starts,
      expires,
    ]) {
      c.clear();
    }
    version.text = '0';
    decision = 'not_sent';
  }

  @override
  void dispose() {
    for (final c in [
      url,
      keyRef,
      id,
      version,
      delivery,
      reason,
      credential,
      digest,
      starts,
      expires,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: url,
            decoration: const InputDecoration(
              labelText: 'Reviewed HTTPS destination',
            ),
            maxLength: 2048,
          ),
          TextField(
            controller: keyRef,
            decoration: const InputDecoration(
              labelText: 'Provisioned server vault reference',
            ),
            maxLength: 180,
          ),
          TextField(
            controller: id,
            decoration: const InputDecoration(
              labelText: 'Subscription ID for rotation/revocation',
            ),
          ),
          TextField(
            controller: version,
            decoration: const InputDecoration(
              labelText: 'Expected subscription revision',
            ),
          ),
          Wrap(
            spacing: 12,
            children: [
              FilledButton(
                onPressed: c.online && !c.busy && c.pending == null
                    ? () => c.submit('register', {
                        'id': const Uuid().v4(),
                        'url': url.text,
                        'keyRef': keyRef.text,
                        'expectedVersion': '0',
                      })
                    : null,
                child: const Text('Register subscription'),
              ),
              TextButton(
                onPressed: c.online && !c.busy && c.pending == null
                    ? () => c.submit('rotate', {
                        'id': id.text,
                        'keyRef': keyRef.text,
                        'expectedVersion': version.text,
                      })
                    : null,
                child: const Text('Rotate vault reference'),
              ),
              TextButton(
                onPressed: c.online && !c.busy && c.pending == null
                    ? () => c.submit('revoke', {
                        'id': id.text,
                        'expectedVersion': version.text,
                      })
                    : null,
                child: const Text('Revoke subscription'),
              ),
            ],
          ),
          TextField(
            controller: delivery,
            decoration: const InputDecoration(
              labelText: 'Delivery ID for reviewed reconciliation',
            ),
          ),
          const Divider(height: 32),
          const Text('Scoped external command credentials'),
          const Text(
            'A reviewed server provisions the random credential. Enter its digest and effective dates here; the raw credential stays in server custody.',
          ),
          TextField(
            controller: credential,
            decoration: const InputDecoration(labelText: 'Credential ID'),
          ),
          TextField(
            controller: digest,
            decoration: const InputDecoration(
              labelText: 'Reviewed server SHA256 credential digest',
            ),
          ),
          TextField(
            controller: starts,
            decoration: const InputDecoration(
              labelText: 'Credential starts at (UTC)',
            ),
          ),
          TextField(
            controller: expires,
            decoration: const InputDecoration(
              labelText: 'Credential expires at (UTC)',
            ),
          ),
          Wrap(
            spacing: 12,
            children: [
              TextButton(
                onPressed: c.online && !c.busy && c.pending == null
                    ? () => c.submit('credential_register', {
                        'id': credential.text,
                        'tokenHash': digest.text,
                        'startsAt': starts.text,
                        'expiresAt': expires.text,
                      })
                    : null,
                child: const Text('Register reviewed credential digest'),
              ),
              TextButton(
                onPressed: c.online && !c.busy && c.pending == null
                    ? () =>
                          c.submit('credential_revoke', {'id': credential.text})
                    : null,
                child: const Text('Revoke scoped credential'),
              ),
            ],
          ),
          const Divider(height: 32),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: decision,
            items: const [
              DropdownMenuItem(
                value: 'not_sent',
                child: Text('Receiver confirmed no send'),
              ),
              DropdownMenuItem(
                value: 'acknowledged',
                child: Text('Receiver confirmed acknowledgement'),
              ),
              DropdownMenuItem(
                value: 'replay',
                child: Text('Reviewed dead-letter replay'),
              ),
            ],
            onChanged: (v) => setState(() => decision = v!),
          ),
          TextField(
            controller: reason,
            decoration: const InputDecoration(
              labelText: 'Review reason and receiver evidence',
            ),
            maxLength: 500,
          ),
          TextButton(
            onPressed: c.online && !c.busy && c.pending == null
                ? () => c.submit('review', {
                    'deliveryId': delivery.text,
                    'decision': decision,
                    'reason': reason.text,
                  })
                : null,
            child: const Text('Record MFA review'),
          ),
          if (c.busy) const LinearProgressIndicator(),
          if (c.error != null) Text(c.error!),
          if (c.receipt != null)
            SelectableText(
              'Confirmed receipt: ${c.receipt!['id']} · ${c.receipt!['version'] ?? c.receipt!['state']}',
            ),
          Wrap(
            spacing: 12,
            children: [
              TextButton(
                onPressed: c.online && !c.busy ? c.restore : null,
                child: const Text('Restore encrypted request'),
              ),
              TextButton(
                onPressed: c.online && !c.busy && c.pending != null
                    ? c.retry
                    : null,
                child: const Text('Retry original request'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
