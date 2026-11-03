import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_workspace_admin.dart';
import 'package:jentra_platform/jentra_workspace_admin_platform.dart';
import 'package:uuid/uuid.dart';

import 'workspace_admin_controller.dart';
import '../../app_providers.dart';

final workspaceStaffGatewayProvider = Provider<WorkspaceStaffGateway?>(
  (ref) => null,
);
final workspaceStaffRecoveryProvider = Provider<StaffAccountRecovery>(
  (ref) => EncryptedStaffAccountRecovery(
    ref.watch(encryptedDraftRepositoryProvider),
  ),
);

class StaffAccountDialog extends ConsumerStatefulWidget {
  const StaffAccountDialog({required this.controller, super.key});
  final WorkspaceAdminController controller;

  @override
  ConsumerState<StaffAccountDialog> createState() => _StaffAccountDialogState();
}

class _StaffAccountDialogState extends ConsumerState<StaffAccountDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _roles = <String>{};
  String _requestId = const Uuid().v4();
  bool _busy = false,
      _submitted = false,
      _visible = false,
      _passwordRetry = false;
  String? _error;
  bool _loading = true, _recoveryAvailable = false;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    try {
      final saved = await ref
          .read(workspaceStaffRecoveryProvider)
          .load(widget.controller.scope);
      if (!mounted || !_current) return;
      if (saved != null) {
        _requestId = saved.requestId;
        _username.text = saved.username;
        _name.text = saved.displayName;
        _roles.addAll(saved.roleIds);
        _submitted = true;
        _passwordRetry = true;
      }
      _recoveryAvailable = true;
    } on Object {
      if (mounted) _error = 'Protected recovery could not be loaded. Reopen this form before creating an account.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  bool get _current =>
      ref.read(workspaceAdminControllerProvider) == widget.controller &&
      !widget.controller.locked;

  Future<void> _startDifferent() async {
    if (_busy || !_current) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(workspaceStaffRecoveryProvider)
          .complete(widget.controller.scope, _requestId);
      if (!mounted || !_current) return;
      _name.clear();
      _username.clear();
      _password.clear();
      _confirmation.clear();
      _roles.clear();
      setState(() {
        _requestId = const Uuid().v4();
        _submitted = false;
        _passwordRetry = false;
        _error = null;
      });
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Protected recovery could not be cleared. Retry clearing the saved request.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    if (_busy ||
        _loading ||
        !_recoveryAvailable ||
        !_current ||
        !_form.currentState!.validate()) {
      return;
    }
    if (_roles.isEmpty) {
      setState(
        () => _error = 'Select at least one role for the assigned sections.',
      );
      return;
    }
    final gateway = ref.read(workspaceStaffGatewayProvider);
    if (gateway == null) return;
    setState(() {
      _busy = true;
      _submitted = true;
      _passwordRetry = false;
      _error = null;
    });
    try {
      await ref
          .read(workspaceStaffRecoveryProvider)
          .save(
            widget.controller.scope,
            StaffAccountRequest(
              requestId: _requestId,
              username: _username.text.trim().toLowerCase(),
              displayName: _name.text.trim(),
              roleIds: Set.of(_roles),
            ),
          );
      if (!mounted || !_current) return;
      await gateway.create(
        scope: widget.controller.scope,
        requestId: _requestId,
        username: _username.text,
        displayName: _name.text,
        roleIds: Set.of(_roles),
        password: _password.text,
      );
      if (!mounted || !_current) return;
      await ref
          .read(workspaceStaffRecoveryProvider)
          .complete(widget.controller.scope, _requestId);
      if (!mounted || !_current) return;
      _password.clear();
      _confirmation.clear();
      Navigator.of(context).pop(true);
    } on DomainError catch (error) {
      if (!mounted) return;
      if (error.code == 'CONFLICT' ||
          error.code == 'VALIDATION_ERROR' ||
          error.code == 'ACCESS_CHANGED') {
        try {
          await ref
              .read(workspaceStaffRecoveryProvider)
              .complete(widget.controller.scope, _requestId);
        } on Object {
          if (mounted) {
            setState(
              () => _error = 'Protected recovery could not be cleared. Keep the original details and retry.',
            );
          }
          return;
        }
        if (!mounted) return;
      }
      setState(() {
        _error = error.message;
        if (error.code == 'ACCESS_CHANGED') {
          _name.clear();
          _username.clear();
          _password.clear();
          _confirmation.clear();
          _roles.clear();
          _requestId = const Uuid().v4();
          _submitted = false;
        }
        if (error.code == 'CONFLICT' || error.code == 'VALIDATION_ERROR') {
          _submitted = false;
          if (error.code == 'CONFLICT') _requestId = const Uuid().v4();
        }
        _passwordRetry =
            error.code == 'PASSWORD_TOO_WEAK' ||
            error.code == 'PASSWORD_REQUIRED';
      });
    } on Object {
      if (mounted) {
        setState(
          () =>
              _error = 'Creation is not confirmed. Retry the original details.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current =
        ref.watch(workspaceAdminControllerProvider) == widget.controller;
    if (!current) {
      _password.clear();
      _confirmation.clear();
      return AlertDialog(
        title: const Text('Administrator access changed'),
        content: const Text(
          'Reopen staff administration to check your current access.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    }
    final choices =
        widget.controller.catalogues[WorkspaceAdminResource.roles] ?? [];
    final editable = !_busy && !_submitted && !_loading && _recoveryAvailable;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Create staff account'),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Give this person their username and password privately. They can sign in immediately and set up their own authenticator.',
                  ),
                  const SizedBox(height: 16),
                  if (_loading) const LinearProgressIndicator(),
                  if (_submitted)
                    const Text(
                      'A saved creation request is being resumed. Enter its original password; passwords are never saved on this device.',
                    ),
                  TextFormField(
                    key: const ValueKey('staff-display-name'),
                    controller: _name,
                    enabled: editable,
                    maxLength: 100,
                    decoration: const InputDecoration(labelText: 'Full name'),
                    validator: (value) =>
                        value == null ||
                            value.trim().isEmpty ||
                            RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)
                        ? 'Enter their name.'
                        : null,
                  ),
                  TextFormField(
                    key: const ValueKey('staff-username'),
                    controller: _username,
                    enabled: editable,
                    maxLength: 40,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      helperText: '3–40 letters, numbers, underscores or hyphens. Use a business prefix for a unique name.',
                    ),
                    validator: (value) =>
                        RegExp(r'^[a-z0-9][a-z0-9_-]{2,39}$')
                            .hasMatch(value?.trim().toLowerCase() ?? '')
                        ? null
                        : 'Enter a valid username.',
                  ),
                  TextFormField(
                    key: const ValueKey('staff-password'),
                    controller: _password,
                    enabled: editable || (!_busy && _passwordRetry),
                    obscureText: !_visible,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        tooltip: _visible ? 'Hide password' : 'Show password',
                        onPressed: _busy
                            ? null
                            : () => setState(() => _visible = !_visible),
                        icon: Icon(
                          _visible ? Icons.visibility_off : Icons.visibility,
                        ),
                      ),
                    ),
                    validator: (value) =>
                        value == null ||
                            value.length < 12 ||
                            utf8.encode(value).length > 256 ||
                            value.contains('\u0000')
                        ? 'Use at least 12 characters and keep the password reasonably short.'
                        : null,
                  ),
                  TextFormField(
                    key: const ValueKey('staff-password-confirmation'),
                    controller: _confirmation,
                    enabled: editable || (!_busy && _passwordRetry),
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Confirm password',
                    ),
                    validator: (value) => value != _password.text
                        ? 'Passwords must match.'
                        : null,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Assigned sections and tasks',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Text(
                    'Choose one or more roles. Create a custom role in Roles to combine permissions from Sales, Finance, Inventory or other sections.',
                  ),
                  for (final role in choices.where(
                    (role) => role.data['code'] != 'tenant_owner',
                  ))
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(role.name),
                      subtitle: Text(
                        (role.data['permissions'] as List? ?? []).join(', '),
                      ),
                      value: _roles.contains(role.id),
                      onChanged: !editable
                          ? null
                          : (selected) => setState(() {
                              if (selected == true) {
                                _roles.add(role.id);
                              } else {
                                _roles.remove(role.id);
                              }
                            }),
                    ),
                  if (choices
                      .where((role) => role.data['code'] != 'tenant_owner')
                      .isEmpty)
                    const Text(
                      'Create a role with the required section permissions before adding staff.',
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          if (_submitted)
            TextButton(
              key: const ValueKey('staff-start-different'),
              onPressed: _busy ? null : _startDifferent,
              child: const Text('Start a different account'),
            ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton(
            key: const ValueKey('staff-create-submit'),
            onPressed:
                _busy ||
                    _loading ||
                    !_recoveryAvailable ||
                    ref.watch(workspaceStaffGatewayProvider) == null
                ? null
                : _create,
            child: Text(
              _busy
                  ? 'Creating…'
                  : _submitted
                  ? 'Retry original request'
                  : 'Create account',
            ),
          ),
        ],
      ),
    );
  }
}
