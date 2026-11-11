import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_platform/jentra_platform.dart';

import '../../app_providers.dart';
import 'mfa_required_screen.dart';
import 'password_reset_dialog.dart';

final accountSecurityProfileProvider = FutureProvider.autoDispose
    .family<AccountSecurityProfile, String>((ref, actor) async {
      final gateway = ref.watch(foundationGatewayProvider);
      if (gateway == null || gateway.currentUser?.id != actor) {
        throw const AccountSecurityException('session_required');
      }
      return gateway.accountSecurityProfile();
    }, retry: (_, _) => null);

class AccountSecurityScreen extends ConsumerWidget {
  const AccountSecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gateway = ref.watch(foundationGatewayProvider);
    ref.watch(authenticatedActorProvider);
    final actor = gateway?.currentUser?.id;
    if (gateway == null || actor == null) {
      return const Center(child: Text('Sign in to manage your account.'));
    }
    final provider = accountSecurityProfileProvider(actor);
    final profile = ref.watch(provider);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(JentraSpacing.x6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: JentraPanel(
            padding: const EdgeInsets.all(JentraSpacing.x6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const JentraSectionHeader(title: 'Account profile'),
                const SizedBox(height: JentraSpacing.x4),
                profile.when(
                  skipLoadingOnRefresh: false,
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AuthFormError(
                        'Could not load your account profile.',
                      ),
                      TextButton(
                        onPressed: () => ref.invalidate(provider),
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                  data: (profile) => _ProfileDetails(
                    profile: profile,
                    gateway: gateway,
                    refreshProfile: () => ref.invalidate(provider),
                  ),
                ),
                const SizedBox(height: JentraSpacing.x4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                    onPressed: () => _signOut(context, gateway),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signOut(
    BuildContext context,
    SupabaseFoundationGateway gateway,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You’ll need to sign in again to open your workspace.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await gateway.signOut();
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not sign out. Please try again.'),
          ),
        );
      }
    }
  }
}

class _ProfileDetails extends ConsumerWidget {
  const _ProfileDetails({
    required this.profile,
    required this.gateway,
    required this.refreshProfile,
  });

  final AccountSecurityProfile profile;
  final SupabaseFoundationGateway gateway;
  final VoidCallback refreshProfile;

  Future<void> _editRecovery(
    BuildContext context, {
    bool resume = false,
  }) async {
    // Refresh even if the dialog closes before verification. The server may
    // already have created a pending address that the user can resume.
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AccountUpdateDialog(
        gateway: gateway,
        pendingRecoveryEmail: resume ? profile.pendingRecoveryEmail : null,
      ),
    );
    if (context.mounted) refreshProfile();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assurance = ref.watch(sessionAssuranceProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (profile.organizationLocked) ...[
          Text(
            'Workspace locked',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: JentraSpacing.x2),
          const Text(
            'Your organization’s workspace is temporarily locked. Contact your Jentra OS provider for help.',
          ),
          TextButton(
            onPressed: refreshProfile,
            child: const Text('Check again'),
          ),
          const SizedBox(height: JentraSpacing.x4),
        ],
        if (profile.username case final username?) ...[
          Text('Username', style: Theme.of(context).textTheme.labelLarge),
          SelectableText(username),
          const SizedBox(height: JentraSpacing.x4),
        ],
        if (profile.isAdministrator ||
            profile.accountKind == 'hr_manager' ||
            (profile.mustChangePassword && !profile.organizationLocked)) ...[
          Text('Password', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: JentraSpacing.x2),
          Text(
            profile.mustChangePassword
                ? 'Set your own password before opening your workspace.'
                : 'Change the password for your account.',
          ),
          const SizedBox(height: JentraSpacing.x2),
          FilledButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) =>
                  AccountUpdateDialog(gateway: gateway, changePassword: true),
            ),
            child: const Text('Change password'),
          ),
        ],
        if (profile.isAdministrator &&
            !profile.mustChangePassword &&
            !profile.organizationLocked)
          TextButton(
            onPressed: () => context.go('/account/department-accounts'),
            child: const Text('Department accounts'),
          ),
        if (!profile.mustChangePassword) ...[
          const SizedBox(height: JentraSpacing.x4),
          Text(
            'Recovery email',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: JentraSpacing.x2),
          if (profile.recoveryVerified && profile.recoveryEmail != null)
            SelectableText(profile.recoveryEmail!)
          else
            const Text(
              'Add an email address where we can send password reset codes.',
            ),
          if (profile.pendingRecoveryEmail case final pending?) ...[
            const SizedBox(height: JentraSpacing.x2),
            Text('Awaiting verification: $pending'),
          ],
          const SizedBox(height: JentraSpacing.x2),
          Wrap(
            spacing: JentraSpacing.x2,
            children: [
              OutlinedButton(
                onPressed: () => _editRecovery(context),
                child: Text(
                  profile.recoveryVerified
                      ? 'Change recovery email'
                      : 'Add recovery email',
                ),
              ),
              if (profile.pendingRecoveryEmail != null)
                TextButton(
                  onPressed: () => _editRecovery(context, resume: true),
                  child: const Text('Enter verification code'),
                ),
            ],
          ),
        ],
        if (!profile.mustChangePassword && !profile.organizationLocked) ...[
          const SizedBox(height: JentraSpacing.x4),
          if (assurance == MfaAssurance.aal2)
            const Text('This session is verified for restricted actions.')
          else
            TextButton(
              onPressed: () => context.go('/account/verify'),
              child: const Text('Verify this session for restricted actions'),
            ),
        ],
      ],
    );
  }
}

