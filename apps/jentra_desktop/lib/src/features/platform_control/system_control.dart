part of 'platform_organization_screen.dart';

Future<void> _createSystem(
  BuildContext context,
  PlatformOrganizationGateway gateway,
  List<_Row> plans,
) async {
  final eligible = plans
      .where(
        (plan) => _availablePackage(plan) && plan['currency_code'] == 'LKR',
      )
      .toList();
  if (eligible.isEmpty) {
    _notice(context, 'Configure an active LKR plan before creating a system.');
    return;
  }
  final request = const Uuid().v4();
  _Row? receipt;
  final saved = await _edit(
    context,
    'Create New System',
    'Choose a plan. Record the exact verified bank transfer or give a reason for a complimentary term.',
    [
      const _Field('name', 'System or organization name'),
      const _Field('email', 'Owner email', email: true),
      _Field('plan', 'Plan', choices: _packageChoices(eligible)),
      const _Field(
        'mode',
        'Access grant',
        choices: {
          'paid': 'Verified bank transfer',
          'complimentary': 'Complimentary grant',
        },
      ),
      const _Field(
        'reference',
        'Bank reference (paid systems)',
        required: false,
      ),
      const _Field(
        'amount',
        'Amount received in LKR (paid systems)',
        required: false,
      ),
      const _Field(
        'paid_at',
        'Bank time in Sri Lanka (YYYY-MM-DD HH:MM:SS)',
        required: false,
      ),
      const _Field('reason', 'Reason (complimentary systems)', required: false),
    ],
    (values) async {
      final paid = values['mode'] == 'paid';
      final plan = eligible.singleWhere((row) => row['code'] == values['plan']);
      final amount = paid ? _minor(values['amount']!, 'LKR') : null;
      final reference = _provided(values['reference']);
      final reason = _provided(values['reason']);
      if (paid &&
          (amount == null ||
              amount != plan['price_minor'] ||
              amount <= 0 ||
              reference == null)) {
        throw const PlatformOrganizationFailure('SYSTEM_PAYMENT_MISMATCH');
      }
      if (!paid && (reason == null || reason.trim().length < 5)) {
        throw const PlatformOrganizationFailure('SYSTEM_GRANT_REASON_REQUIRED');
      }
      receipt = await gateway.rpc<Map<String, dynamic>>(
        'platform_create_system',
        {
          'p_name': values['name'],
          'p_owner_email': values['email'],
          'p_plan_code': plan['code'],
          'p_expected_revision': plan['revision'],
          'p_request_id': request,
          'p_mode': values['mode'],
          if (paid) 'p_payment_reference': reference,
          if (paid) 'p_paid_amount_minor': amount,
          if (paid)
            'p_paid_at': _sriLankaTransferTime(values['paid_at']!)
                .toIso8601String(),
          if (!paid) 'p_reason': reason,
        },
      );
    },
    submit: 'Create system',
  );
  final system = receipt;
  if (!saved || system == null || !context.mounted) return;
  final verification = system['verification_id'];
  if (verification is String && system['can_request_verification'] != false) {
    try {
      await gateway.systemOwnerVerification('request_code', {
        'verification_id': verification,
      });
    } on Object {
      if (context.mounted) {
        _notice(
          context,
          'System created. Retry the owner verification email in System access.',
        );
      }
    }
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _SystemAccessDialog(
      gateway: gateway,
      tenantId: system['tenant_id'] as String,
    ),
  );
}

class _SystemActions extends StatelessWidget {
  const _SystemActions({
    required this.gateway,
    required this.tenantId,
    required this.serial,
    required this.username,
  });

  final PlatformOrganizationGateway gateway;
  final String tenantId;
  final String serial;
  final String? username;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SelectableText('System serial $serial'),
      if (username case final value?) SelectableText('Owner username $value'),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  _SystemAccessDialog(gateway: gateway, tenantId: tenantId),
            ),
            child: const Text('System access'),
          ),
          OutlinedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  _SystemCutoverDialog(gateway: gateway, tenantId: tenantId),
            ),
            child: const Text('Username cutover'),
          ),
        ],
      ),
    ],
  );
}

class _SystemAccessDialog extends StatefulWidget {
  const _SystemAccessDialog({required this.gateway, required this.tenantId});

  final PlatformOrganizationGateway gateway;
  final String tenantId;

  @override
  State<_SystemAccessDialog> createState() => _SystemAccessDialogState();
}

