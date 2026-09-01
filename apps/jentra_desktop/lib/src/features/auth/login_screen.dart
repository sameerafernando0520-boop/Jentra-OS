import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

import '../../app_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(foundationGatewayProvider)!
          .signInWithPassword(
            email: _email.text.trim(),
            password: _password.text,
          );
      if (mounted) {
        final redirect = GoRouterState.of(
          context,
        ).uri.queryParameters['redirect'];
        context.go(redirect ?? '/dashboard');
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Sign-in failed. Check your details and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Row(
      children: [
        Expanded(
          flex: 11,
          child: Container(
            color: JentraColors.navy900,
            padding: const EdgeInsets.all(JentraSpacing.x12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _LoginBrand(),
                const Spacer(),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your business,\nworking as one.',
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(
                              color: Colors.white,
                              fontSize: 42,
                              height: 1.12,
                            ),
                      ),
                      const SizedBox(height: JentraSpacing.x5),
                      Text(
                        'Operate revenue, stock, finance, people and service from one governed command centre.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: JentraColors.darkTextSecondary,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                const Text(
                  'Development workspace • Mumbai region • Synthetic data only',
                  style: TextStyle(color: JentraColors.darkTextSecondary),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 9,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(JentraSpacing.x12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 410),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Welcome back',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: JentraSpacing.x2),
                      Text(
                        'Sign in to continue to Jentra OS.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: context.jentraColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: JentraSpacing.x8),
                      TextField(
                        controller: _email,
                        autofillHints: const [AutofillHints.email],
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Work email',
                          prefixIcon: Icon(Icons.alternate_email),
                        ),
                      ),
                      const SizedBox(height: JentraSpacing.x4),
                      TextField(
                        controller: _password,
                        autofillHints: const [AutofillHints.password],
                        obscureText: true,
                        onSubmitted: (_) => _signIn(),
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                      if (_error case final error?) ...[
                        const SizedBox(height: JentraSpacing.x3),
                        JentraStatusBadge(
                          label: error,
                          tone: JentraStatusTone.danger,
                        ),
                      ],
                      const SizedBox(height: JentraSpacing.x5),
                      JentraPrimaryButton(
                        label: 'Sign in securely',
                        icon: Icons.arrow_forward,
                        loading: _busy,
                        onPressed: _busy ? null : _signIn,
                      ),
                      const SizedBox(height: JentraSpacing.x4),
                      OutlinedButton.icon(
                        onPressed: () => ref
                            .read(foundationGatewayProvider)!
                            .signInWithGoogle(),
                        icon: const Icon(Icons.language, size: 18),
                        label: const Text('Continue with Google'),
                      ),
                      const SizedBox(height: JentraSpacing.x6),
                      const Divider(),
                      const SizedBox(height: JentraSpacing.x4),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.verified_user_outlined, size: 16),
                          SizedBox(width: JentraSpacing.x2),
                          Text('Privileged access requires MFA'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _LoginBrand extends StatelessWidget {
  const _LoginBrand();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      _BrandTile(),
      SizedBox(width: JentraSpacing.x3),
      Text(
        'JENTRA OS',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
    ],
  );
}

class _BrandTile extends StatelessWidget {
  const _BrandTile();

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: JentraColors.green500,
      borderRadius: BorderRadius.circular(9),
    ),
    child: const Text(
      'J',
      style: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
