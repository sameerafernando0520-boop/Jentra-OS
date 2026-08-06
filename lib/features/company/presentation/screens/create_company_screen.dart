import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/components/brand_mark.dart';
import '../../application/company_models.dart';
import '../../application/company_state.dart';
import '../widgets/company_feedback.dart';
import '../widgets/company_sign_out_button.dart';

final class CreateCompanyScreen extends ConsumerStatefulWidget {
  const CreateCompanyScreen({super.key});

  @override
  ConsumerState<CreateCompanyScreen> createState() =>
      _CreateCompanyScreenState();
}

final class _CreateCompanyScreenState
    extends ConsumerState<CreateCompanyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _legalNameController = TextEditingController();
  final _currencyController = TextEditingController(text: 'LKR');
  final _countryController = TextEditingController(text: 'LK');
  final _timezoneController = TextEditingController(text: 'Asia/Colombo');

  @override
  void dispose() {
    _nameController.dispose();
    _legalNameController.dispose();
    _currencyController.dispose();
    _countryController.dispose();
    _timezoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusManager.instance.primaryFocus?.unfocus();
    final legalName = _legalNameController.text.trim();

    try {
      await ref
          .read(companyControllerProvider.notifier)
          .createCompany(
            CreateCompanyInput(
              name: _nameController.text.trim(),
              legalName: legalName.isEmpty ? null : legalName,
              currencyCode: _currencyController.text.trim().toUpperCase(),
              countryCode: _countryController.text.trim().toUpperCase(),
              timezone: _timezoneController.text.trim(),
            ),
          );
      if (mounted) context.go('/dashboard');
    } catch (error) {
      if (mounted) CompanyFeedback.showError(context, error);
    }
  }

  void _goBack() {
    if (Navigator.of(context).canPop()) {
      context.pop();
    } else {
      context.go('/company/select');
    }
  }

  @override
  Widget build(BuildContext context) {
    final controllerState = ref.watch(companyControllerProvider);
    final isSubmitting = switch (controllerState) {
      AsyncData(:final value) => value.isSubmitting,
      _ => false,
    };

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Go back',
          onPressed: isSubmitting ? null : _goBack,
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Create company'),
        actions: const [CompanySignOutButton(), SizedBox(width: 8)],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: BrandMark(),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Create a secure workspace',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You will become the owner. Jentra OS will prepare the '
                    'company membership, default branch, roles, and document '
                    'settings automatically.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Company details',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _nameController,
                              enabled: !isSubmitting,
                              autofocus: true,
                              textInputAction: TextInputAction.next,
                              textCapitalization: TextCapitalization.words,
                              autofillHints: const [
                                AutofillHints.organizationName,
                              ],
                              maxLength: 160,
                              decoration: const InputDecoration(
                                labelText: 'Company name',
                                hintText: 'Example: Acme Trading',
                                prefixIcon: Icon(Icons.business_outlined),
                              ),
                              validator: _validateCompanyName,
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _legalNameController,
                              enabled: !isSubmitting,
                              textInputAction: TextInputAction.next,
                              textCapitalization: TextCapitalization.words,
                              maxLength: 200,
                              decoration: const InputDecoration(
                                labelText: 'Legal name (optional)',
                                hintText: 'Registered business name',
                                prefixIcon: Icon(Icons.gavel_outlined),
                              ),
                            ),
                            const SizedBox(height: 8),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final isWide = constraints.maxWidth >= 500;
                                final currencyField = TextFormField(
                                  controller: _currencyController,
                                  enabled: !isSubmitting,
                                  textInputAction: TextInputAction.next,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  inputFormatters: [
                                    LengthLimitingTextInputFormatter(3),
                                    _upperCaseFormatter,
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: 'Currency',
                                    helperText: 'ISO code, for example LKR',
                                    prefixIcon: Icon(Icons.payments_outlined),
                                  ),
                                  validator: (value) => _validateCode(
                                    value,
                                    length: 3,
                                    label: 'currency',
                                  ),
                                );
                                final countryField = TextFormField(
                                  controller: _countryController,
                                  enabled: !isSubmitting,
                                  textInputAction: TextInputAction.next,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  inputFormatters: [
                                    LengthLimitingTextInputFormatter(2),
                                    _upperCaseFormatter,
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: 'Country',
                                    helperText: 'ISO code, for example LK',
                                    prefixIcon: Icon(Icons.public_outlined),
                                  ),
                                  validator: (value) => _validateCode(
                                    value,
                                    length: 2,
                                    label: 'country',
                                  ),
                                );

                                if (!isWide) {
                                  return Column(
                                    children: [
                                      currencyField,
                                      const SizedBox(height: 16),
                                      countryField,
                                    ],
                                  );
                                }

                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: currencyField),
                                    const SizedBox(width: 16),
                                    Expanded(child: countryField),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _timezoneController,
                              enabled: !isSubmitting,
                              textInputAction: TextInputAction.done,
                              autocorrect: false,
                              maxLength: 64,
                              decoration: const InputDecoration(
                                labelText: 'Timezone',
                                helperText:
                                    'IANA timezone, for example Asia/Colombo',
                                prefixIcon: Icon(Icons.schedule_outlined),
                              ),
                              validator: _validateTimezone,
                              onFieldSubmitted: (_) {
                                if (!isSubmitting) _submit();
                              },
                            ),
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              onPressed: isSubmitting ? null : _submit,
                              icon: isSubmitting
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.add_business_outlined),
                              label: Text(
                                isSubmitting
                                    ? 'Preparing workspace...'
                                    : 'Create company',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String? _validateCompanyName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Enter a company name.';
    if (name.length < 2) return 'Company name must have at least 2 characters.';
    return null;
  }

  static String? _validateCode(
    String? value, {
    required int length,
    required String label,
  }) {
    final code = value?.trim().toUpperCase() ?? '';
    if (code.length != length || !RegExp(r'^[A-Z]+$').hasMatch(code)) {
      return 'Enter a valid $length-letter $label code.';
    }
    return null;
  }

  static String? _validateTimezone(String? value) {
    final timezone = value?.trim() ?? '';
    if (timezone.isEmpty) return 'Enter a timezone.';
    if (timezone == 'UTC' || timezone == 'GMT') return null;
    if (!RegExp(r'^[A-Za-z_+\-]+(?:\/[A-Za-z0-9_+\-]+)+$').hasMatch(timezone)) {
      return 'Use an IANA timezone such as Asia/Colombo.';
    }
    return null;
  }

  static final TextInputFormatter _upperCaseFormatter =
      TextInputFormatter.withFunction((oldValue, newValue) {
        return newValue.copyWith(text: newValue.text.toUpperCase());
      });
}
