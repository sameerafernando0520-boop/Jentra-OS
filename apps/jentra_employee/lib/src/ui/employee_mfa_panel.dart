import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/employee_mfa.dart';
import '../l10n/employee_strings.dart';

/// Keep [gateway] stable for this panel's lifetime. [onVerified] should refresh
/// employee access; it is called only for the panel's original verified actor.
class EmployeeMfaPanel extends StatefulWidget {
  const EmployeeMfaPanel({
    required this.gateway,
    required this.onVerified,
    this.observeLifecycle = true,
    super.key,
  });
  final EmployeeMfaGateway gateway;
  final Future<void> Function() onVerified;
  final bool observeLifecycle;
  @override
  State<EmployeeMfaPanel> createState() => _EmployeeMfaPanelState();
}

class _EmployeeMfaPanelState extends State<EmployeeMfaPanel>
    with WidgetsBindingObserver {
  late EmployeeMfaController _controller;
  final _code = TextEditingController();
  bool _notified = false;
  bool _continuing = false;
  String? _continueError;
  String? _inputFactorId;

  void _createController() {
    _controller = EmployeeMfaController(widget.gateway)..addListener(_changed);
    unawaited(_controller.load());
  }

  @override
  void initState() {
    super.initState();
    if (widget.observeLifecycle) WidgetsBinding.instance.addObserver(this);
    _createController();
  }

  @override
  void didUpdateWidget(covariant EmployeeMfaPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.gateway, widget.gateway)) {
      _controller.removeListener(_changed);
      _controller.dispose();
      _code.clear();
      _notified = false;
      _continuing = false;
      _continueError = null;
      _inputFactorId = null;
      _createController();
    }
  }

  void _changed() {
    if (!_controller.current ||
        _inputFactorId != _controller.selectedFactorId) {
      _code.clear();
      _inputFactorId = _controller.selectedFactorId;
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _code.clear();
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller.resume());
    } else {
      _controller.suspend();
    }
  }

  Future<void> _verify() async {
    if (_continuing || _notified) return;
    final controller = _controller;
    final code = _code.text.trim();
    _code.clear();
    final accepted = controller.gateway.isVerifiedSession
        ? controller.confirmVerifiedSession()
        : await controller.verify(code);
    if (!mounted ||
        !identical(controller, _controller) ||
        !accepted ||
        !controller.current ||
        !controller.verified ||
        !controller.gateway.isVerifiedSession ||
        _notified) {
      return;
    }
    _notified = true;
    _continuing = true;
    _continueError = null;
    setState(() {});
    try {
      await widget.onVerified();
    } on Object {
      if (mounted && identical(controller, _controller) && controller.current) {
        _notified = false;
        _continueError = 'Verification succeeded. Refresh employee access again to continue.';
      }
    } finally {
      if (mounted && identical(controller, _controller)) {
        _continuing = false;
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    if (widget.observeLifecycle) WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_changed);
    _controller.dispose();
    _code.clear();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller, enrollment = c.enrollment;
    final s = EmployeeStrings.of(context);
    final alreadyVerified = c.current && c.gateway.isVerifiedSession;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s('mfaTitle'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(s('mfaPrivate')),
            if (c.busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (!c.current)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(s('mfaPaused')),
              )
            else if (c.loaded && !alreadyVerified) ...[
              if (enrollment != null) ...[
                const SizedBox(height: 12),
                Text(s('mfaManualKey')),
                const SizedBox(height: 8),
                SelectableText(
                  enrollment.secret,
                  key: const Key('employee-mfa-setup-key'),
                ),
                const SizedBox(height: 8),
                Text(s('mfaEnterAfterSetup')),
              ] else if (c.factors.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey(c.selectedFactorId),
                  initialValue: c.selectedFactorId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: s('mfaAuthenticator')),
                  items: [
                    for (final (index, factor) in c.factors.indexed)
                      DropdownMenuItem(
                        value: factor.id,
                        child: Text(
                          factor.verified
                              ? '${s('mfaAuthenticator')} ${index + 1}'
                              : s('mfaPreviousSetup'),
                        ),
                      ),
                  ],
                  onChanged: c.busy ? null : c.selectFactor,
                ),
              ] else ...[
                const SizedBox(height: 12),
                Text(s('mfaNoFactor')),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const Key('employee-mfa-enroll'),
                  onPressed: c.busy ? null : c.enroll,
                  child: Text(s('mfaSetUp')),
                ),
              ],
              if (!c.hasPendingSetup)
                for (final (index, factor) in c.recoverableSetups.indexed)
                  TextButton(
                    key: ValueKey('employee-mfa-restore-${factor.id}'),
                    onPressed: c.busy ? null : () => c.restoreSetup(factor.id),
                    child: Text('${s('mfaPreviousSetup')} ${index + 1}'),
                  ),
              if (c.selectedFactorId != null) ...[
                if (c.hasPendingSetup && enrollment == null) ...[
                  const SizedBox(height: 12),
                  Text(s('mfaHiddenKey')),
                ],
                const SizedBox(height: 12),
                TextField(
                  key: const Key('employee-mfa-code'),
                  controller: _code,
                  enabled: !c.busy,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: s('mfaCode')),
                  onSubmitted: (_) {
                    if (!c.busy) unawaited(_verify());
                  },
                ),
              ],
              if (c.hasPendingSetup)
                TextButton(
                  key: const Key('employee-mfa-cancel-setup'),
                  onPressed: c.busy ? null : c.cancelSetup,
                  child: Text(s('mfaCancelSetup')),
                ),
            ],
            if (c.error != null || _continueError != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(s.mfaMessage(c.error ?? _continueError!)),
              ),
            ],
            if (c.current &&
                (alreadyVerified || c.selectedFactorId != null)) ...[
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('employee-mfa-verify'),
                onPressed: c.busy || _continuing ? null : _verify,
                child: Text(s(alreadyVerified ? 'mfaContinue' : 'mfaVerify')),
              ),
            ] else if (c.current && !c.loaded && !c.busy)
              TextButton(onPressed: c.load, child: Text(s('mfaCheckAgain'))),
          ],
        ),
      ),
    );
  }
}
