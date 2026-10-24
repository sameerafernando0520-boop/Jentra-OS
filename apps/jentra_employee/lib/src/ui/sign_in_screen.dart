import 'package:flutter/material.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

import '../l10n/employee_strings.dart';
import 'employee_components.dart';
import 'employee_help_screen.dart';
import 'employee_surfaces.dart';

class EmployeeSignInScreen extends StatefulWidget {
  const EmployeeSignInScreen({
    required this.connected,
    required this.busy,
    required this.onSignIn,
    this.error,
    super.key,
  });

  final bool connected;
  final bool busy;
  final String? error;
  final Future<void> Function(String email, String password) onSignIn;

  @override
  State<EmployeeSignInScreen> createState() => _EmployeeSignInScreenState();
}

class _EmployeeSignInScreenState extends State<EmployeeSignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.clear();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!widget.connected || widget.busy || !_form.currentState!.validate()) {
      return;
    }
    final email = _email.text.trim();
    final password = _password.text;
    FocusScope.of(context).unfocus();
    await widget.onSignIn(email, password);
    if (mounted) _password.clear();
  }

  @override
  Widget build(BuildContext context) {
    final s = EmployeeStrings.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: JentraBrandLockup(
                            size: 32,
                            inverse:
                                Theme.of(context).brightness == Brightness.dark,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Flexible(
                          child: Text(
                            s('employee'),
                            textAlign: TextAlign.end,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: context.jentraColors.textSecondary,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    Semantics(
                      header: true,
                      child: Text(
                        s('welcome'),
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(
                              fontSize: 38,
                              height: 1.12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.2,
                            ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      s('welcomeCopy'),
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(color: context.jentraColors.textSecondary),
                    ),
                    const SizedBox(height: 24),
                    if (!widget.connected && widget.error == null) ...[
                      EmployeeMessage(
                        title: s('connectionNotReady'),
                        message: s('connectionCopy'),
                      ),
                      const SizedBox(height: 20),
                    ],
                    EmployeeSurface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            key: const Key('employee-email'),
                            controller: _email,
                            enabled: widget.connected && !widget.busy,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.username],
                            autocorrect: false,
                            textCapitalization: TextCapitalization.none,
                            decoration: InputDecoration(
                              labelText: s('email'),
                              prefixIcon: const Icon(
                                Icons.alternate_email_rounded,
                                size: 20,
                              ),
                              filled: true,
                              fillColor: context.jentraColors.panelElevated,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            validator: (value) =>
                                RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                    .hasMatch(value?.trim() ?? '')
                                ? null
                                : s('emailError'),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const Key('employee-password'),
                            controller: _password,
                            enabled: widget.connected && !widget.busy,
                            obscureText: _obscure,
                            enableSuggestions: false,
                            autocorrect: false,
                            keyboardType: TextInputType.visiblePassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: s('password'),
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                                size: 20,
                              ),
                              filled: true,
                              fillColor: context.jentraColors.panelElevated,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              suffixIcon: IconButton(
                                tooltip: s(
                                  _obscure ? 'showPassword' : 'hidePassword',
                                ),
                                onPressed: widget.busy
                                    ? null
                                    : () =>
                                          setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (value) => value == null || value.isEmpty
                                ? s('passwordError')
                                : null,
                          ),
                          if (widget.error != null) ...[
                            const SizedBox(height: 20),
                            EmployeeMessage(
                              title: widget.error!,
                              error: true,
                              icon: Icons.error_outline,
                            ),
                          ],
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              key: const Key('employee-sign-in'),
                              onPressed: !widget.connected || widget.busy
                                  ? null
                                  : _submit,
                              child: widget.busy
                                  ? const SizedBox.square(
                                      dimension: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            s('signIn'),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        const Icon(
                                          Icons.arrow_forward_rounded,
                                          size: 20,
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        key: const Key('employee-account-help'),
                        onPressed: widget.busy
                            ? null
                            : () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => const EmployeeHelpScreen(),
                                ),
                              ),
                        child: Text(
                          s('accountHelp'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.lock_outline,
                          color: context.jentraColors.textSecondary,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${s('accountCopy')}\n${s('hrAccessCopy')}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: context.jentraColors.textSecondary,
                                ),
                          ),
                        ),
                      ],
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
