import 'package:flutter/material.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:uuid/uuid.dart';

typedef StaffCredentials = Map<String, Object?>;

Future<void> showStaffCredentialIssuer(
  BuildContext context, {
  required PlatformOrganizationGateway gateway,
  required String tenantId,
  required String displayName,
  Map<String, String> entities = const {},
  String? legalEntityId,
  String? branchId,
  String? employeeId,
  String? suggestedEmail,
  String? migrationId,
  String? oldMembershipId,
  String? oldLinkId,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _StaffIssuer(
    gateway: gateway,
    tenantId: tenantId,
    displayName: displayName,
    entities: entities,
    legalEntityId: legalEntityId,
    branchId: branchId,
    employeeId: employeeId,
    suggestedEmail: suggestedEmail,
    migrationId: migrationId,
    oldMembershipId: oldMembershipId,
    oldLinkId: oldLinkId,
  ),
);

Future<void> manageEmployeeCredentials(
  BuildContext context, {
  required PlatformOrganizationGateway gateway,
  required String tenantId,
  required String legalEntityId,
  required String branchId,
  required String employeeId,
  required String name,
  String? email,
}) async {
  try {
    final rows = await gateway.rpc<List<dynamic>>('managed_staff_credentials', {
      'p_tenant_id': tenantId,
      'p_legal_entity_id': legalEntityId,
      'p_employee_id': employeeId,
    });
    if (!context.mounted) return;
    final current = rows
        .whereType<Map>()
        .where((row) => row['status'] != 'revoked')
        .firstOrNull;
    if (current != null) {
      await showStaffCredentialActions(
        context,
        gateway,
        Map<String, Object?>.from(current),
      );
      return;
    }
    await showStaffCredentialIssuer(
      context,
      gateway: gateway,
      tenantId: tenantId,
      displayName: name,
      legalEntityId: legalEntityId,
      branchId: branchId,
      employeeId: employeeId,
      suggestedEmail: email,
    );
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load Employee app access.')),
      );
    }
  }
}

Future<void> showStaffCredentialActions(
  BuildContext context,
  PlatformOrganizationGateway gateway,
  StaffCredentials credentials, {
  bool allowRevoke = true,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _StaffActions(gateway, credentials, allowRevoke: allowRevoke),
);

String staffCredentialStatus(Object? status) => switch (status) {
  'verification_required' => 'Waiting for email verification',
  'prepared' || 'processing' => 'Preparing credentials',
  'issued' => 'Waiting for first password change',
  'ready' => 'Ready for cutover',
  'active' => 'Active',
  'expired' => 'Temporary password expired',
  'failed' => 'Handover failed. Reissue the password.',
  'revoked' => 'Revoked',
  _ => 'Credential status unavailable',
};

String _staffError(Object error) => switch (error) {
  PlatformOrganizationFailure(code: 'forbidden') =>
    'Verify MFA and check your access to this organization.',
  PlatformOrganizationFailure(
    code: 'DUPLICATE_RECORD' || 'username_unavailable',
  ) =>
    'This employee or username is already linked. Check the existing account.',
  PlatformOrganizationFailure(code: 'delivery_unavailable') =>
    'Email could not be sent. Check the delivery configuration and retry.',
  _ => 'Could not complete this request. Check the details and retry.',
};

class _StaffIssuer extends StatefulWidget {
  const _StaffIssuer({
    required this.gateway,
    required this.tenantId,
    required this.displayName,
    required this.entities,
    this.legalEntityId,
    this.branchId,
    this.employeeId,
    this.suggestedEmail,
    this.migrationId,
    this.oldMembershipId,
    this.oldLinkId,
  });

  final PlatformOrganizationGateway gateway;
  final String tenantId;
  final String displayName;
  final Map<String, String> entities;
  final String? legalEntityId;
  final String? branchId;
  final String? employeeId;
  final String? suggestedEmail;
  final String? migrationId;
  final String? oldMembershipId;
  final String? oldLinkId;

  @override
  State<_StaffIssuer> createState() => _StaffIssuerState();
}

class _StaffIssuerState extends State<_StaffIssuer> {
  final _form = GlobalKey<FormState>();
  final _requestId = const Uuid().v4();
  final _selected = <String>{};
  late String _name = widget.displayName;
  late String _email = widget.suggestedEmail ?? '';
  String _segment = '';
  String _delivery = 'email';
  StaffCredentials? _result;
  String? _error;
  bool _busy = false;

  bool get _manager => widget.employeeId == null;

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_manager && _selected.isEmpty) {
      setState(() => _error = 'Select at least one organization.');
      return;
    }
    _form.currentState!.save();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final row = await widget.gateway.identity(
        _manager ? 'create_hr_manager' : 'create_employee_credentials',
        {
          'tenant_id': widget.tenantId,
          'request_id': _requestId,
          'delivery': _delivery,
          if (_delivery == 'email') 'email': _email,
          if (_manager) ...{
            'name': _name,
            'legal_entity_ids': _selected.toList(growable: false),
            if (_segment.isNotEmpty) 'username': _segment,
          } else ...{
            'legal_entity_id': widget.legalEntityId,
            'branch_id': widget.branchId,
            'employee_id': widget.employeeId,
            if (_segment.isNotEmpty) 'name_segment': _segment,
          },
          if (widget.migrationId != null) ...{
            'migration_id': widget.migrationId,
            'supersedes_membership_id': widget.oldMembershipId,
            'supersedes_link_id': widget.oldLinkId,
          },
        },
      );
      if (mounted) {
        setState(() => _result = Map<String, Object?>.from(row as Map));
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = _staffError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(
          _manager ? 'Create HR Manager' : 'Issue Employee App Login',
        ),
        scrollable: true,
        content: SizedBox(
          width: 470,
          child: result != null
              ? _StaffHandover(result)
              : Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_manager) ...[
                        TextFormField(
                          initialValue: _name,
                          enabled: !_busy,
                          decoration: const InputDecoration(
                            labelText: 'HR Manager name',
                          ),
                          validator: (value) =>
                              value!.trim().isEmpty ? 'Enter a name.' : null,
                          onSaved: (value) => _name = value!.trim(),
                        ),
                        const SizedBox(height: 10),
                        const Text('Organizations this manager can administer'),
                        for (final entity in widget.entities.entries)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(entity.value),
                            value: _selected.contains(entity.key),
                            onChanged: _busy
                                ? null
                                : (selected) => setState(() {
                                    if (selected == true) {
                                      _selected.add(entity.key);
                                    } else {
                                      _selected.remove(entity.key);
                                    }
                                  }),
                          ),
                      ] else
                        Text(widget.displayName),
                      TextFormField(
                        enabled: !_busy,
                        decoration: const InputDecoration(
                          labelText: 'Username name portion (optional)',
                          helperText: 'Jentra adds the system serial.',
                        ),
                        validator: (value) {
                          final text = value!.trim().toLowerCase();
                          return text.isEmpty ||
                                  RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$')
                                      .hasMatch(text)
                              ? null
                              : 'Use letters, numbers, and single hyphens.';
                        },
                        onSaved: (value) =>
                            _segment = value!.trim().toLowerCase(),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _delivery,
                        decoration: const InputDecoration(
                          labelText: 'Credential delivery',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'email',
                            child: Text('Verify and deliver by email'),
                          ),
                          DropdownMenuItem(
                            value: 'reveal',
                            child: Text('Private one-time handoff'),
                          ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _delivery = value!),
                      ),
                      if (_delivery == 'email')
                        TextFormField(
                          initialValue: _email,
                          enabled: !_busy,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Recipient email',
                          ),
                          validator: (value) =>
                              RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                  .hasMatch(value!.trim())
                              ? null
                              : 'Enter a valid email address.',
                          onChanged: (value) => _email = value.trim(),
                          onSaved: (value) => _email = value!.trim(),
                        ),
                      if (_error case final error?) Text(error),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(result == null ? 'Cancel' : 'Close'),
          ),
          if (result == null)
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Issuing…' : 'Issue credentials'),
            ),
        ],
      ),
    );
  }
}

