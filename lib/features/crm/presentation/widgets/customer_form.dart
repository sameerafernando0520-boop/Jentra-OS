import 'package:flutter/material.dart';

import '../../application/customer_models.dart';
import '../../application/customer_validators.dart';

final class CustomerForm extends StatefulWidget {
  const CustomerForm({
    required this.submitLabel,
    required this.isSubmitting,
    required this.onSubmit,
    required this.onCancel,
    this.initialCustomer,
    super.key,
  });

  final String submitLabel;
  final bool isSubmitting;
  final Customer? initialCustomer;
  final Future<void> Function(CustomerInput input) onSubmit;
  final VoidCallback onCancel;

  @override
  State<CustomerForm> createState() => _CustomerFormState();
}

final class _CustomerFormState extends State<CustomerForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _displayNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _mobileController;
  late final TextEditingController _taxNumberController;
  late final TextEditingController _creditLimitController;
  late final TextEditingController _paymentTermsController;
  late final TextEditingController _openingBalanceController;
  late final TextEditingController _tagsController;
  late final TextEditingController _notesController;
  bool _showValidation = false;

  @override
  void initState() {
    super.initState();
    final customer = widget.initialCustomer;
    _nameController = TextEditingController(text: customer?.name ?? '');
    _displayNameController = TextEditingController(
      text: customer?.displayName ?? '',
    );
    _emailController = TextEditingController(text: customer?.email ?? '');
    _phoneController = TextEditingController(text: customer?.phone ?? '');
    _mobileController = TextEditingController(text: customer?.mobile ?? '');
    _taxNumberController = TextEditingController(
      text: customer?.taxNumber ?? '',
    );
    _creditLimitController = TextEditingController(
      text: (customer?.creditLimit ?? 0).toStringAsFixed(2),
    );
    _paymentTermsController = TextEditingController(
      text: customer?.paymentTermsDays?.toString() ?? '',
    );
    _openingBalanceController = TextEditingController(
      text: (customer?.openingBalance ?? 0).toStringAsFixed(2),
    );
    _tagsController = TextEditingController(
      text: customer?.tags.join(', ') ?? '',
    );
    _notesController = TextEditingController(text: customer?.notes ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _displayNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _mobileController.dispose();
    _taxNumberController.dispose();
    _creditLimitController.dispose();
    _paymentTermsController.dispose();
    _openingBalanceController.dispose();
    _tagsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _showValidation = true);
    if (!_formKey.currentState!.validate()) return;

    final tags = _tagsController.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .take(30)
        .toList(growable: false);

    await widget.onSubmit(
      CustomerInput(
        name: _nameController.text,
        displayName: _displayNameController.text,
        email: _emailController.text,
        phone: _phoneController.text,
        mobile: _mobileController.text,
        taxNumber: _taxNumberController.text,
        creditLimit: double.tryParse(_creditLimitController.text.trim()) ?? 0,
        paymentTermsDays: _paymentTermsController.text.trim().isEmpty
            ? null
            : int.tryParse(_paymentTermsController.text.trim()),
        openingBalance:
            double.tryParse(_openingBalanceController.text.trim()) ?? 0,
        notes: _notesController.text,
        tags: tags,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      autovalidateMode: _showValidation
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FormSection(
            title: 'Customer information',
            subtitle: 'Basic identity and contact details.',
            children: [
              _FormFieldSlot(
                child: TextFormField(
                  controller: _nameController,
                  enabled: !widget.isSubmitting,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Legal or customer name *',
                    prefixIcon: Icon(Icons.business_outlined),
                  ),
                  validator: CustomerValidators.name,
                ),
              ),
              _FormFieldSlot(
                child: TextFormField(
                  controller: _displayNameController,
                  enabled: !widget.isSubmitting,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
              ),
              _FormFieldSlot(
                child: TextFormField(
                  controller: _emailController,
                  enabled: !widget.isSubmitting,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: CustomerValidators.email,
                ),
              ),
              _FormFieldSlot(
                child: TextFormField(
                  controller: _mobileController,
                  enabled: !widget.isSubmitting,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Mobile',
                    prefixIcon: Icon(Icons.phone_android_outlined),
                  ),
                ),
              ),
              _FormFieldSlot(
                child: TextFormField(
                  controller: _phoneController,
                  enabled: !widget.isSubmitting,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
              ),
              _FormFieldSlot(
                child: TextFormField(
                  controller: _taxNumberController,
                  enabled: !widget.isSubmitting,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Tax number',
                    prefixIcon: Icon(Icons.numbers_outlined),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _FormSection(
            title: 'Commercial settings',
            subtitle: 'Defaults used by future Sales and Finance modules.',
            children: [
              _FormFieldSlot(
                child: TextFormField(
                  controller: _creditLimitController,
                  enabled: !widget.isSubmitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Credit limit',
                    prefixIcon: Icon(Icons.credit_score_outlined),
                  ),
                  validator: (value) => CustomerValidators.nonnegativeMoney(
                    value,
                    'credit limit',
                  ),
                ),
              ),
              _FormFieldSlot(
                child: TextFormField(
                  controller: _paymentTermsController,
                  enabled: !widget.isSubmitting,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Payment terms (days)',
                    prefixIcon: Icon(Icons.event_available_outlined),
                  ),
                  validator: CustomerValidators.paymentTerms,
                ),
              ),
              _FormFieldSlot(
                child: TextFormField(
                  controller: _openingBalanceController,
                  enabled: !widget.isSubmitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Opening balance',
                    prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                  ),
                  validator: (value) =>
                      CustomerValidators.signedMoney(value, 'opening balance'),
                ),
              ),
              _FormFieldSlot(
                child: TextFormField(
                  controller: _tagsController,
                  enabled: !widget.isSubmitting,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Tags',
                    hintText: 'Retail, Priority, Colombo',
                    prefixIcon: Icon(Icons.sell_outlined),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _notesController,
            enabled: !widget.isSubmitting,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Notes',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton(
                onPressed: widget.isSubmitting ? null : widget.onCancel,
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: widget.isSubmitting ? null : _submit,
                icon: widget.isSubmitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(
                  widget.isSubmitting ? 'Saving…' : widget.submitLabel,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 720 ? 2 : 1;
                final width =
                    (constraints.maxWidth - (16 * (columns - 1))) / columns;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final child in children)
                      SizedBox(width: width, child: child),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

final class _FormFieldSlot extends StatelessWidget {
  const _FormFieldSlot({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
