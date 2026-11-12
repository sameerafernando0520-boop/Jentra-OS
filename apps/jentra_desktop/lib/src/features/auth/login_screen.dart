import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_platform/jentra_platform.dart';

import '../../app_providers.dart';
import 'password_reset_dialog.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.googleSignIn});

  /// Hosts may supply the browser action. The normal desktop uses the
  /// foundation gateway's private PKCE return channel.
  final Future<bool> Function()? googleSignIn;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _passwordFocus = FocusNode();
  final _confirmationFocus = FocusNode();
  bool _creatingAccount = false;
  bool _showPassword = false;
  bool _busy = false;
  bool _googlePending = false;
  bool _resetOpen = false;
  String? _error;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    _passwordFocus.dispose();
    _confirmationFocus.dispose();
    super.dispose();
  }

  void _changeMode() {
    if (_busy) return;
    _form.currentState?.reset();
    _password.clear();
    _confirmation.clear();
    setState(() {
      _creatingAccount = !_creatingAccount;
      _showPassword = false;
      _error = null;
      _message = null;
    });
  }

  String? _validateEmail(String? value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value?.trim() ?? '')
      ? null
      : 'Enter a valid email address.';

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Enter your password.';
    if (_creatingAccount && value.length < 8) {
      return 'Use at least 8 characters.';
    }
    return null;
  }

  void _goToWorkspace() {
    final redirect = GoRouterState.of(context).uri.queryParameters['redirect'];
    context.go(redirect ?? '/dashboard');
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    final gateway = ref.read(foundationGatewayProvider);
    if (gateway == null) {
      setState(() => _error = 'Open the connected build to use an account.');
      return;
    }
    final creatingAccount = _creatingAccount;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      if (creatingAccount) {
        final response = await gateway.createAccount(
          email: _email.text.trim(),
          password: _password.text,
        );
        if (!mounted) return;
        final registeredEmail = _email.text.trim();
        _form.currentState?.reset();
        _email.text = registeredEmail;
        _password.clear();
        _confirmation.clear();
        setState(() {
          _creatingAccount = false;
          _message =
              'If this address can be registered, check your email and '
              'confirm your address, then return here to sign in.';
        });
        // Confirmation-disabled projects can return a session. Navigation does
        // not create business memberships, roles or entitlements.
        if (response.session != null) _goToWorkspace();
      } else {
        await gateway.signInWithAccountLogin(
          login: _email.text,
          password: _password.text,
        );
        if (mounted) _goToWorkspace();
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = creatingAccount
              ? 'Account creation could not complete. Check your details and '
                    'try again. If you already have an account, sign in.'
              : 'Sign-in failed. Check your details and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final gateway = ref.read(foundationGatewayProvider);
    if (gateway == null) {
      setState(() => _error = 'Open the connected build to reset a password.');
      return;
    }
    _password.clear();
    setState(() {
      _busy = true;
      _resetOpen = true;
      _error = null;
      _message = null;
    });
    try {
      final login = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PasswordResetDialog(
          gateway: gateway,
          initialLogin: _email.text.trim(),
        ),
      );
      if (!mounted || login == null) return;
      _email.text = login;
      setState(
        () => _message = 'Password reset. Sign in with your new password.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _resetOpen = false;
        });
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_busy) return;
    final gateway = ref.read(foundationGatewayProvider);
    final action = widget.googleSignIn ?? gateway?.signInWithGoogle;
    if (action == null) {
      setState(() => _error = 'Open the connected build to use an account.');
      return;
    }
    setState(() {
      _busy = true;
      _googlePending = true;
      _error = null;
      _message =
          'Choose your Google account in the browser. Return to this '
          'window after completing sign-in.';
    });
    try {
      final launched = await action();
      if (!mounted) return;
      if (!launched) {
        setState(() {
          _message = null;
          _error =
              'The browser could not open. Check your default browser '
              'and try Google sign-in again.';
        });
      } else if (gateway?.currentUser != null) {
        _password.clear();
        _confirmation.clear();
        _goToWorkspace();
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _message = null;
          _error =
              'Google sign-in timed out. Try again and complete the '
              'browser steps. Your administrator may need to enable Google '
              'sign-in and the Windows callback.';
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _message = null;
          _error =
              'Google sign-in could not complete. Google must be enabled '
              'for this workspace, with the Windows callback allowed. Ask '
              'your administrator to check those settings, then try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _googlePending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;
        final form = Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(
              wide ? JentraSpacing.x12 : JentraSpacing.x6,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 410),
              child: AutofillGroup(
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!wide) ...[
                        const JentraBrandLockup(size: 44, showTagline: true),
                        const SizedBox(height: JentraSpacing.x8),
                      ],
                      Text(
                        _creatingAccount
                            ? 'Create your account'
                            : 'Welcome back',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: JentraSpacing.x2),
                      Text(
                        _creatingAccount
                            ? 'Register with your email or continue with Google.'
                            : 'Sign in to continue to Jentra OS.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: context.jentraColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: JentraSpacing.x6),
                      TextFormField(
                        key: const ValueKey('login-email'),
                        controller: _email,
                        enabled: !_busy,
                        autofillHints: [
                          _creatingAccount
                              ? AutofillHints.email
                              : AutofillHints.username,
                        ],
                        keyboardType: _creatingAccount
                            ? TextInputType.emailAddress
                            : TextInputType.text,
                        textInputAction: TextInputAction.next,
                        validator: _creatingAccount
                            ? _validateEmail
                            : (value) => isAccountLogin(value ?? '')
                                  ? null
                                  : 'Enter your username or email address.',
                        onFieldSubmitted: (_) {
                          if (!_busy) _passwordFocus.requestFocus();
                        },
                        decoration: InputDecoration(
                          labelText: _creatingAccount
                              ? 'Work email'
                              : 'Username or email',
                          prefixIcon: const Icon(Icons.alternate_email),
                        ),
                      ),
                      const SizedBox(height: JentraSpacing.x4),
                      TextFormField(
                        key: const ValueKey('login-password'),
                        controller: _password,
                        focusNode: _passwordFocus,
                        enabled: !_busy,
                        autofillHints: [
                          _creatingAccount
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        obscureText: !_showPassword,
                        textInputAction: _creatingAccount
                            ? TextInputAction.next
                            : TextInputAction.done,
                        validator: _validatePassword,
                        onFieldSubmitted: (_) {
                          if (_busy) return;
                          if (_creatingAccount) {
                            _confirmationFocus.requestFocus();
                          } else {
                            _submit();
                          }
                        },
                        decoration: InputDecoration(
                          labelText: 'Password',
                          helperText: _creatingAccount
                              ? 'Use at least 8 characters.'
                              : null,
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _password,
                            builder: (context, value, child) => Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (value.text.isNotEmpty)
                                  IconButton(
                                    tooltip: 'Clear password',
                                    onPressed: _busy
                                        ? null
                                        : () {
                                            _password.clear();
                                            setState(() {
                                              _showPassword = false;
                                              _error = null;
                                            });
                                            _passwordFocus.requestFocus();
                                          },
                                    icon: const Icon(Icons.clear),
                                  ),
                                child!,
                              ],
                            ),
                            child: IconButton(
                              tooltip: _showPassword
                                  ? 'Hide password'
                                  : 'Show password',
                              onPressed: _busy
                                  ? null
                                  : () {
                                      setState(
                                        () => _showPassword = !_showPassword,
                                      );
                                      _passwordFocus.requestFocus();
                                    },
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_creatingAccount) ...[
                        const SizedBox(height: JentraSpacing.x4),
                        TextFormField(
                          key: const ValueKey('login-confirmation'),
                          controller: _confirmation,
                          focusNode: _confirmationFocus,
                          enabled: !_busy,
                          autofillHints: const [AutofillHints.newPassword],
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          validator: (value) => value == _password.text
                              ? null
                              : 'The passwords must match.',
                          onFieldSubmitted: (_) => _submit(),
                          decoration: const InputDecoration(
                            labelText: 'Confirm password',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                        ),
                      ],
                      if (_error case final error?) ...[
                        const SizedBox(height: JentraSpacing.x3),
                        _AuthNotice(message: error, error: true),
                      ],
                      if (_message case final message?) ...[
                        const SizedBox(height: JentraSpacing.x3),
                        _AuthNotice(message: message),
                      ],
                      const SizedBox(height: JentraSpacing.x5),
                      JentraPrimaryButton(
                        key: const ValueKey('login-submit'),
                        label: _creatingAccount
                            ? 'Create account'
                            : 'Sign in securely',
                        icon: Icons.arrow_forward,
                        loading: _busy && !_googlePending && !_resetOpen,
                        onPressed: _busy ? null : _submit,
                      ),
                      if (!_creatingAccount)
                        TextButton(
                          key: const ValueKey('login-forgot-password'),
                          onPressed: _busy ? null : _forgotPassword,
                          child: const Text('Forgot password?'),
                        ),
                      const SizedBox(height: JentraSpacing.x4),
                      OutlinedButton.icon(
                        key: const ValueKey('login-google'),
                        onPressed: _busy ? null : _signInWithGoogle,
                        icon: _googlePending
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.language, size: 18),
                        label: Text(
                          _googlePending
                              ? 'Waiting for Google…'
                              : 'Continue with Google',
                        ),
                      ),
                      const SizedBox(height: JentraSpacing.x2),
                      TextButton(
                        key: const ValueKey('login-change-mode'),
                        onPressed: _busy ? null : _changeMode,
                        child: Text(
                          _creatingAccount
                              ? 'Back to sign in'
                              : 'Create an account',
                        ),
                      ),
                      const SizedBox(height: JentraSpacing.x2),
                      Text(
                        'New accounts need a business invitation or business '
                        'setup before accessing workspaces.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.jentraColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        if (!wide) return form;
        return Row(
          children: [
            Expanded(
              flex: 11,
              child: Container(
                color: JentraColors.navy900,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(JentraSpacing.x12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: (constraints.maxHeight - JentraSpacing.x12 * 2)
                          .clamp(0, double.infinity)
                          .toDouble(),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _LoginBrand(),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: JentraSpacing.x8,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Your business,\nworking as one.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineLarge
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontSize: 42,
                                        height: 1.12,
                                      ),
                                ),
                                const SizedBox(height: JentraSpacing.x5),
                                Text(
                                  'Operate revenue, stock, finance, people and '
                                  'service from one governed command centre.',
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(
                                        color: JentraColors.darkTextSecondary,
                                        fontSize: 16,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Text(
                          'Development workspace • Mumbai region • Synthetic '
                          'data only',
                          style: TextStyle(
                            color: JentraColors.darkTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(flex: 9, child: form),
          ],
        );
      },
    ),
  );
}

class _AuthNotice extends StatelessWidget {
  const _AuthNotice({required this.message, this.error = false});
  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: error
            ? context.jentraColors.dangerSurface
            : context.jentraColors.infoSurface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(JentraSpacing.x3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              error ? Icons.error_outline : Icons.info_outline,
              size: 18,
              color: error
                  ? context.jentraColors.danger
                  : context.jentraColors.info,
            ),
            const SizedBox(width: JentraSpacing.x2),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
}

class _LoginBrand extends StatelessWidget {
  const _LoginBrand();

  @override
  Widget build(BuildContext context) =>
      const JentraBrandLockup(size: 52, inverse: true, showTagline: true);
}
