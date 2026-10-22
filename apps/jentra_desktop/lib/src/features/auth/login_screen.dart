import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_platform/jentra_platform.dart';

import '../../app_providers.dart';
import '../../shell/build_information_dialog.dart';

typedef EmailConfirmationAction = Future<void> Function({
  required String email,
  required String? password,
  required bool resend,
  required EmailConfirmationCancellation cancellation,
  required VoidCallback onEmailSent,
  required VoidCallback onExchangeStarted,
});

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({
    super.key,
    this.googleSignIn,
    this.googleSignInFlow,
    this.emailConfirmationFlow,
    this.confirmEmailLink,
  });

  final EmailConfirmationAction? emailConfirmationFlow;
  final Future<void> Function(String link)? confirmEmailLink;

  /// Hosts may supply the browser action. The normal desktop uses the
  /// foundation gateway's private PKCE return channel.
  final Future<bool> Function()? googleSignIn;

  /// Allows a host to participate in cancellation and exchange progress.
  final Future<bool> Function(
    GoogleSignInCancellation cancellation,
    void Function() onExchangeStarted,
  )?
  googleSignInFlow;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _confirmationLink = TextEditingController();
  final _passwordFocus = FocusNode();
  final _confirmationFocus = FocusNode();
  bool _creatingAccount = false;
  bool _busy = false;
  bool _googlePending = false;
  bool _googleFinishing = false;
  bool _googleCancelling = false;
  GoogleSignInCancellation? _googleCancellation;
  EmailConfirmationCancellation? _emailCancellation;
  Timer? _resendCooldown;
  bool _showEmailConfirmation = false;
  bool _showLinkRecovery = false;
  bool _emailPending = false;
  bool _emailFinishing = false;
  bool _emailCancelling = false;
  bool _resendCoolingDown = false;
  String? _error;
  String? _message;

  @override
  void dispose() {
    _googleCancellation?.cancel();
    _emailCancellation?.cancel();
    _resendCooldown?.cancel();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    _confirmationLink.dispose();
    _passwordFocus.dispose();
    _confirmationFocus.dispose();
    super.dispose();
  }

  void _changeMode() {
    if (_busy) return;
    _form.currentState?.reset();
    _password.clear();
    _confirmation.clear();
    _confirmationLink.clear();
    setState(() {
      _creatingAccount = !_creatingAccount;
      _showEmailConfirmation = false;
      _showLinkRecovery = false;
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
    if (creatingAccount) {
      await _beginEmailConfirmation(resend: false);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await gateway.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
      if (mounted) _goToWorkspace();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          if (emailConfirmationFailure(error) ==
              EmailConfirmationFailure.emailNotConfirmed) {
            _showEmailConfirmation = true;
            _error = 'Confirm your email before signing in. You can request a fresh email below.';
          } else {
            _error = 'Sign-in failed. Check your details and try again.';
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _emailError(Object error) => switch (emailConfirmationFailure(error)) {
    EmailConfirmationFailure.emailNotConfirmed => 'Confirm your email before signing in. Request a fresh email and keep Jentra OS open.',
    EmailConfirmationFailure.expired => 'This confirmation link has expired or has already been used. Try signing in, or request a fresh email.',
    EmailConfirmationFailure.invalidLink => 'Copy the original confirmation link from your email. The localhost address from the browser cannot be used here.',
    EmailConfirmationFailure.rateLimited => 'Please wait before requesting another confirmation email, then try again.',
    EmailConfirmationFailure.signupUnavailable => 'Account creation could not complete. Email registration is unavailable for this workspace. Ask your administrator to check its email settings.',
    EmailConfirmationFailure.weakPassword =>
      'Choose a stronger password and try creating the account again.',
    EmailConfirmationFailure.callbackUnavailable => 'Another Jentra sign-in window may be open. Close it and request a fresh confirmation email.',
    EmailConfirmationFailure.exchangeFailed => 'Email confirmation could not finish. Try signing in first, or request a fresh email and keep Jentra OS open.',
    EmailConfirmationFailure.alreadySignedIn =>
      'An account is already signed in. Return to your workspace.',
    EmailConfirmationFailure.cancelled => 'Waiting for email confirmation stopped. Try signing in, or request a fresh email.',
    EmailConfirmationFailure.failed => 'Account confirmation could not complete. Try signing in first, or request a fresh confirmation email.',
  };

  Future<void> _beginEmailConfirmation({required bool resend}) async {
    if (_busy || (resend && _resendCoolingDown)) return;
    if (_validateEmail(_email.text) != null) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    final gateway = ref.read(foundationGatewayProvider);
    if (gateway == null && widget.emailConfirmationFlow == null) {
      setState(() => _error = 'Open the connected build to use an account.');
      return;
    }
    final cancellation = EmailConfirmationCancellation();
    _emailCancellation = cancellation;
    final email = _email.text.trim();
    final password = resend ? null : _password.text;
    void onEmailSent() {
      if (!mounted || _emailCancellation != cancellation) return;
      _password.clear();
      _confirmation.clear();
      _resendCooldown?.cancel();
      _resendCooldown = Timer(const Duration(seconds: 60), () {
        if (mounted) setState(() => _resendCoolingDown = false);
      });
      setState(() {
        _email.text = email;
        _creatingAccount = false;
        _showEmailConfirmation = true;
        _resendCoolingDown = true;
        if (!_emailCancelling && !_emailFinishing) {
          _message = 'If this address can be registered or is awaiting confirmation, check your latest email. Keep Jentra OS open while you click its confirmation link.';
        }
      });
    }

    void onExchangeStarted() {
      if (!mounted || _emailCancellation != cancellation) return;
      setState(() {
        _emailFinishing = true;
        _message = 'Confirming your email and completing sign-in…';
      });
    }

    setState(() {
      _busy = true;
      _emailPending = true;
      _emailFinishing = false;
      _emailCancelling = false;
      _error = null;
      _message = 'Requesting your confirmation email…';
    });
    try {
      if (widget.emailConfirmationFlow case final action?) {
        await action(
          email: email,
          password: password,
          resend: resend,
          cancellation: cancellation,
          onEmailSent: onEmailSent,
          onExchangeStarted: onExchangeStarted,
        );
      } else if (resend) {
        await gateway!.resendAndConfirmEmail(
          email: email,
          cancellation: cancellation,
          onEmailSent: onEmailSent,
          onExchangeStarted: onExchangeStarted,
        );
      } else {
        await gateway!.createAccountAndConfirm(
          email: email,
          password: password!,
          cancellation: cancellation,
          onEmailSent: onEmailSent,
          onExchangeStarted: onExchangeStarted,
        );
      }
      if (mounted && gateway?.currentUser != null) _goToWorkspace();
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _message = null;
          _error = 'Waiting for confirmation timed out. Try signing in first. If needed, request a fresh email and keep Jentra OS open.';
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _message = null;
          _error = _emailError(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _emailPending = false;
          _emailFinishing = false;
          _emailCancelling = false;
          _emailCancellation = null;
        });
      }
    }
  }

  void _cancelEmailConfirmation() {
    if (!_emailPending || _emailFinishing || _emailCancelling) return;
    setState(() {
      _emailCancelling = true;
      _message = 'Stopping the confirmation wait…';
    });
    _emailCancellation?.cancel();
  }

  Future<void> _confirmFromLink() async {
    if (_busy) return;
    final gateway = ref.read(foundationGatewayProvider);
    if (gateway == null && widget.confirmEmailLink == null) {
      setState(() => _error = 'Open the connected build to use an account.');
      return;
    }
    final link = _confirmationLink.text;
    _confirmationLink.clear();
    setState(() {
      _busy = true;
      _error = null;
      _message = 'Confirming your email…';
    });
    try {
      if (widget.confirmEmailLink case final action?) {
        await action(link);
      } else {
        await gateway!.confirmEmailFromLink(link: link);
      }
      if (mounted && gateway?.currentUser != null) _goToWorkspace();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _message = null;
          _error = _emailError(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_busy) return;
    final gateway = ref.read(foundationGatewayProvider);
    if (widget.googleSignInFlow == null &&
        widget.googleSignIn == null &&
        gateway == null) {
      setState(() => _error = 'Open the connected build to use an account.');
      return;
    }
    final cancellation = GoogleSignInCancellation();
    _googleCancellation = cancellation;
    void onExchangeStarted() {
      if (!mounted || _googleCancellation != cancellation) return;
      setState(() {
        _googleFinishing = true;
        _message = 'Google has returned. Completing your secure sign-in…';
      });
    }

    setState(() {
      _busy = true;
      _googlePending = true;
      _googleFinishing = false;
      _googleCancelling = false;
      _error = null;
      _message =
          'Choose your Google account in the browser. Return to this '
          'window after completing sign-in.';
    });
    try {
      final launched = widget.googleSignInFlow != null
          ? await widget.googleSignInFlow!(cancellation, onExchangeStarted)
          : widget.googleSignIn != null
          ? await widget.googleSignIn!()
          : await gateway!.signInWithGoogle(
              cancellation: cancellation,
              onExchangeStarted: onExchangeStarted,
            );
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
    } on GoogleSignInException catch (failure) {
      if (mounted) {
        setState(() {
          if (failure.failure == GoogleSignInFailure.cancelled) {
            _error = null;
            _message = 'Google sign-in cancelled. You can try again or use your work email.';
          } else {
            _message = null;
            _error = switch (failure.failure) {
              GoogleSignInFailure.providerDisabled =>
                'Google sign-in is not available for this workspace yet. '
                    'Use your work email or ask your administrator to finish Google setup.',
              GoogleSignInFailure.settingsUnavailable => 'Could not connect to Google sign-in. Check your internet connection and try again.',
              GoogleSignInFailure.browserUnavailable => 'The browser could not open. Check your default browser and try Google sign-in again.',
              GoogleSignInFailure.callbackUnavailable ||
              GoogleSignInFailure.alreadyPending => 'Another sign-in window may be open. Close it and try Google sign-in again.',
              GoogleSignInFailure.callbackRejected => 'Google sign-in was not completed. Try again or use your work email.',
              GoogleSignInFailure.exchangeFailed => 'Google returned to the app, but sign-in could not finish. Please try again.',
              GoogleSignInFailure.cancelled => null,
            };
          }
        });
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _message = null;
          _error =
              'Google sign-in timed out. Try again and complete the '
              'browser steps. Keep Jentra OS open until sign-in finishes.';
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _message = null;
          _error = 'Google sign-in could not complete. Try again or sign in with your work email.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _googlePending = false;
          _googleFinishing = false;
          _googleCancelling = false;
          _googleCancellation = null;
        });
      }
    }
  }

  void _cancelGoogleSignIn() {
    if (!_googlePending || _googleFinishing || _googleCancelling) return;
    setState(() {
      _googleCancelling = true;
      _message = 'Cancelling Google sign-in…';
    });
    _googleCancellation?.cancel();
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
                        autofillHints: const [AutofillHints.email],
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        validator: _validateEmail,
                        onFieldSubmitted: (_) {
                          if (!_busy) _passwordFocus.requestFocus();
                        },
                        decoration: const InputDecoration(
                          labelText: 'Work email',
                          prefixIcon: Icon(Icons.alternate_email),
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
                        obscureText: true,
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
                      if (_showEmailConfirmation || _emailPending) ...[
                        const SizedBox(height: JentraSpacing.x4),
                        Text(
                          'Confirm your email',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: JentraSpacing.x2),
                        const Text(
                          'If a previous link opened an unreachable page, your email may already be confirmed. Try signing in with your email and password.',
                        ),
                        if (_emailPending) ...[
                          const SizedBox(height: JentraSpacing.x2),
                          Text(
                            _emailFinishing
                                ? 'Completing confirmation…'
                                : _emailCancelling
                                ? 'Stopping…'
                                : 'Waiting for your email confirmation…',
                          ),
                          TextButton(
                            key: const ValueKey('login-email-cancel'),
                            onPressed: _emailFinishing || _emailCancelling
                                ? null
                                : _cancelEmailConfirmation,
                            child: const Text('Stop waiting'),
                          ),
                        ],
                        OutlinedButton(
                          key: const ValueKey('login-email-resend'),
                          onPressed: _busy || _resendCoolingDown
                              ? null
                              : () => _beginEmailConfirmation(resend: true),
                          child: const Text('Resend confirmation email'),
                        ),
                        if (_resendCoolingDown)
                          const Text(
                            'Wait a minute before requesting another email.',
                          ),
                        TextButton(
                          key: const ValueKey('login-email-signin'),
                          onPressed: _busy
                              ? null
                              : () {
                                  _confirmationLink.clear();
                                  setState(() {
                                    _showEmailConfirmation = false;
                                    _showLinkRecovery = false;
                                    _error = null;
                                    _message = 'Sign in with the email and password you used to register.';
                                  });
                                  _passwordFocus.requestFocus();
                                },
                          child: const Text('Already confirmed? Sign in'),
                        ),
                        TextButton(
                          key: const ValueKey('login-email-link-help'),
                          onPressed: _busy
                              ? null
                              : () => setState(
                                  () => _showLinkRecovery = !_showLinkRecovery,
                                ),
                          child: const Text('Link won’t open?'),
                        ),
                        if (_showLinkRecovery) ...[
                          const Text(
                            'Copy the original confirmation link from the email and paste it here. Use the link from your email, not the localhost address from the browser.',
                          ),
                          const SizedBox(height: JentraSpacing.x2),
                          TextField(
                            key: const ValueKey('login-email-link'),
                            controller: _confirmationLink,
                            enabled: !_busy,
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            autofillHints: const [],
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _confirmFromLink(),
                            decoration: const InputDecoration(
                              labelText: 'Original confirmation link',
                            ),
                          ),
                          const SizedBox(height: JentraSpacing.x2),
                          OutlinedButton(
                            key: const ValueKey('login-email-link-confirm'),
                            onPressed: _busy ? null : _confirmFromLink,
                            child: const Text('Confirm email from link'),
                          ),
                        ],
                      ],
                      const SizedBox(height: JentraSpacing.x5),
                      JentraPrimaryButton(
                        key: const ValueKey('login-submit'),
                        label: _creatingAccount
                            ? 'Create account'
                            : 'Sign in securely',
                        icon: Icons.arrow_forward,
                        loading: _busy && !_googlePending && !_emailPending,
                        onPressed: _busy ? null : _submit,
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
                              ? _googleFinishing
                                    ? 'Completing sign-in…'
                                    : _googleCancelling
                                    ? 'Cancelling…'
                                    : 'Waiting for Google…'
                              : 'Continue with Google',
                        ),
                      ),
                      if (_googlePending &&
                          (widget.googleSignInFlow != null ||
                              widget.googleSignIn == null)) ...[
                        const SizedBox(height: JentraSpacing.x2),
                        TextButton(
                          key: const ValueKey('login-google-cancel'),
                          onPressed: _googleFinishing || _googleCancelling
                              ? null
                              : _cancelGoogleSignIn,
                          child: const Text('Cancel Google sign-in'),
                        ),
                      ],
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
                      if (!_creatingAccount &&
                          !_showEmailConfirmation &&
                          !_emailPending)
                        TextButton(
                          key: const ValueKey('login-email-help'),
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _showEmailConfirmation = true;
                                  _error = null;
                                  _message = null;
                                }),
                          child: const Text('Need to confirm your email?'),
                        ),
                      const SizedBox(height: JentraSpacing.x2),
                      Text(
                        'New accounts need a business invitation or business '
                        'setup before accessing workspaces.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.jentraColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: JentraSpacing.x4),
                      const Divider(),
                      const SizedBox(height: JentraSpacing.x4),
                      const Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: JentraSpacing.x2,
                        children: [
                          Icon(Icons.verified_user_outlined, size: 16),
                          Text('Privileged access requires MFA'),
                        ],
                      ),
                      const SizedBox(height: JentraSpacing.x2),
                      TextButton.icon(
                        key: const ValueKey('login-about'),
                        onPressed: () => showDesktopBuildInformation(context),
                        icon: const Icon(Icons.info_outline, size: 16),
                        label: const Text('About Jentra OS'),
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
                        Text(
                          ref.watch(runtimeConfigProvider).workspaceLabel,
                          style: const TextStyle(
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
