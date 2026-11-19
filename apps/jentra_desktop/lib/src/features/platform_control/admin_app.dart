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
    final form = gateway == null
        ? const Text(
            'Open the J panel build configured for your internal Supabase project.',
          )
        : _OperatorSignIn(gateway: gateway, operator: operator);
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 960;
          final card = Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(JentraSpacing.x6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!wide) ...[
                      const _PanelTitle(),
                      const SizedBox(height: JentraSpacing.x6),
                    ],
                    JentraPanel(
                      padding: const EdgeInsets.all(JentraSpacing.x8),
                      child: form,
                    ),
                    const SizedBox(height: JentraSpacing.x4),
                    Text(
                      'Internal use only. Not for customers.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: JentraColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          );
          if (!wide) return card;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(flex: 5, child: _BrandPane()),
              Expanded(flex: 6, child: card),
            ],
          );
        },
      ),
    );
  }
}

/// Brand mark with the product name, used above the form on narrow windows.
class _PanelTitle extends StatelessWidget {
  const _PanelTitle({this.inverse = false});

  final bool inverse;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final secondary = inverse
        ? JentraColors.darkTextSecondary
        : JentraColors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        JentraBrandMark(size: 44, inverse: inverse),
        const SizedBox(width: JentraSpacing.x3),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'J panel',
              style: text.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: inverse ? JentraColors.darkTextPrimary : null,
              ),
            ),
            Text(
              'Jentra OS control panel',
              style: text.bodyMedium?.copyWith(color: secondary),
            ),
          ],
        ),
      ],
    );
  }
}

/// The navy brand side of the wide sign-in layout.
class _BrandPane extends StatelessWidget {
  const _BrandPane();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget point(IconData icon, String label) => Padding(
      padding: const EdgeInsets.only(bottom: JentraSpacing.x4),
      child: Row(
        children: [
          Icon(icon, color: JentraColors.blue400),
          const SizedBox(width: JentraSpacing.x3),
          Expanded(
            child: Text(
              label,
              style: text.bodyLarge?.copyWith(
                color: JentraColors.darkTextPrimary,
              ),
            ),
          ),
        ],
      ),
    );
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: JentraColors.brandGradient),
      child: Padding(
        padding: const EdgeInsets.all(JentraSpacing.x12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PanelTitle(inverse: true),
            const Spacer(),
            Text(
              'Run every Jentra OS system from one place.',
              style: text.headlineMedium?.copyWith(
                color: JentraColors.darkTextPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: JentraSpacing.x6),
            point(Icons.add_business_outlined, 'Create and activate systems'),
            point(Icons.inventory_2_outlined, 'Manage packages and modules'),
            point(Icons.receipt_long_outlined, 'Verify subscription payments'),
            point(Icons.archive_outlined, 'Back up and archive organizations'),
            const Spacer(),
            Text(
              'Every action is checked on the server and needs your authenticator.',
              style: text.bodySmall?.copyWith(
                color: JentraColors.darkTextSecondary,
              ),
            ),
          ],
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
  bool _showPassword = false;
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
        setState(() {
          _busy = false;
          _showPassword = false;
        });
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
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: JentraSpacing.x2),
        Text(
          'Sign in with your platform operator email. You confirm with your authenticator app next.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: JentraColors.textSecondary),
        ),
        const SizedBox(height: JentraSpacing.x6),
        TextFormField(
          controller: _email,
          enabled: !_busy,
          decoration: const InputDecoration(
            labelText: 'Operator email',
            prefixIcon: Icon(Icons.alternate_email),
          ),
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
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              tooltip: _showPassword ? 'Hide password' : 'Show password',
              onPressed: () => setState(() => _showPassword = !_showPassword),
              icon: Icon(
                _showPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          ),
          obscureText: !_showPassword,
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
