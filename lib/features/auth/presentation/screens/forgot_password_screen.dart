import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/auth_controller.dart';
import '../../application/auth_models.dart';
import '../../application/auth_validators.dart';
import '../widgets/auth_feedback.dart';
import '../widgets/auth_form_shell.dart';

final class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

final class _ForgotPasswordScreenState
    extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final result = await ref
        .read(authControllerProvider.notifier)
        .requestPasswordReset(email: _emailController.text);
    if (!mounted || result == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'If an account exists for that email, reset instructions were sent.',
        ),
      ),
    );
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AuthActionResult?>>(authControllerProvider, (
      previous,
      next,
    ) {
      if (next.hasError && !identical(previous?.error, next.error)) {
        AuthFeedback.showError(context, next.error);
      }
    });
    final authState = ref.watch(authControllerProvider);

    return AuthFormShell(
      title: 'Reset your password',
      subtitle: 'We will email instructions if the account exists.',
      footer: TextButton.icon(
        onPressed: authState.isLoading ? null : () => context.go('/login'),
        icon: const Icon(Icons.arrow_back),
        label: const Text('Back to sign in'),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: AuthValidators.email,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: authState.isLoading ? null : _submit,
              child: authState.isLoading
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Send reset instructions'),
            ),
          ],
        ),
      ),
    );
  }
}
