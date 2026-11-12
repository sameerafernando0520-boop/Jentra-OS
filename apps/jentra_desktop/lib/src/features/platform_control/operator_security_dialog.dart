import 'package:flutter/material.dart';
import 'package:jentra_platform/jentra_platform.dart';

import '../auth/account_security_screen.dart';

enum _SecurityAction { setPassword, changePassword, recoveryEmail, verifyEmail }

Future<void> showOperatorSecurityDialog(
  BuildContext context, {
  required SupabaseFoundationGateway foundation,
  required PlatformOrganizationGateway gateway,
}) async {
  final actor = foundation.currentUser?.id;
  if (actor == null) return;
  final profile = gateway.identity('operator_profile', {});
  final selected = await showDialog<(_SecurityAction, String?)>(
    context: context,
    builder: (dialogContext) => FutureBuilder(
      future: profile,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final ready = data is Map && data['has_password'] is bool;
        final recovery = ready && data['recovery_verified'] == true
            ? data['recovery_email'] as String?
            : null;
        final pending = ready
            ? data['pending_recovery_email'] as String?
            : null;
        final hasPassword = ready && data['has_password'] == true;
        void select(_SecurityAction action, [String? address]) =>
            Navigator.of(dialogContext).pop((action, address));

        return AlertDialog(
          title: const Text('J panel account security'),
          scrollable: true,
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (snapshot.connectionState != ConnectionState.done)
                  const LinearProgressIndicator()
                else if (!ready)
                  const Text('Could not load your operator account. Try again.')
                else ...[
                  FilledButton(
                    onPressed: () => select(
                      hasPassword
                          ? _SecurityAction.changePassword
                          : _SecurityAction.setPassword,
                    ),
                    child: Text(
                      hasPassword ? 'Change password' : 'Set password',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Recovery email',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (recovery != null)
                    SelectableText(recovery)
                  else
                    const Text(
                      'Add a verified address to receive password reset codes.',
                    ),
                  if (hasPassword)
                    OutlinedButton(
                      onPressed: () => select(_SecurityAction.recoveryEmail),
                      child: Text(
                        recovery == null
                            ? 'Add recovery email'
                            : 'Change recovery email',
                      ),
                    ),
                  if (pending != null) ...[
                    Text('Awaiting verification for $pending'),
                    TextButton(
                      onPressed: () =>
                          select(_SecurityAction.verifyEmail, pending),
                      child: const Text('Enter verification code'),
                    ),
                  ],
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    ),
  );
  if (!context.mounted ||
      selected == null ||
      foundation.currentUser?.id != actor) {
    return;
  }
  final (action, pending) = selected;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AccountUpdateDialog(
      gateway: foundation,
      operatorGateway: gateway,
      changePassword:
          action == _SecurityAction.setPassword ||
          action == _SecurityAction.changePassword,
      setFirstPassword: action == _SecurityAction.setPassword,
      pendingRecoveryEmail: pending,
    ),
  );
}
