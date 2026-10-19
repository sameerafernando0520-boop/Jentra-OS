import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

import '../../app_providers.dart';

class AcceptInvitationScreen extends ConsumerStatefulWidget {
  const AcceptInvitationScreen({required this.token, super.key});

  final String token;

  @override
  ConsumerState<AcceptInvitationScreen> createState() =>
      _AcceptInvitationScreenState();
}

class _AcceptInvitationScreenState
    extends ConsumerState<AcceptInvitationScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _accept() async {
    final gateway = ref.read(foundationGatewayProvider);
    if (gateway == null) {
      context.go('/dashboard');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await gateway.acceptInvitation(widget.token);
      ref.invalidate(tenantListProvider);
      if (mounted) context.go('/dashboard');
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'This invitation is invalid, expired, or belongs to another email address.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: JentraPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: context.jentraColors.successSurface,
                borderRadius: BorderRadius.circular(JentraRadii.card),
              ),
              child: const Icon(
                Icons.mark_email_read_outlined,
                color: JentraColors.green700,
              ),
            ),
            const SizedBox(height: JentraSpacing.x5),
            Text(
              'Join this Jentra workspace',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: JentraSpacing.x2),
            Text(
              'Jentra will verify the signed-in email, invitation status and expiry before creating your scoped membership.',
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: context.jentraColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (_error case final error?) ...[
              const SizedBox(height: JentraSpacing.x4),
              JentraStatusBadge(label: error, tone: JentraStatusTone.danger),
            ],
            const SizedBox(height: JentraSpacing.x6),
            JentraPrimaryButton(
              label: 'Accept invitation',
              icon: Icons.arrow_forward,
              loading: _busy,
              onPressed: _busy ? null : _accept,
            ),
          ],
        ),
      ),
    ),
  );
}
