import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/auth_controller.dart';
import '../../application/auth_models.dart';
import '../../application/auth_validators.dart';
import '../widgets/auth_feedback.dart';
import '../widgets/auth_form_shell.dart';

final class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

final class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final result = await ref
        .read(authControllerProvider.notifier)
        .login(
          email: _emailController.text,
          password: _passwordController.text,
        );
    if (mounted && result != null) context.go('/auth-gate');
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
      title: 'Welcome back',
      subtitle: 'Sign in to access your company workspace.',
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('New to Jentra OS?'),
          TextButton(
            onPressed: authState.isLoading
                ? null
                : () => context.go('/register'),
            child: const Text('Create account'),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: AuthValidators.email,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: AuthValidators.loginPassword,
              onFieldSubmitted: (_) => _submit(),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: authState.isLoading
                    ? null
                    : () => context.go('/forgot-password'),
                child: const Text('Forgot password?'),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: authState.isLoading ? null : _submit,
              child: authState.isLoading
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Sign in'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.go('/company/select'),
              icon: const Icon(Icons.explore_outlined, size: 18),
              label: const Text('Explore Demo Workspace'),
            ),
          ],
        ),
      ),
    );
  }
}
