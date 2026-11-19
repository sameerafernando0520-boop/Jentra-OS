import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jentra_platform/jentra_platform.dart';

class PasswordResetDialog extends StatefulWidget {
  const PasswordResetDialog({
    required this.gateway,
    required this.initialLogin,
    super.key,
  }) : operatorGateway = null;

  const PasswordResetDialog.operator({
    required this.operatorGateway,
    required this.initialLogin,
    super.key,
  }) : gateway = null;

  final SupabaseFoundationGateway? gateway;
  final PlatformOrganizationGateway? operatorGateway;
  final String initialLogin;

  @override
  State<PasswordResetDialog> createState() => _PasswordResetDialogState();
}

class _PasswordResetDialogState extends State<PasswordResetDialog> {
  final _form = GlobalKey<FormState>();
  late final _login = TextEditingController(text: widget.initialLogin);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  bool _codeRequested = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.operatorGateway == null && _validLogin(widget.initialLogin)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _requestCode();
      });
    }
  }

  @override
  void dispose() {
    _login.dispose();
    _code.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  bool _validLogin(String value) =>
      isAccountLogin(value) &&
      (widget.operatorGateway == null || value.contains('@'));

  Future<void> _requestCode() async {
    if (_busy || (!_codeRequested && !_form.currentState!.validate())) return;
    await _run(() async {
      final operator = widget.operatorGateway;
      if (operator != null) {
        await operator.identity('request_operator_reset', {
          'login': _login.text.trim(),
        });
      } else {
        await widget.gateway!.requestPasswordReset(_login.text);
      }
      if (!mounted) return;
      _code.clear();
      setState(() => _codeRequested = true);
    }, fallback: 'Could not request a code. Please try again.');
  }

  Future<void> _resetPassword() async {
    if (_busy || !_form.currentState!.validate()) return;
    await _run(() async {
      final login = _login.text.trim();
      final operator = widget.operatorGateway;
      if (operator != null) {
        await operator.identity('reset_operator_password', {
          'login': login,
          'code': _code.text,
          'new_password': _password.text,
        });
      } else {
        await widget.gateway!.resetPassword(
          login: login,
          code: _code.text,
          newPassword: _password.text,
        );
      }
      if (mounted) Navigator.of(context).pop(login);
    }, fallback: 'Could not reset the password. Please try again.');
  }

  Future<void> _run(
    Future<void> Function() action, {
    required String fallback,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Object catch (error) {
      if (!mounted) return;
      setState(
        () => _error = switch (accountSecurityErrorCode(error)) {
          'invalid_code' =>
            'The code is invalid or expired. Request a new code.',
          'weak_password' => organizationPasswordHint,
          _ => fallback,
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
      title: const Text('Reset your password'),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_codeRequested)
                TextFormField(
                  key: const ValueKey('reset-login'),
                  controller: _login,
                  enabled: !_busy,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: widget.operatorGateway == null
                        ? 'Username or email'
                        : 'Operator email',
                  ),
                  validator: (value) => _validLogin(value ?? '')
                      ? null
                      : widget.operatorGateway == null
                      ? 'Enter your username or email address.'
                      : 'Enter your operator email.',
                  onFieldSubmitted: (_) => _requestCode(),
                )
              else ...[
                const Text(
                  'If the account has a registered recovery email, we sent a reset code there.',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('reset-code'),
                  controller: _code,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Reset code'),
                  validator: (value) =>
                      validEmailCode(value) ? null : 'Enter the 8-digit code.',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('reset-password'),
                  controller: _password,
                  enabled: !_busy,
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: const InputDecoration(labelText: 'New password'),
                  validator: validateOrganizationPassword,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('reset-confirmation'),
                  controller: _confirmation,
                  enabled: !_busy,
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: const InputDecoration(
                    labelText: 'Confirm new password',
                  ),
                  validator: (value) => value == _password.text
                      ? null
                      : 'The passwords must match.',
                  onFieldSubmitted: (_) => _resetPassword(),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _busy ? null : _requestCode,
                    child: const Text('Send another code'),
                  ),
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
        FilledButton(
          key: const ValueKey('reset-submit'),
          onPressed: _busy
              ? null
              : _codeRequested
              ? _resetPassword
              : _requestCode,
          child: Text(
            _busy
                ? 'Please wait…'
                : _codeRequested
                ? 'Reset password'
                : 'Send reset code',
          ),
        ),
      ],
    ),
  );
}

const organizationPasswordHint =
    'Use at least 12 characters with uppercase and lowercase letters and a number.';

String? accountSecurityErrorCode(Object error) => switch (error) {
  AccountSecurityException(:final code) => code,
  PlatformOrganizationFailure(:final code) => code,
  _ => null,
};

String? validateOrganizationPassword(String? value) {
  final password = value ?? '';
  if (isOrganizationPassword(password)) return null;
  if (utf8.encode(password).length > 72) return 'Choose a shorter password.';
  return organizationPasswordHint;
}

bool validEmailCode(String? value) => RegExp(r'^\d{8}$').hasMatch(value ?? '');

class AuthFormError extends StatelessWidget {
  const AuthFormError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );
}