class _StaffHandover extends StatelessWidget {
  const _StaffHandover(this.row);

  final StaffCredentials row;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (row['username'] case final String username)
        SelectableText('Username $username'),
      Text(staffCredentialStatus(row['status'])),
      if (row['temporary_password'] case final String password) ...[
        const Text(
          'Share this temporary password privately. It can be viewed only here.',
        ),
        SelectableText(password),
        if (row['expires_at'] case final String deadline)
          Text('Expires ${DateTime.tryParse(deadline)?.toLocal() ?? deadline}'),
      ],
    ],
  );
}

class _StaffActions extends StatefulWidget {
  const _StaffActions(
    this.gateway,
    this.credentials, {
    required this.allowRevoke,
  });

  final PlatformOrganizationGateway gateway;
  final StaffCredentials credentials;
  final bool allowRevoke;

  @override
  State<_StaffActions> createState() => _StaffActionsState();
}

class _StaffActionsState extends State<_StaffActions> {
  late StaffCredentials _row = widget.credentials;
  final _request = const Uuid().v4();
  bool _busy = false;
  bool _finished = false;
  String? _error;

  Future<void> _update({required bool revoke}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = _row['identity_id'];
      final StaffCredentials next;
      if (revoke) {
        await widget.gateway.rpc('revoke_managed_staff_identity', {
          'p_identity_id': id,
        });
        next = {..._row, 'status': 'revoked'};
      } else {
        next = Map<String, Object?>.from(
          await widget.gateway.identity('reissue_staff_credentials', {
            'identity_id': id,
            'request_id': _request,
          }) as Map,
        );
      }
      if (mounted) {
        setState(() {
          _row = next;
          _finished = true;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = _staffError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Staff app access'),
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StaffHandover(_row),
          if (_busy) const LinearProgressIndicator(),
          if (_error case final error?) Text(error),
          if (!_finished && _row['status'] != 'revoked')
            const Text('Reissuing invalidates the current password.'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (!_finished && _row['status'] != 'revoked') ...[
          if (widget.allowRevoke)
            TextButton(
              onPressed: _busy ? null : () => _update(revoke: true),
              child: const Text('Revoke access'),
            ),
          FilledButton(
            onPressed: _busy ? null : () => _update(revoke: false),
            child: Text(
              _row['status'] == 'verification_required'
                  ? 'Resend verification'
                  : 'Reissue password',
            ),
          ),
        ],
      ],
    ),
  );
}