class RestrictedActionVerificationScreen extends ConsumerWidget {
  const RestrictedActionVerificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(foundationGatewayProvider)?.currentUser == null ||
        ref.watch(sessionAssuranceProvider) == MfaAssurance.aal2) {
      return Center(
        child: TextButton(
          onPressed: () => context.go('/account'),
          child: const Text('Return to account profile'),
        ),
      );
    }
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => context.go('/account'),
            child: const Text('Return to account profile'),
          ),
        ),
        const Expanded(
          child: MfaRequiredScreen(
            description: 'Verify your session to use actions that require additional approval.',
          ),
        ),
      ],
    );
  }
}

class AccountUpdateDialog extends StatefulWidget {
  const AccountUpdateDialog({
    super.key,
    required this.gateway,
    this.changePassword = false,
    this.pendingRecoveryEmail,
    this.operatorGateway,
    this.setFirstPassword = false,
  }) : assert(!setFirstPassword || (changePassword && operatorGateway != null));

  final SupabaseFoundationGateway gateway;
  final PlatformOrganizationGateway? operatorGateway;
  final bool changePassword;
  final bool setFirstPassword;
  final String? pendingRecoveryEmail;

  @override
  State<AccountUpdateDialog> createState() => _AccountUpdateDialogState();
}

class _AccountUpdateDialogState extends State<AccountUpdateDialog> {
  final _form = GlobalKey<FormState>();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmation = TextEditingController();
  final _email = TextEditingController();
  final _code = TextEditingController();
  late String? _pendingEmail = widget.pendingRecoveryEmail;
  bool _busy = false;
  bool _showCurrentPassword = false;
  bool _showNewPassword = false;
  bool _showConfirmation = false;
  String? _error;

  InputDecoration _passwordDecoration(
    String label,
    bool visible,
    VoidCallback toggle,
  ) => InputDecoration(
    labelText: label,
    suffixIcon: IconButton(
      tooltip: '${visible ? 'Hide' : 'Show'} ${label.toLowerCase()}',
      onPressed: _busy ? null : () => setState(toggle),
      icon: Icon(
        visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      ),
    ),
  );

