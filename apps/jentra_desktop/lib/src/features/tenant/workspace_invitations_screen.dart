import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import 'workspace_admin_controller.dart';

class WorkspaceInvitationLink extends ConsumerWidget {
  const WorkspaceInvitationLink({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(workspaceAdminGatewayProvider) == null
      ? const SizedBox.shrink()
      : TextButton.icon(
          onPressed: () => context.go('/workspace/invitations'),
          icon: const Icon(Icons.mark_email_unread_outlined),
          label: const Text('Check company invitations'),
        );
}

final workspaceInvitationsProvider =
    FutureProvider.autoDispose<Map<String, Object?>>((ref) async {
      final connectivity = ref.watch(connectivityStateProvider);
      if (connectivity.value != ConnectivityState.online) {
        return {'items': <Object?>[], 'next_cursor': null};
      }
      final actor = await ref.watch(authenticatedActorProvider.future);
      await ref.watch(authSessionRevisionProvider.future);
      final gateway = ref.watch(workspaceAdminGatewayProvider);
      if (actor == null || gateway == null) {
        return {'items': <Object?>[], 'next_cursor': null};
      }
      return gateway.myInvitations();
    });

class WorkspaceInvitationsScreen extends ConsumerStatefulWidget {
  const WorkspaceInvitationsScreen({super.key});
  @override
  ConsumerState<WorkspaceInvitationsScreen> createState() =>
      _WorkspaceInvitationsState();
}

class _WorkspaceInvitationsState
    extends ConsumerState<WorkspaceInvitationsScreen> {
  String? busy, error, message;
  Map<String, Object?>? extraPage;
  String? pageActor;
  Object? pageGateway;
  int? pageRevision;
  bool? wasOnline;
  int epoch = 0;
  bool currentAccess(String actor, Object gateway, int? revision) {
    if (!mounted || revision == null) return false;
    final session = ref.read(authSessionRevisionProvider),
        connectivity = ref.read(connectivityStateProvider),
        identity = ref.read(authenticatedActorProvider);
    return !session.isLoading &&
        !session.hasError &&
        session.value == revision &&
        !connectivity.isLoading &&
        !connectivity.hasError &&
        connectivity.value == ConnectivityState.online &&
        !identity.isLoading &&
        !identity.hasError &&
        identity.value == actor &&
        ref.read(workspaceAdminGatewayProvider) == gateway;
  }

  Future<void> accept(Map item) async {
    final gateway = ref.read(workspaceAdminGatewayProvider),
        actor = ref.read(authenticatedActorProvider).value;
    final revision = ref.read(authSessionRevisionProvider).value;
    if (gateway == null ||
        actor == null ||
        busy != null ||
        !currentAccess(actor, gateway, revision)) {
      return;
    }
    final requestEpoch = epoch;
    final id = item['id']! as String,
        key = 'workspace-invitation:$actor:${item['id']}';
    setState(() {
      busy = id;
      error = null;
      message = null;
    });
    bool current() =>
        mounted &&
        epoch == requestEpoch &&
        currentAccess(actor, gateway, revision);
    try {
      final drafts = ref.read(encryptedDraftRepositoryProvider);
      final request = await drafts.transaction(() async {
        final old = await drafts.find(key);
        if (!current()) {
          throw const FormatException('Invitation context changed.');
        }
        if (old != null &&
            (old.entityType != 'workspace.invitation.accept' ||
                old.tenantId != item['tenant_id'] ||
                old.payload['actor_id'] != actor ||
                old.payload['invitation_id'] != id)) {
          throw const FormatException('Invitation recovery scope differs.');
        }
        final request =
            old?.payload['idempotency_key'] as String? ?? const Uuid().v4();
        if (old == null) {
          await drafts.save(
            id: key,
            tenantId: item['tenant_id']! as String,
            entityType: 'workspace.invitation.accept',
            payload: {
              'actor_id': actor,
              'invitation_id': id,
              'idempotency_key': request,
            },
            localVersion: 1,
          );
        }
        return request;
      });
      if (!current()) return;
      final confirmation = await gateway.acceptInvitation(id, request);
      if (!current()) return;
      if ((confirmation['entity'] as Map?)?['tenant_id'] != item['tenant_id']) {
        throw const DomainError(
          code: 'UNCERTAIN_RESULT',
          message: 'The acceptance scope was not confirmed. Retry the original invitation.',
        );
      }
      await drafts.transaction(() async {
        final saved = await drafts.find(key);
        if (!current() ||
            saved?.payload['idempotency_key'] != request ||
            saved?.payload['actor_id'] != actor ||
            saved?.tenantId != item['tenant_id']) {
          throw const FormatException('Invitation recovery identity changed.');
        }
        await drafts.delete(key);
      });
      if (!current()) return;
      extraPage = null;
      message = 'Invitation accepted. Choose the company group from your workspace selector.';
      ref.invalidate(tenantListProvider);
      ref.invalidate(workspaceInvitationsProvider);
    } on Object catch (e) {
      if (current()) {
        setState(
          () => error = e is DomainError ? e.message : 'Acceptance was not confirmed. Refresh your workspaces and retry this invitation before starting again.',
        );
      }
    } finally {
      if (current()) setState(() => busy = null);
    }
  }

  Future<void> next(String cursor) async {
    final gateway = ref.read(workspaceAdminGatewayProvider),
        actor = ref.read(authenticatedActorProvider).value;
    final revision = ref.read(authSessionRevisionProvider).value;
    if (gateway == null ||
        actor == null ||
        busy != null ||
        !currentAccess(actor, gateway, revision)) {
      return;
    }
    final requestEpoch = epoch;
    setState(() => busy = 'page');
    try {
      final result = await gateway.myInvitations(after: cursor);
      if (mounted &&
          epoch == requestEpoch &&
          currentAccess(actor, gateway, revision)) {
        setState(() {
          extraPage = result;
          pageActor = actor;
        });
      }
    } on Object {
      if (mounted &&
          epoch == requestEpoch &&
          ref.read(authenticatedActorProvider).value == actor) {
        setState(() => error = 'The next invitation page could not be loaded.');
      }
    } finally {
      if (mounted &&
          epoch == requestEpoch &&
          ref.read(authenticatedActorProvider).value == actor) {
        setState(() => busy = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final actor = ref.watch(authenticatedActorProvider).value,
        data = ref.watch(workspaceInvitationsProvider);
    final revision = ref.watch(authSessionRevisionProvider).value,
        gateway = ref.watch(workspaceAdminGatewayProvider),
        online =
            ref.watch(connectivityStateProvider).value ==
            ConnectivityState.online;
    if (actor != pageActor ||
        revision != pageRevision ||
        gateway != pageGateway ||
        online != wasOnline) {
      extraPage = null;
      error = null;
      message = null;
      busy = null;
      pageActor = actor;
      pageRevision = revision;
      pageGateway = gateway;
      wasOnline = online;
      epoch++;
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Your company invitations',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        const Text(
          'Sign in with the verified email that received the invitation. Accepting joins that company group with the stated role and scope.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: busy != null
                  ? null
                  : () {
                      setState(() => extraPage = null);
                      ref.invalidate(workspaceInvitationsProvider);
                    },
              child: const Text('Refresh invitations'),
            ),
            TextButton(
              onPressed: () => ref.invalidate(tenantListProvider),
              child: const Text('Refresh workspaces'),
            ),
          ],
        ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (message != null) Text(message!),
        if (!online) const Text('Reconnect to view your company invitations.'),
        if (online)
          data.when(
            skipLoadingOnReload: false,
            skipLoadingOnRefresh: false,
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Invitations could not be loaded. Verify your email, access and connection, then retry.',
              ),
            ),
            data: (first) {
              final page = extraPage ?? first, items = page['items'] as List;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No pending invitations on this page.'),
                    ),
                  for (final item in items.cast<Map>())
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['tenant_name']! as String,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(item['role_name']! as String),
                            Text(
                              '${item['legal_entity_name'] ?? 'All companies'} · ${item['branch_name'] ?? 'All branches'}',
                            ),
                            const SizedBox(height: 8),
                            FilledButton(
                              onPressed: busy != null
                                  ? null
                                  : () => accept(item),
                              child: Text(
                                busy == item['id']
                                    ? 'Confirming…'
                                    : 'Accept invitation',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (page['next_cursor'] case final String cursor)
                    TextButton(
                      onPressed: busy != null ? null : () => next(cursor),
                      child: const Text('Next page'),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}
