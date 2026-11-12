import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jentra_platform/jentra_platform.dart';

import '../../app_providers.dart';
import 'account_security_screen.dart';

const _departments = {
  'hr': 'Human Resources',
  'sales': 'Sales',
  'procurement': 'Procurement',
  'finance': 'Finance',
  'inventory': 'Inventory',
  'projects': 'Projects',
  'service': 'Service',
};

final _departmentAccounts = FutureProvider.autoDispose
    .family<List<Map<String, Object?>>, String>((ref, tenantId) {
      return ref.watch(foundationGatewayProvider)!.departmentAccounts(tenantId);
    }, retry: (_, _) => null);

class DepartmentAccountsScreen extends ConsumerWidget {
  const DepartmentAccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gateway = ref.watch(foundationGatewayProvider);
    final actor = gateway?.currentUser?.id;
    final scope = ref.watch(activeTenantContextProvider);
    final profile = actor == null
        ? null
        : ref.watch(accountSecurityProfileProvider(actor));
    if (profile?.isLoading ?? false) {
      return const Center(child: CircularProgressIndicator());
    }
    if (gateway == null ||
        scope == null ||
        profile?.value?.isAdministrator != true) {
      return const Center(
        child: Text('Company administrator access required.'),
      );
    }
    final accountsProvider = _departmentAccounts(scope.tenantId);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => context.go('/account'),
            child: const Text('Back to account profile'),
          ),
        ),
        Text(
          'Department accounts',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Create a named manager account for a department in the current organization.',
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            icon: const Icon(Icons.person_add_alt),
            onPressed: () async {
              final created = await showDialog<String>(
                context: context,
                barrierDismissible: false,
                builder: (_) => _CreateAccount(gateway, scope.tenantId),
              );
              if (created == null || !context.mounted) return;
              ref.invalidate(accountsProvider);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Created $created. Share the temporary password privately.',
                  ),
                ),
              );
            },
            label: const Text('Create department account'),
          ),
        ),
        const SizedBox(height: 16),
        ref
            .watch(accountsProvider)
            .when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) =>
                  const Text('Department accounts could not be loaded.'),
              data: (accounts) => accounts.isEmpty
                  ? const Text('No department accounts yet.')
                  : Column(
                      children: [
                        for (final account in accounts)
                          ListTile(
                            leading: const Icon(Icons.badge_outlined),
                            title: Text(account['name'] as String),
                            subtitle: Text(
                              '${_departments[account['department']]} · ${account['username']}',
                            ),
                            trailing: Text(
                              account['must_change_password'] == true
                                  ? 'Password change required'
                                  : account['status'] as String,
                            ),
                          ),
                      ],
                    ),
            ),
      ],
    );
  }
}

class _CreateAccount extends StatefulWidget {
  const _CreateAccount(this.gateway, this.tenantId);

  final SupabaseFoundationGateway gateway;
  final String tenantId;

  @override
  State<_CreateAccount> createState() => _CreateAccountState();
}

class _CreateAccountState extends State<_CreateAccount> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _current = TextEditingController();
  String _department = 'hr';
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _username,
      _password,
      _confirm,
      _current,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.gateway.createDepartmentAccount(
        tenantId: widget.tenantId,
        name: _name.text.trim(),
        username: _username.text,
        department: _department,
        password: _password.text,
        confirmation: _confirm.text,
        currentPassword: _current.text,
      );
      if (mounted) Navigator.pop(context, organizationUsername(_username.text));
    } on AccountSecurityException catch (error) {
      if (mounted) {
        setState(
          () => _error = switch (error.code) {
            'incorrect_password' =>
              'Check your current administrator password.',
            'username_unavailable' => 'Choose a different username.',
            'forbidden' =>
              'Your account does not have access to create this manager.',
            'invalid_input' =>
              'Check the account details and the available subscription seats.',
            _ => 'The account could not be created.',
          },
        );
      }
    } on Object {
      if (mounted) setState(() => _error = 'The account could not be created.');
    } finally {
      if (mounted) {
        _current.clear();
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Create department account'),
      scrollable: true,
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              _field(
                'Name',
                _name,
                (value) =>
                    value == null ||
                        value.trim().isEmpty ||
                        value.trim().length > 100
                    ? 'Enter a name.'
                    : null,
              ),
              _field(
                'Username',
                _username,
                (value) =>
                    value == null ||
                        value.contains('@') ||
                        !isAccountLogin(value)
                    ? 'Enter a valid username.'
                    : null,
              ),
              DropdownButtonFormField<String>(
                initialValue: _department,
                decoration: const InputDecoration(labelText: 'Department'),
                items: [
                  for (final department in _departments.entries)
                    DropdownMenuItem(
                      value: department.key,
                      child: Text(department.value),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _department = value!),
              ),
              _field(
                'Temporary password',
                _password,
                (value) => isOrganizationPassword(value ?? '') ? null : 'Use at least 12 characters with uppercase, lowercase and a digit.',
                secret: true,
              ),
              _field(
                'Confirm password',
                _confirm,
                (value) => value == _password.text
                    ? null
                    : 'The passwords must match.',
                secret: true,
              ),
              _field(
                'Your current administrator password',
                _current,
                (value) => value == null || value.isEmpty
                    ? 'Enter your current password.'
                    : null,
                secret: true,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Create account'),
        ),
      ],
    ),
  );

  Widget _field(
    String label,
    TextEditingController controller,
    String? Function(String?) validator, {
    bool secret = false,
  }) => TextFormField(
    controller: controller,
    enabled: !_busy,
    decoration: InputDecoration(labelText: label),
    obscureText: secret,
    autocorrect: !secret,
    enableSuggestions: !secret,
    validator: validator,
  );
}
