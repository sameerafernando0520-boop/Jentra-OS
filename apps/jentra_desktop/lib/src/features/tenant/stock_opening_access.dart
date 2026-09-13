import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:uuid/uuid.dart';
import '../../app_providers.dart';

class StockOpeningInviteButton extends ConsumerWidget {
  const StockOpeningInviteButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps =
        ref.watch(businessCapabilitiesProvider).value ?? const <String>{};
    final scope = ref.watch(businessScopeProvider).value;
    final actor = ref.watch(authenticatedActorProvider);
    if (!caps.contains('core.roles.manage') ||
        !caps.contains('core.members.invite') ||
        scope?.branch == null ||
        actor.isLoading ||
        actor.hasError ||
        actor.value == null ||
        ref.watch(stockOpeningAccessGatewayProvider) == null) {
      return const SizedBox.shrink();
    }
    return IconButton(
      tooltip: 'Invite stock opening approver',
      icon: const Icon(Icons.person_add_alt_1_outlined),
      onPressed: () => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const StockOpeningInviteDialog(),
      ),
    );
  }
}

class StockOpeningInviteDialog extends ConsumerStatefulWidget {
  const StockOpeningInviteDialog({super.key});
  @override
  ConsumerState<StockOpeningInviteDialog> createState() => _InviteState();
}

class _InviteState extends ConsumerState<StockOpeningInviteDialog> {
  final _email = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _key = const Uuid().v4();
  late final _scope = ref.read(businessScopeProvider).requireValue;
  late final _actor = ref.read(authenticatedActorProvider).value;
  String? _submittedEmail, _error;
  Map<String, Object?>? _result;
  bool _busy = false;
  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
    if (_busy || !_form.currentState!.validate()) return;
    final scope = ref.read(businessScopeProvider).value;
    if (ref.read(authenticatedActorProvider).value != _actor ||
        scope?.tenantId != _scope.tenantId ||
        scope?.legalEntityId != _scope.legalEntityId ||
        scope?.branchId != _scope.branchId) {
      return;
    }
    _submittedEmail ??= _email.text.trim().toLowerCase();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(stockOpeningAccessGatewayProvider)!
          .invite(
            tenantId: _scope.tenantId,
            legalEntityId: _scope.legalEntityId!,
            branchId: _scope.branchId!,
            email: _submittedEmail!,
            idempotencyKey: _key,
          );
      if (mounted && ref.read(authenticatedActorProvider).value == _actor) {
        setState(() => _result = result);
      }
    } on StockOpeningAccessFailure catch (error) {
      if (mounted && ref.read(authenticatedActorProvider).value == _actor) {
        setState(() => _error = error.message);
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'Invitation was not confirmed. Retry this same request. The server may have already accepted it.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(businessScopeProvider).value;
    final caps =
        ref.watch(businessCapabilitiesProvider).value ?? const <String>{};
    final valid =
        ref.watch(authenticatedActorProvider).value == _actor &&
        scope?.tenantId == _scope.tenantId &&
        scope?.legalEntityId == _scope.legalEntityId &&
        scope?.branchId == _scope.branchId &&
        caps.contains('core.roles.manage') &&
        caps.contains('core.members.invite');
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Invite stock opening approver'),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_scope.tenant.name}\n${_scope.legalEntity!.name} / ${_scope.branch!.name}',
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'This role can review stock-opening values and make approval decisions in this branch. MFA is required. The preparer cannot approve their own opening.',
                  ),
                  const SizedBox(height: 16),
                  if (!valid)
                    const Text(
                      'Account, permissions or business scope changed. Close this form and reopen it.',
                    ),
                  if (valid && _result == null)
                    TextFormField(
                      controller: _email,
                      readOnly: _submittedEmail != null || _busy,
                      decoration: const InputDecoration(
                        labelText: 'Approver email',
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) =>
                          RegExp(
                            r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                          ).hasMatch(value?.trim() ?? '')
                          ? null
                          : 'Enter a valid email address.',
                    ),
                  if (valid && _result != null) ...[
                    Text(
                      'Invitation created for $_submittedEmail. The recipient can sign in and accept it from their command centre.',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Approval role ID for the stock-opening approval matrix:',
                    ),
                    SelectableText(
                      ((_result!['entity'] as Map)['role_id']).toString(),
                    ),
                  ],
                  if (valid && _error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          if (valid && _result == null)
            JentraPrimaryButton(
              label: _submittedEmail == null
                  ? 'Create invitation'
                  : 'Retry invitation',
              loading: _busy,
              onPressed: _busy ? null : _invite,
            ),
        ],
      ),
    );
  }
}

class StockOpeningInvitationInbox extends ConsumerStatefulWidget {
  const StockOpeningInvitationInbox({super.key});
  @override
  ConsumerState<StockOpeningInvitationInbox> createState() => _InboxState();
}

class _InboxState extends ConsumerState<StockOpeningInvitationInbox> {
  final _keys = <String, String>{};
  String? _busy, _error;
  Future<void> _accept(String id) async {
    if (_busy != null) return;
    final actor = ref.read(authenticatedActorProvider).value;
    setState(() {
      _busy = id;
      _error = null;
    });
    try {
      await ref
          .read(stockOpeningAccessGatewayProvider)!
          .accept(
            invitationId: id,
            idempotencyKey: _keys.putIfAbsent(
              '$actor:$id',
              () => const Uuid().v4(),
            ),
          );
      if (mounted && actor == ref.read(authenticatedActorProvider).value) {
        ref.invalidate(stockOpeningInvitationsProvider);
        ref.invalidate(tenantListProvider);
        ref.invalidate(businessScopeProvider);
        ref.invalidate(businessCapabilitiesProvider);
      }
    } on StockOpeningAccessFailure catch (error) {
      if (mounted && actor == ref.read(authenticatedActorProvider).value) {
        setState(() => _error = error.message);
      }
    } on Object {
      if (mounted && actor == ref.read(authenticatedActorProvider).value) {
        setState(
          () => _error =
              'Acceptance was not confirmed. Retry the same invitation.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invitations = ref.watch(stockOpeningInvitationsProvider);
    return invitations.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => TextButton(
        onPressed: () => ref.invalidate(stockOpeningInvitationsProvider),
        child: const Text('Retry workspace invitations'),
      ),
      data: (items) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: JentraPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Invitation to ${item['tenant_name']}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${item['legal_entity_name']} / ${item['branch_name']}\nStock opening approver · MFA required for approvals',
                    ),
                    const SizedBox(height: 12),
                    JentraPrimaryButton(
                      label: 'Accept stock opening invitation',
                      loading: _busy == item['id'],
                      onPressed: _busy != null
                          ? null
                          : () => _accept(item['id']! as String),
                    ),
                    if (_error != null) Text(_error!),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
