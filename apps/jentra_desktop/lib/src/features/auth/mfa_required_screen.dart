import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_platform/jentra_platform.dart';

import '../../app_providers.dart';

class MfaRequiredScreen extends ConsumerStatefulWidget {
  const MfaRequiredScreen({super.key});

  @override
  ConsumerState<MfaRequiredScreen> createState() => _MfaRequiredScreenState();
}

class _MfaRequiredScreenState extends ConsumerState<MfaRequiredScreen> {
  late Future<List<String>> _factors;
  final _code = TextEditingController();
  TotpEnrollment? _enrollment;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _factors = ref.read(foundationGatewayProvider)!.listVerifiedTotpFactorIds();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _enroll() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final enrollment = await ref
          .read(foundationGatewayProvider)!
          .enrollTotp();
      if (mounted) setState(() => _enrollment = enrollment);
    } on Object {
      if (mounted) setState(() => _error = 'Could not begin MFA enrollment.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify(String factorId) async {
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) {
      setState(
        () => _error = 'Enter the 6-digit code from your authenticator.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(foundationGatewayProvider)!
          .verifyTotp(factorId: factorId, code: _code.text.trim());
      ref.invalidate(tenantListProvider);
    } on Object {
      if (mounted) {
        setState(() => _error = 'The code was not accepted. Try a new code.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(JentraSpacing.x8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: JentraPanel(
          padding: const EdgeInsets.all(JentraSpacing.x8),
          child: FutureBuilder<List<String>>(
            future: _factors,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final factorId =
                  _enrollment?.factorId ??
                  (snapshot.data?.isNotEmpty == true
                      ? snapshot.data!.first
                      : null);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: context.jentraColors.successSurface,
                      borderRadius: BorderRadius.circular(JentraRadii.dialog),
                    ),
                    child: const Icon(
                      Icons.verified_user_outlined,
                      color: JentraColors.green700,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: JentraSpacing.x5),
                  Text(
                    'Multi-factor verification required',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: JentraSpacing.x2),
                  Text(
                    'This membership can perform privileged business actions. Jentra keeps every privileged route and RPC locked until this session reaches assurance level 2.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: context.jentraColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: JentraSpacing.x6),
                  if (factorId == null)
                    JentraPrimaryButton(
                      label: 'Set up authenticator',
                      icon: Icons.security_outlined,
                      loading: _busy,
                      onPressed: _busy ? null : _enroll,
                    )
                  else ...[
                    if (_enrollment case final enrollment?) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Add this secret to your authenticator app',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      const SizedBox(height: JentraSpacing.x2),
                      Container(
                        padding: const EdgeInsets.all(JentraSpacing.x3),
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          border: Border.all(
                            color: context.jentraColors.border,
                          ),
                          borderRadius: BorderRadius.circular(
                            JentraRadii.control,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                enrollment.secret,
                                style: const TextStyle(
                                  fontFamily: JentraTypography.monoFamily,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Copy secret',
                              onPressed: () => Clipboard.setData(
                                ClipboardData(text: enrollment.secret),
                              ),
                              icon: const Icon(Icons.copy, size: 18),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: JentraSpacing.x4),
                    ],
                    TextField(
                      controller: _code,
                      autofocus: true,
                      maxLength: 6,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: JentraTypography.monoFamily,
                        fontSize: 22,
                        letterSpacing: 8,
                      ),
                      onSubmitted: (_) => _verify(factorId),
                      decoration: const InputDecoration(
                        labelText: 'Authenticator code',
                        hintText: '000000',
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: JentraSpacing.x4),
                    JentraPrimaryButton(
                      label: 'Verify and continue',
                      icon: Icons.lock_open_outlined,
                      loading: _busy,
                      onPressed: _busy ? null : () => _verify(factorId),
                    ),
                  ],
                  if (_error case final error?) ...[
                    const SizedBox(height: JentraSpacing.x4),
                    JentraStatusBadge(
                      label: error,
                      tone: JentraStatusTone.danger,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}
