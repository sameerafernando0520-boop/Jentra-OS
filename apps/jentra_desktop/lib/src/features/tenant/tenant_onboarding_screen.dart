import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import 'workspace_creation.dart';

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
  bool _busy = false;
  String? _error;
  WorkspaceCreationRequest? _request;

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
    if (_busy || !_formKey.currentState!.validate()) return;
    final actor = ref.read(foundationGatewayProvider)?.currentUser?.id;
    if (actor == null) {
      setState(
        () => _error = 'Sign in to your workspace before creating a business.',
      );
      return;
    }
    final request = _request ??= WorkspaceCreationRequest(
      actorId: actor,
      idempotencyKey: const Uuid().v4(),
      name: _businessName.text.trim(),
      slug: _slug.text.trim().toLowerCase(),
      legalEntityName: _entityName.text.trim(),
      legalEntityCode: _entityCode.text.trim().toUpperCase(),
      branchName: _branchName.text.trim(),
      branchCode: _branchCode.text.trim().toUpperCase(),
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    WorkspaceCreationFailure? failure;
    try {
      await ref.read(tenantListProvider.notifier).createTenant(request);
    } on WorkspaceCreationException catch (error) {
      failure = error.failure;
    } on Object {
      failure = WorkspaceCreationFailure.unconfirmed;
    }
    if (!mounted || !identical(_request, request)) return;
    setState(() {
      _busy = false;
      if (failure == null) return;
      _error = switch (failure) {
        WorkspaceCreationFailure.unavailable =>
          'Connect to your workspace before creating a business.',
        WorkspaceCreationFailure.sessionChanged =>
          'Your account changed. Sign in and start this form again.',
        WorkspaceCreationFailure.invalidValues =>
          'Review your workspace details and try again.',
        WorkspaceCreationFailure.duplicateSlug => 'This workspace address is already in use. Choose another workspace slug.',
        WorkspaceCreationFailure.accessDenied => 'Your account cannot create a workspace. Ask your administrator to check access.',
        _ => 'Workspace creation has not been confirmed. Your details are kept. Retry this same request to check its result.',
      };
      if (failure != WorkspaceCreationFailure.unconfirmed) _request = null;
    });
  }

  void _resetForActorChange() {
    if (!mounted) return;
    setState(() {
      _request = null;
      _busy = false;
      _error = null;
      _slugManuallyEdited = false;
      for (final controller in [
        _businessName,
        _slug,
        _entityName,
        _entityCode,
      ]) {
        controller.clear();
      }
      _branchName.text = 'Head Office';
      _branchCode.text = 'HQ';
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authenticatedActorProvider.select((state) => state.value), (
      previous,
      next,
    ) {
      if (previous != next) _resetForActorChange();
    });
    final readOnly = _busy || _request != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(JentraSpacing.x8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const JentraStatusBadge(
                label: 'Set up your business',
                tone: JentraStatusTone.success,
              ),
              const SizedBox(height: JentraSpacing.x4),
              Text(
                'Create your first Jentra workspace',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: JentraSpacing.x2),
              Text(
                'Create your business workspace with its first legal entity and branch. You will become its owner and can invite your team after setup.',
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: context.jentraColors.textSecondary),
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
                        description: 'The name your team sees and a unique workspace address.',
                      ),
                      const SizedBox(height: JentraSpacing.x4),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _businessName,
                              readOnly: readOnly,
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
                              readOnly: readOnly,
                              decoration: const InputDecoration(
                                labelText: 'Workspace slug',
                                hintText: 'example-holdings',
                              ),
                              onChanged: (_) => _slugManuallyEdited = true,
                              validator: (value) =>
                                  RegExp(r'^[a-z0-9][a-z0-9-]{2,62}$')
                                      .hasMatch(value ?? '')
                                  ? null
                                  : 'Use lowercase letters, numbers and hyphens.',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: JentraSpacing.x6),
                      const JentraSectionHeader(
                        title: 'Legal entity',
                        description: 'Use your registered business details. Review the LKR currency and accounting settings before your first posting.',
                      ),
                      const SizedBox(height: JentraSpacing.x4),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _entityName,
                              readOnly: readOnly,
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
                              readOnly: readOnly,
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
                              readOnly: readOnly,
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
                              readOnly: readOnly,
                              decoration: const InputDecoration(
                                labelText: 'Branch code',
                              ),
                              validator: _code,
                            ),
                          ),
                        ],
                      ),
                      if (_error case final message?) ...[
                        const SizedBox(height: JentraSpacing.x4),
                        JentraStatusBadge(
                          label: message,
                          tone: JentraStatusTone.danger,
                        ),
                      ],
                      const SizedBox(height: JentraSpacing.x6),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Set up an authenticator before using owner permissions.',
                            ),
                          ),
                          const SizedBox(width: JentraSpacing.x5),
                          JentraPrimaryButton(
                            label: _request == null
                                ? 'Create workspace'
                                : 'Retry workspace creation',
                            icon: Icons.arrow_forward,
                            loading: _busy,
                            onPressed: _busy ? null : _create,
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
      value == null || value.trim().length < 2 || value.trim().length > 160
      ? 'Enter 2–160 characters.'
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