class _SystemAccessDialogState extends State<_SystemAccessDialog> {
  _Row? _details;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run([Future<Object?> Function()? action]) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action?.call();
      final row = await widget.gateway.rpc<Map<String, dynamic>?>(
        'platform_system_details',
        {'p_tenant_id': widget.tenantId},
      );
      if (mounted) setState(() => _details = row);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = _details;
    return AlertDialog(
      title: const Text('System access'),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error case final error?) _Problem(error),
            if (row != null) ...[
              SelectableText('System serial ${row['serial']}'),
              if (row['username'] case final String username)
                SelectableText('Owner username $username'),
              if (row['owner_email'] case final String email)
                Text('Owner email $email'),
              Text(switch (row['owner_status']) {
                'awaiting_verification' =>
                  'Waiting for the owner to verify their email.',
                'pending' || 'processing' => 'Preparing owner credentials.',
                'sent' => 'Credentials sent. Waiting for first sign-in.',
                'completed' => 'Owner password setup complete.',
                'failed' || 'expired' => 'Owner credentials need reissue.',
                _ => 'Owner credential status unavailable.',
              }),
            ] else if (!_busy && _error == null)
              const Text('This system has no new owner handover yet.'),
          ],
        ),
      ),
      actions: [
        if (row?['can_request_verification'] == true)
          TextButton(
            onPressed: _busy
                ? null
                : () => _run(
                    () => widget.gateway.systemOwnerVerification(
                      'request_code',
                      {'verification_id': row!['verification_id']},
                    ),
                  ),
            child: const Text('Send verification email'),
          ),
        if (row?['can_reissue'] == true)
          TextButton(
            onPressed: _busy
                ? null
                : () => _run(
                    () => widget.gateway.rpc('platform_reissue_system_owner', {
                      'p_tenant_id': widget.tenantId,
                    }),
                  ),
            child: const Text('Reissue owner credentials'),
          ),
        TextButton(
          onPressed: _busy ? null : () => _run(),
          child: const Text('Refresh'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _SystemCutoverDialog extends StatefulWidget {
  const _SystemCutoverDialog({required this.gateway, required this.tenantId});

  final PlatformOrganizationGateway gateway;
  final String tenantId;

  @override
  State<_SystemCutoverDialog> createState() => _SystemCutoverDialogState();
}

class _SystemCutoverDialogState extends State<_SystemCutoverDialog> {
  final _requestId = const Uuid().v4();
  _Row? _status;
  bool _busy = false;
  String? _error;

  PlatformOrganizationGateway get _gateway => widget.gateway;
  String get _migration => _status!['migration_id'] as String;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run([Future<Object?> Function()? command]) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await command?.call();
      final row = await _gateway.rpc<Map<String, dynamic>>(
        'platform_system_cutover_status',
        {'p_tenant_id': widget.tenantId},
      );
      if (mounted) setState(() => _status = row);
    } on PlatformOrganizationFailure catch (error) {
      if (mounted) {
        setState(
          () => _error = switch (error.code) {
            'SYSTEM_CUTOVER_ROSTER_CHANGED' => 'The existing roster changed. Access remains on the current accounts.',
            'SYSTEM_CUTOVER_NOT_READY' =>
              'Every replacement account must complete password setup.',
            _ => _message(error),
          },
        );
      }
    } on Exception {
      if (mounted) setState(() => _error = 'Could not reach Jentra OS.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stageOwner(_Row row) async {
    String? verification;
    final saved = await _edit(
      context,
      'Prepare owner username',
      'The owner verifies this mailbox and changes their temporary password before the cutover.',
      [
        _Field(
          'email',
          'Owner email',
          initial: row['email'] as String? ?? '',
          email: true,
        ),
      ],
      (values) async {
        final result = await _gateway.rpc<Map<String, dynamic>>(
          'platform_stage_system_owner_cutover',
          {'p_migration_id': _migration, 'p_owner_email': values['email']},
        );
        verification = result['verification_id'] as String?;
      },
      submit: 'Prepare owner',
    );
    if (!mounted || !saved) return;
    await _run(
      verification == null
          ? null
          : () => _gateway.systemOwnerVerification('request_code', {
              'verification_id': verification,
            }),
    );
  }

  Future<void> _staff(_Row row) async {
    final id = row['replacement_id'];
    if (id != null) {
      await showStaffCredentialActions(context, _gateway, {
        ...row,
        'identity_id': id,
        'status': row['credential_status'],
      }, allowRevoke: false);
    } else {
      await showStaffCredentialIssuer(
        context,
        gateway: _gateway,
        tenantId: widget.tenantId,
        displayName: row['display_name'] as String? ?? '',
        suggestedEmail: row['email'] as String?,
        entities: {
          for (final entity in _rows(_status!['entities']))
            entity['id'] as String: entity['name'] as String,
        },
        legalEntityId: row['legal_entity_id'] as String?,
        branchId: row['branch_id'] as String?,
        employeeId: row['employee_id'] as String?,
        migrationId: _migration,
        oldMembershipId: row['legacy_membership_id'] as String?,
        oldLinkId: row['legacy_link_id'] as String?,
      );
    }
    if (mounted) await _run();
  }

  Future<void> _confirm({required bool rollback}) async {
    final serial = _status!['serial'];
    final changed = await _edit(
      context,
      rollback
          ? 'Restore previous usernames'
          : 'Activate replacement usernames',
      'Confirm system $serial to ${rollback ? 'restore the prior access' : 'switch to the verified replacement accounts'}.',
      [
        const _Field('serial', 'Confirm system serial'),
        if (rollback) const _Field('reason', 'Reason for rollback'),
      ],
      (values) async {
        if (values['serial']?.toUpperCase() != serial) {
          throw const PlatformOrganizationFailure('SYSTEM_SERIAL_MISMATCH');
        }
        await _gateway.rpc(
          rollback
              ? 'platform_rollback_system_cutover'
              : 'platform_commit_system_cutover',
          {
            'p_migration_id': _migration,
            if (rollback) 'p_reason': values['reason'],
          },
        );
      },
      submit: rollback ? 'Restore prior access' : 'Activate replacements',
      destructive: true,
    );
    if (mounted && changed) await _run();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final phase = status?['status'];
    final roster = _rows(status?['roster'] ?? const []);
    final canCommit =
        phase == 'preparing' &&
        roster.isNotEmpty &&
        roster.every((row) => row['ready'] == true);
    return AlertDialog(
      title: const Text('Username cutover'),
      scrollable: true,
      content: SizedBox(
        width: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error case final error?) _Problem(error),
            if (status != null) ...[
              Text('System ${status['serial']}'),
              Text(switch (phase) {
                'preparing' =>
                  'Current accounts retain access during verification.',
                'completed' => 'Replacement accounts are active.',
                'rolled_back' => 'Previous access restored.',
                _ when status['can_start'] == true =>
                  'Prepare the owner, HR Managers, and Employee app accounts.',
                _ =>
                  'An eligible legacy system must have one identifiable owner.',
              }),
              for (final row in roster)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    row['display_name'] as String? ?? 'Unassigned recipient',
                  ),
                  subtitle: Text(
                    '${switch (row['kind']) {
                      'owner' => 'Owner',
                      'hr_manager' => 'HR Manager',
                      _ => 'Employee',
                    }} · ${row['username'] ?? 'Username pending'} · ${row['ready'] == true ? 'Ready' : staffCredentialStatus(row['credential_status'])}',
                  ),
                  trailing: phase != 'preparing' || row['ready'] == true
                      ? null
                      : row['kind'] != 'owner'
                      ? TextButton(
                          onPressed: _busy ? null : () => _staff(row),
                          child: const Text('Prepare'),
                        )
                      : row['replacement_id'] == null
                      ? TextButton(
                          onPressed: _busy ? null : () => _stageOwner(row),
                          child: const Text('Prepare'),
                        )
                      : TextButton(
                          onPressed: _busy
                              ? null
                              : () => showDialog<void>(
                                  context: context,
                                  builder: (_) => _SystemAccessDialog(
                                    gateway: _gateway,
                                    tenantId: widget.tenantId,
                                  ),
                                ),
                          child: const Text('Owner access'),
                        ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => _run(),
          child: const Text('Refresh'),
        ),
        if (status?['can_start'] == true)
          FilledButton(
            onPressed: _busy
                ? null
                : () => _run(
                    () => _gateway.rpc('platform_begin_system_cutover', {
                      'p_tenant_id': widget.tenantId,
                      'p_request_id': _requestId,
                    }),
                  ),
            child: const Text('Prepare cutover'),
          ),
        if (phase == 'preparing')
          FilledButton(
            onPressed: _busy || !canCommit
                ? null
                : () => _confirm(rollback: false),
            child: const Text('Activate replacements'),
          ),
        if (phase == 'completed')
          OutlinedButton(
            onPressed: _busy ? null : () => _confirm(rollback: true),
            child: const Text('Restore prior access'),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
