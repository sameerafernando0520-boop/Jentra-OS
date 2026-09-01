import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

import '../../app_providers.dart';

class TenantOnboardingScreen extends ConsumerStatefulWidget {
  const TenantOnboardingScreen({super.key});

  @override
  ConsumerState<TenantOnboardingScreen> createState() =>
      _TenantOnboardingScreenState();
}

class _TenantOnboardingScreenState
    extends ConsumerState<TenantOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _businessName = TextEditingController();
  final _slug = TextEditingController();
  final _entityName = TextEditingController();
  final _entityCode = TextEditingController();
  final _branchName = TextEditingController(text: 'Head Office');
  final _branchCode = TextEditingController(text: 'HQ');
  bool _slugManuallyEdited = false;

  @override
  void dispose() {
    for (final controller in [
      _businessName,
      _slug,
      _entityName,
      _entityCode,
      _branchName,
      _branchCode,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    await ref
        .read(tenantListProvider.notifier)
        .createTenant(
          name: _businessName.text.trim(),
          slug: _slug.text.trim().toLowerCase(),
          legalEntityName: _entityName.text.trim(),
          legalEntityCode: _entityCode.text.trim().toUpperCase(),
          branchName: _branchName.text.trim(),
          branchCode: _branchCode.text.trim().toUpperCase(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tenantListProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(JentraSpacing.x8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const JentraStatusBadge(
                label: 'Secure business bootstrap',
                tone: JentraStatusTone.success,
              ),
              const SizedBox(height: JentraSpacing.x4),
              Text(
                'Create your first Jentra workspace',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: JentraSpacing.x2),
              Text(
                'This creates the tenant, legal entity, head-office branch, owner membership, scoped role, starter trial and first audit event in one transaction.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: context.jentraColors.textSecondary,
                ),
              ),
              const SizedBox(height: JentraSpacing.x6),
              JentraPanel(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const JentraSectionHeader(
                        title: 'Business group',
                        description:
                            'Your top-level tenant and URL-safe identity.',
                      ),
                      const SizedBox(height: JentraSpacing.x4),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _businessName,
                              autofocus: true,
                              decoration: const InputDecoration(
                                labelText: 'Business group name',
                                hintText: 'Example Holdings',
                              ),
                              onChanged: (value) {
                                if (!_slugManuallyEdited) {
                                  _slug.text = _slugify(value);
                                }
                              },
                              validator: _required,
                            ),
                          ),
                          const SizedBox(width: JentraSpacing.x4),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _slug,
                              decoration: const InputDecoration(
                                labelText: 'Workspace slug',
                                hintText: 'example-holdings',
                              ),
                              onChanged: (_) => _slugManuallyEdited = true,
                              validator: (value) =>
                                  RegExp(
                                    r'^[a-z0-9][a-z0-9-]{2,62}$',
                                  ).hasMatch(value ?? '')
                                  ? null
                                  : 'Use lowercase letters, numbers and hyphens.',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: JentraSpacing.x6),
                      const JentraSectionHeader(
                        title: 'Legal entity',
                        description:
                            'Accounting rules and LKR defaults are locked before first posting.',
                      ),
                      const SizedBox(height: JentraSpacing.x4),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _entityName,
                              decoration: const InputDecoration(
                                labelText: 'Registered entity name',
                                hintText: 'Example Trading (Pvt) Ltd',
                              ),
                              validator: _required,
                            ),
                          ),
                          const SizedBox(width: JentraSpacing.x4),
                          Expanded(
                            child: TextFormField(
                              controller: _entityCode,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                labelText: 'Entity code',
                                hintText: 'ETPL',
                              ),
                              validator: _code,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: JentraSpacing.x6),
                      const JentraSectionHeader(
                        title: 'First branch',
                        description:
                            'Operational transactions require a branch scope.',
                      ),
                      const SizedBox(height: JentraSpacing.x4),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _branchName,
                              decoration: const InputDecoration(
                                labelText: 'Branch name',
                              ),
                              validator: _required,
                            ),
                          ),
                          const SizedBox(width: JentraSpacing.x4),
                          Expanded(
                            child: TextFormField(
                              controller: _branchCode,
                              decoration: const InputDecoration(
                                labelText: 'Branch code',
                              ),
                              validator: _code,
                            ),
                          ),
                        ],
                      ),
                      if (state.hasError) ...[
                        const SizedBox(height: JentraSpacing.x4),
                        const JentraStatusBadge(
                          label:
                              'Creation failed. Review the values or try again.',
                          tone: JentraStatusTone.danger,
                        ),
                      ],
                      const SizedBox(height: JentraSpacing.x6),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Owner permissions stay locked until your session reaches MFA assurance level 2.',
                            ),
                          ),
                          const SizedBox(width: JentraSpacing.x5),
                          JentraPrimaryButton(
                            label: 'Create workspace',
                            icon: Icons.arrow_forward,
                            loading: state.isLoading,
                            onPressed: state.isLoading ? null : _create,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String? _required(String? value) =>
      value == null || value.trim().length < 2
      ? 'Enter at least 2 characters.'
      : null;

  static String? _code(String? value) =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{1,19}$').hasMatch(value ?? '')
      ? null
      : 'Use 2–20 letters or numbers.';

  static String _slugify(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}
