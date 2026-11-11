import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_platform/jentra_platform.dart';

import '../../app_providers.dart';
import '../auth/password_reset_dialog.dart';
import 'platform_organization_screen.dart';

class JentraAdministratorApp extends StatelessWidget {
  const JentraAdministratorApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'J panel',
    debugShowCheckedModeBanner: false,
    theme: JentraTheme.light(),
    home: const _AdministratorHome(),
  );
}

class _AdministratorHome extends ConsumerWidget {
  const _AdministratorHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authSessionRevisionProvider);
    final gateway = ref.watch(foundationGatewayProvider);
    final operator = ref.watch(platformOrganizationGatewayProvider);
    if (gateway?.currentUser != null) {
      return const PlatformOrganizationScreen(standalone: true);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('J panel')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(JentraSpacing.x6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: JentraPanel(
              padding: const EdgeInsets.all(JentraSpacing.x8),
              child: gateway == null
                  ? const Text(
                      'Open the J panel build configured for your internal Supabase project.',
                    )
                  : _OperatorSignIn(gateway: gateway, operator: operator),
            ),
          ),
        ),
      ),
    );
  }
}

class _OperatorSignIn extends StatefulWidget {
  const _OperatorSignIn({required this.gateway, required this.operator});

  final SupabaseFoundationGateway gateway;
  final PlatformOrganizationGateway? operator;

  @override
  State<_OperatorSignIn> createState() => _OperatorSignInState();
}

class _OperatorSignInState extends State<_OperatorSignIn> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await widget.gateway.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'Sign-in failed. Check your operator email and password.',
        );
      }
    } finally {
      if (mounted) {
        _password.clear();
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _forgotPassword() async {
    final operator = widget.operator;
    if (_busy || operator == null) return;
    _password.clear();
    final login = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PasswordResetDialog.operator(
        operatorGateway: operator,
        initialLogin: _email.text.trim(),
      ),
    );
    if (!mounted || login == null) return;
    _email.text = login;
    setState(() {
      _error = null;
      _message = 'Password reset. Sign in with your new password.';
    });
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Operator sign-in',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: JentraSpacing.x2),
        const Text(
          'Use your assigned platform operator account and authenticator.',
        ),
        const SizedBox(height: JentraSpacing.x5),
        TextFormField(
          controller: _email,
          enabled: !_busy,
          decoration: const InputDecoration(labelText: 'Operator email'),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          validator: (value) => value == null || !value.trim().contains('@')
              ? 'Enter your operator email.'
              : null,
        ),
        const SizedBox(height: JentraSpacing.x4),
        TextFormField(
          controller: _password,
          enabled: !_busy,
          decoration: const InputDecoration(labelText: 'Password'),
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          onFieldSubmitted: (_) => _signIn(),
          validator: (value) =>
              value == null || value.isEmpty ? 'Enter your password.' : null,
        ),
        if (_error case final error?) ...[
          const SizedBox(height: JentraSpacing.x3),
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_message case final message?) ...[
          const SizedBox(height: JentraSpacing.x3),
          Text(message),
        ],
        const SizedBox(height: JentraSpacing.x5),
        JentraPrimaryButton(
          label: 'Sign in',
          loading: _busy,
          onPressed: _busy ? null : _signIn,
        ),
        if (widget.operator != null)
          TextButton(
            onPressed: _busy ? null : _forgotPassword,
            child: const Text('Forgot password'),
          ),
      ],
    ),
  );
}
