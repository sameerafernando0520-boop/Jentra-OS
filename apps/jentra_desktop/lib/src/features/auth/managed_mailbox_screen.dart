import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jentra_platform/jentra_platform.dart';

import '../platform_control/platform_organization_screen.dart';

class ManagedMailboxScreen extends ConsumerStatefulWidget {
  const ManagedMailboxScreen({
    required this.verificationId,
    this.staff = false,
    super.key,
  });

  final String? verificationId;
  final bool staff;

  @override
  ConsumerState<ManagedMailboxScreen> createState() =>
      _ManagedMailboxScreenState();
}

class _ManagedMailboxScreenState extends ConsumerState<ManagedMailboxScreen> {
  final _form = GlobalKey<FormState>();
  late final _id = TextEditingController(text: widget.verificationId);
  final _code = TextEditingController();
  bool _busy = false;
  bool _verified = false;
  String? _error;

  @override
  void dispose() {
    _id.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_busy || !_form.currentState!.validate()) return;
    final gateway = ref.read(platformOrganizationGatewayProvider);
    if (gateway == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = widget.staff
          ? await gateway.identity('verify_staff_mailbox', {
              'identity_id': _id.text.trim(),
              'code': _code.text.trim(),
            })
          : await gateway.systemOwnerVerification('verify_code', {
              'verification_id': _id.text.trim(),
              'code': _code.text.trim(),
            });
      if (result is Map && result['ok'] == false) {
        throw const PlatformOrganizationFailure('invalid_code');
      }
      if (mounted) {
        _code.clear();
        setState(() => _verified = true);
      }
    } on PlatformOrganizationFailure catch (error) {
      if (mounted) {
        setState(
          () => _error = error.code == 'invalid_code'
              ? 'The code is incorrect or expired. Ask for a new code.'
              : 'Verification could not be completed. Try again.',
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
    final connected = ref.watch(platformOrganizationGatewayProvider) != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Verify your Jentra email')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!connected)
                    const Text('Open the connected Jentra link in your email.')
                  else if (_verified) ...[
                    const Text(
                      'Email verified. Check your inbox for your username and temporary password.',
                    ),
                    TextButton(
                      onPressed: () => context.go('/login'),
                      child: const Text('Return to sign-in'),
                    ),
                  ] else ...[
                    const Text(
                      'Enter the verification ID and eight-digit code from your email.',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _id,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Verification ID',
                      ),
                      validator: (value) =>
                          RegExp(
                            r'^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$',
                          ).hasMatch(value?.trim() ?? '')
                          ? null
                          : 'Enter the verification ID.',
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _code,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 8,
                      decoration: const InputDecoration(
                        labelText: 'Email code',
                      ),
                      validator: (value) =>
                          RegExp(r'^\d{8}$').hasMatch(value ?? '')
                          ? null
                          : 'Enter the eight-digit code.',
                      onFieldSubmitted: (_) => _verify(),
                    ),
                    if (_error case final error?) Text(error),
                    FilledButton(
                      onPressed: _busy ? null : _verify,
                      child: Text(_busy ? 'Verifying…' : 'Verify email'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
