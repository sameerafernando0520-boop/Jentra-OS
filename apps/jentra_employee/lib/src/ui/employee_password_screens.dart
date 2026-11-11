import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:jentra_platform/src/supabase_foundation_gateway.dart';

import '../data/employee_gateway.dart';
import '../l10n/employee_account_strings.dart';
import '../l10n/employee_strings.dart';
import 'employee_components.dart';

class EmployeeTemporaryPasswordScreen extends StatefulWidget {
  const EmployeeTemporaryPasswordScreen({
    required this.busy,
    required this.failure,
    required this.onChange,
    required this.onSignOut,
    super.key,
  });

  final bool busy;
  final EmployeeFailure? failure;
  final Future<void> Function(String, String) onChange;
  final Future<void> Function() onSignOut;

  @override
  State<EmployeeTemporaryPasswordScreen> createState() =>
      _EmployeeTemporaryPasswordScreenState();
}

class _EmployeeTemporaryPasswordScreenState
    extends State<EmployeeTemporaryPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    for (final field in [_current, _new, _confirm]) {
      field.clear();
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (widget.busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await widget.onChange(_current.text, _new.text);
    if (mounted) _current.clear();
  }

  @override
  Widget build(BuildContext context) {
    final a = EmployeeAccountStrings(context);
    final s = EmployeeStrings.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    EmployeeHeading(a.changeTemporaryPassword, large: true),
                    const SizedBox(height: 16),
                    Text(a.changeTemporaryPasswordCopy),
                    const SizedBox(height: 20),
                    _secretField(
                      _current,
                      a.temporaryPassword,
                      widget.busy,
                      (value) => value.isEmpty ? s('passwordError') : null,
                    ),
                    const SizedBox(height: 12),
                    _secretField(
                      _new,
                      a.newPassword,
                      widget.busy,
                      (value) => isOrganizationPassword(value)
                          ? null
                          : a.passwordRequirements,
                    ),
                    const SizedBox(height: 12),
                    _secretField(
                      _confirm,
                      a.confirmPassword,
                      widget.busy,
                      (value) => value == _new.text ? null : a.passwordMismatch,
                    ),
                    if (widget.failure case final failure?) ...[
                      const SizedBox(height: 16),
                      EmployeeMessage(title: s.failure(failure), error: true),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: widget.busy ? null : _save,
                      child: Text(a.changeTemporaryPassword),
                    ),
                    TextButton(
                      onPressed: widget.busy ? null : widget.onSignOut,
                      child: Text(s('signOut')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class EmployeeUsernameRecoveryDialog extends StatefulWidget {
  const EmployeeUsernameRecoveryDialog({
    required this.initialLogin,
    required this.onRequest,
    required this.onReset,
    super.key,
  });

  final String initialLogin;
  final Future<void> Function(String) onRequest;
  final Future<void> Function(String, String, String) onReset;

  @override
  State<EmployeeUsernameRecoveryDialog> createState() =>
      _EmployeeUsernameRecoveryDialogState();
}

class _EmployeeUsernameRecoveryDialogState
    extends State<EmployeeUsernameRecoveryDialog> {
  final _form = GlobalKey<FormState>();
  late final _login = TextEditingController(
    text: widget.initialLogin.contains('@') ? '' : widget.initialLogin.trim(),
  );
  final _code = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _requested = false;
  EmployeeFailure? _failure;

  @override
  void dispose() {
    for (final field in [_login, _code, _new, _confirm]) {
      field.clear();
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      if (_requested) {
        await widget.onReset(_login.text.trim(), _code.text.trim(), _new.text);
        if (mounted) Navigator.pop(context, true);
      } else {
        await widget.onRequest(_login.text.trim());
        if (mounted) setState(() => _requested = true);
      }
    } on Object catch (failure) {
      if (mounted) setState(() => _failure = employeeFailure(failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = EmployeeAccountStrings(context);
    final s = EmployeeStrings.of(context);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        title: Text(a.resetUsernamePassword),
        content: SizedBox(
          width: 420,
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _login,
                  enabled: !_busy && !_requested,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.username],
                  decoration: InputDecoration(labelText: a.username),
                  validator: (value) =>
                      value != null &&
                          !value.contains('@') &&
                          isAccountLogin(value)
                      ? null
                      : a.usernameError,
                ),
                if (_requested) ...[
                  const SizedBox(height: 12),
                  Text(a.recoveryRequested),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _code,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    decoration: InputDecoration(labelText: a.recoveryCode),
                    validator: (value) =>
                        RegExp(r'^\d{6}$').hasMatch(value?.trim() ?? '')
                        ? null
                        : a.recoveryCodeError,
                  ),
                  const SizedBox(height: 12),
                  _secretField(
                    _new,
                    a.newPassword,
                    _busy,
                    (value) => isOrganizationPassword(value)
                        ? null
                        : a.passwordRequirements,
                  ),
                  const SizedBox(height: 12),
                  _secretField(
                    _confirm,
                    a.confirmPassword,
                    _busy,
                    (value) => value == _new.text ? null : a.passwordMismatch,
                  ),
                ],
                if (_failure case final failure?) ...[
                  const SizedBox(height: 12),
                  EmployeeMessage(title: s.failure(failure), error: true),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_requested ? a.resetPassword : a.sendRecoveryCode),
          ),
        ],
      ),
    );
  }
}

TextFormField _secretField(
  TextEditingController controller,
  String label,
  bool busy,
  String? Function(String) validate,
) => TextFormField(
  controller: controller,
  enabled: !busy,
  obscureText: true,
  autocorrect: false,
  enableSuggestions: false,
  decoration: InputDecoration(labelText: label),
  validator: (value) => validate(value ?? ''),
);