  @override
  void dispose() {
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmation.dispose();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final operator = widget.operatorGateway;
      if (widget.changePassword) {
        final gateway = widget.gateway;
        final actor = gateway.currentUser?.id;
        if (operator == null) {
          await gateway.changeOrganizationPassword(
            currentPassword: _currentPassword.text,
            newPassword: _newPassword.text,
          );
        } else {
          await operator.identity(
            widget.setFirstPassword
                ? 'set_operator_password'
                : 'change_operator_password',
            {
              if (!widget.setFirstPassword)
                'current_password': _currentPassword.text,
              'new_password': _newPassword.text,
            },
          );
        }
        if (mounted) Navigator.of(context).pop();
        // Rotation invalidates the server session. Clear the local session
        // after closing the dialog so the sign-in redirect can run cleanly.
        if (actor != null && gateway.currentUser?.id == actor) {
          await gateway.signOut();
        }
        return;
      } else if (_pendingEmail != null) {
        if (operator == null) {
          await widget.gateway.verifyRecoveryEmail(_code.text);
        } else {
          await operator.identity('verify_operator_recovery_email', {
            'code': _code.text,
          });
        }
      } else {
        final email = _email.text.trim();
        if (operator == null) {
          await widget.gateway.requestRecoveryEmail(
            email: email,
            currentPassword: _currentPassword.text,
          );
        } else {
          await operator.identity('request_operator_recovery_email', {
            'email': email,
            'current_password': _currentPassword.text,
          });
        }
        if (!mounted) return;
        _currentPassword.clear();
        setState(() => _pendingEmail = email);
        return;
      }
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(
        () => _error = switch (accountSecurityErrorCode(error)) {
          'invalid_code' =>
            'The code is invalid or expired. Request a new code.',
          'weak_password' => organizationPasswordHint,
          'incorrect_password' => 'Your current password was not accepted.',
          'password_unchanged' =>
            'Choose a password different from your current one.',
          'invalid_email' => 'Enter a valid recovery email address.',
          'recovery_email_matches_login' =>
            'Use a recovery email different from your sign-in email.',
          'try_again_later' => 'Wait a moment before requesting another code.',
          _ => 'Could not update your account. Please try again.',
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      scrollable: true,
      title: Text(
        widget.setFirstPassword
            ? 'Set password'
            : widget.changePassword
            ? 'Change password'
            : 'Verify recovery email',
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_pendingEmail case final pending?) ...[
                Text('Enter the code sent to $pending.'),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('account-verification-code'),
                  controller: _code,
                  enabled: !_busy,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Verification code',
                  ),
                  validator: (value) =>
                      validEmailCode(value) ? null : 'Enter the 8-digit code.',
                  onFieldSubmitted: (_) => _submit(),
                ),
              ] else ...[
                Text(
                  widget.setFirstPassword
                      ? 'Sign in again after saving your password.'
                      : widget.changePassword
                      ? 'After changing your password, sign in again with the new one.'
                      : 'Your current recovery email remains in use until you verify the new address.',
                ),
                const SizedBox(height: 12),
                if (!widget.setFirstPassword) ...[
                  TextFormField(
                    key: const ValueKey('account-current-password'),
                    controller: _currentPassword,
                    enabled: !_busy,
                    autofocus: true,
                    obscureText: !_showCurrentPassword,
                    autofillHints: const [AutofillHints.password],
                    decoration: _passwordDecoration(
                      'Current password',
                      _showCurrentPassword,
                      () => _showCurrentPassword = !_showCurrentPassword,
                    ),
                    validator: (value) => value?.isNotEmpty == true
                        ? null
                        : 'Enter your current password.',
                  ),
                  const SizedBox(height: 12),
                ],
                if (widget.changePassword) ...[
                  TextFormField(
                    key: const ValueKey('account-new-password'),
                    controller: _newPassword,
                    enabled: !_busy,
                    autofocus: widget.setFirstPassword,
                    obscureText: !_showNewPassword,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: _passwordDecoration(
                      'New password',
                      _showNewPassword,
                      () => _showNewPassword = !_showNewPassword,
                    ),
                    validator: validateOrganizationPassword,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('account-confirmation'),
                    controller: _confirmation,
                    enabled: !_busy,
                    obscureText: !_showConfirmation,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: _passwordDecoration(
                      'Confirm new password',
                      _showConfirmation,
                      () => _showConfirmation = !_showConfirmation,
                    ),
                    validator: (value) => value == _newPassword.text
                        ? null
                        : 'The passwords must match.',
                    onFieldSubmitted: (_) => _submit(),
                  ),
                ] else
                  TextFormField(
                    key: const ValueKey('account-recovery-email'),
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'New recovery email',
                    ),
                    validator: (value) =>
                        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                            .hasMatch(value?.trim() ?? '')
                        ? null
                        : 'Enter a valid email address.',
                    onFieldSubmitted: (_) => _submit(),
                  ),
              ],
              if (_error case final error?) ...[
                const SizedBox(height: 12),
                AuthFormError(error),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (_pendingEmail != null)
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _email.text = _pendingEmail!;
                    _pendingEmail = null;
                    _code.clear();
                    _error = null;
                  }),
            child: const Text('Request a new code'),
          ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(
            _busy
                ? 'Please wait…'
                : widget.changePassword
                ? 'Save password'
                : _pendingEmail == null
                ? 'Send verification code'
                : 'Verify email',
          ),
        ),
      ],
    ),
  );
}
