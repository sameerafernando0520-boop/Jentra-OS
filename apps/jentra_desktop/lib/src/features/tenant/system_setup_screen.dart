import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import '../platform_control/platform_organization_screen.dart';

typedef SystemSetup = Map<String, dynamic>;

final systemSetupProvider = FutureProvider.autoDispose<SystemSetup?>((
  ref,
) async {
  ref.watch(authSessionRevisionProvider);
  final auth = ref.watch(foundationGatewayProvider);
  final gateway = ref.watch(platformOrganizationGatewayProvider);
  if (auth?.usesManagedUsername != true || gateway == null) return null;
  try {
    final setup = await gateway.rpc<SystemSetup?>('system_registration_status');
    if (setup != null) return setup;
    return await gateway.rpc<SystemSetup?>('system_replacement_status');
  } on PlatformOrganizationFailure catch (error) {
    if (error.code == 'PGRST202') return null;
    rethrow;
  }
}, retry: (_, _) => null);

class SystemSetupScreen extends ConsumerStatefulWidget {
  const SystemSetupScreen({super.key});

  @override
  ConsumerState<SystemSetupScreen> createState() => _SystemSetupScreenState();
}

class _SystemSetupScreenState extends ConsumerState<SystemSetupScreen> {
  final _form = GlobalKey<FormState>();
  final _entities = [_EntityDraft()];
  String _requestId = const Uuid().v4();
  bool _busy = false;
  String? _error;

  Future<void> _submit(SystemSetup setup) async {
    if (_busy || !_form.currentState!.validate()) return;
    _form.currentState!.save();
    final gateway = ref.read(platformOrganizationGatewayProvider);
    if (gateway == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await gateway.rpc('system_register_entities', {
        'p_tenant_id': setup['tenant_id'],
        'p_request_id': _requestId,
        'p_entities': _entities.map((entity) => entity.toJson()).toList(),
      });
      if (!mounted) return;
      final required = setup['registration_required'] == true;
      ref.invalidate(systemSetupProvider);
      ref.invalidate(tenantListProvider);
      if (required) {
        context.go('/dashboard');
      } else {
        setState(() {
          _requestId = const Uuid().v4();
          _entities
            ..clear()
            ..add(_EntityDraft());
        });
      }
    } on PlatformOrganizationFailure catch (error) {
      if (mounted) {
        setState(
          () => _error = switch (error.code) {
            'DUPLICATE_RECORD' =>
              'Organization and branch codes must be unique.',
            _ => 'Could not register these organizations. Check the details and retry.',
          },
        );
      }
    } on Exception {
      if (mounted) setState(() => _error = 'Could not reach Jentra OS.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(systemSetupProvider);
    final setup = state.value;
    if (state.isLoading && setup == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.hasError) {
      return Center(
        child: TextButton(
          onPressed: () => ref.invalidate(systemSetupProvider),
          child: const Text('Retry system setup access'),
        ),
      );
    }
    if (setup == null) {
      return const Center(child: Text('System owner access is required.'));
    }
    if (setup['replacement_pending'] == true) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Password setup is complete. Your system cutover is pending.',
            ),
            TextButton(
              onPressed: () => ref.invalidate(systemSetupProvider),
              child: const Text('Check cutover status'),
            ),
            TextButton(
              onPressed: () => ref.read(foundationGatewayProvider)?.signOut(),
              child: const Text('Sign out'),
            ),
          ],
        ),
      );
    }
    final existing = (setup['entities'] as List<dynamic>?) ?? const [];
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'System setup',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          SelectableText('System serial ${setup['serial']}'),
          const Text('Register each legal organization and its first branch.'),
          if (_busy) const LinearProgressIndicator(),
          if (_error case final message?) Text(message),
          for (final row in existing)
            if (row is Map)
              ListTile(
                title: Text(row['name'].toString()),
                subtitle: Text(
                  ((row['branches'] as List?) ?? const [])
                      .whereType<Map>()
                      .map((branch) => branch['name'])
                      .join(', '),
                ),
              ),
          for (var i = 0; i < _entities.length; i++)
            _EntityFields(
              key: ObjectKey(_entities[i]),
              number: i + 1,
              draft: _entities[i],
              enabled: !_busy,
              remove: _entities.length > 1 && !_busy
                  ? () => setState(() => _entities.removeAt(i))
                  : null,
            ),
          Wrap(
            spacing: 12,
            children: [
              OutlinedButton(
                onPressed: _busy || _entities.length >= 20
                    ? null
                    : () => setState(() => _entities.add(_EntityDraft())),
                child: const Text('Add another organization'),
              ),
              FilledButton(
                onPressed: _busy ? null : () => _submit(setup),
                child: const Text('Register organizations'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EntityDraft {
  final values = <String, String>{
    'name': '',
    'code': '',
    'branch_name': 'Head office',
    'branch_code': 'HQ',
  };

  Map<String, Object?> toJson() => {
    'name': values['name'],
    'code': values['code'],
    'branches': [
      {'name': values['branch_name'], 'code': values['branch_code']},
    ],
  };
}

class _EntityFields extends StatelessWidget {
  const _EntityFields({
    super.key,
    required this.number,
    required this.draft,
    required this.enabled,
    required this.remove,
  });

  final int number;
  final _EntityDraft draft;
  final bool enabled;
  final VoidCallback? remove;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Organization $number',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final field in const {
            'name': 'Legal organization name',
            'code': 'Organization code',
            'branch_name': 'First branch name',
            'branch_code': 'First branch code',
          }.entries)
            TextFormField(
              initialValue: draft.values[field.key],
              enabled: enabled,
              decoration: InputDecoration(labelText: field.value),
              validator: (value) => (value?.trim().isEmpty ?? true)
                  ? 'Enter ${field.value.toLowerCase()}.'
                  : null,
              onChanged: (value) => draft.values[field.key] = value,
              onSaved: (value) => draft.values[field.key] = value!.trim(),
            ),
          if (remove != null)
            TextButton(
              onPressed: remove,
              child: const Text('Remove organization'),
            ),
        ],
      ),
    ),
  );
}
