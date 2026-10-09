import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/jentra_domain.dart'
    show ConnectivityState, TenantContext;
import 'package:jentra_platform/analytics_platform.dart';

import '../../app_providers.dart';
import 'integration_screen.dart' show integrationRpcProvider;
import '../report_export/report_export_controller.dart'
    show reportExportFilesProvider;

final governedExportReopenProvider = FutureProvider.autoDispose
    .family<String, String>((ref, id) async {
      ref.watch(authSessionRevisionProvider);
      final actor = await ref.watch(authenticatedActorProvider.future),
          s = ref.watch(activeTenantContextProvider),
          caps = await ref.watch(businessCapabilitiesProvider.future),
          online = await ref.watch(connectivityStateProvider.future),
          rpc = ref.watch(integrationRpcProvider);
      if (s == null ||
          actor != s.actorId ||
          rpc == null ||
          online != ConnectivityState.online ||
          !caps.contains('finance.reports.export')) {
        throw StateError('Current export authority required.');
      }
      final result = await GovernedAnalyticsExport(
        rpc,
        ref.watch(reportExportFilesProvider),
      ).reopen(s, id);
      return '${result.$1.rowCount} rows · ${result.$2['fileName']} · SHA256 ${result.$1.sha256}';
    });

class GovernedExportScreen extends ConsumerStatefulWidget {
  const GovernedExportScreen({super.key});
  @override
  ConsumerState<GovernedExportScreen> createState() =>
      _GovernedExportScreenState();
}

class _GovernedExportScreenState extends ConsumerState<GovernedExportScreen> {
  final id = TextEditingController();
  String? selected, message;
  bool busy = false;
  @override
  void dispose() {
    id.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = selected == null
        ? null
        : ref.watch(governedExportReopenProvider(selected!));
    ref.listen(activeTenantContextProvider, (_, _) {
      if (mounted) {
        setState(() {
          selected = null;
          message = null;
        });
      }
    });
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Governed export reopen',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const Text(
          'Create a governed export from a frozen pipeline or scenario workspace. Reopen its registered job here to verify the original exact bytes and current source/export permission.',
        ),
        TextField(
          controller: id,
          decoration: const InputDecoration(
            labelText: 'Registered export job ID',
          ),
          onSubmitted: (_) => _read(),
        ),
        Wrap(
          spacing: 12,
          children: [
            FilledButton(
              onPressed: busy ? null : _read,
              child: const Text('Reopen and verify'),
            ),
            OutlinedButton(
              onPressed: busy || selected == null ? null : _download,
              child: const Text('Download verified bytes'),
            ),
          ],
        ),
        if (busy) const LinearProgressIndicator(),
        if (message != null) Text(message!),
        if (result != null)
          result.when(
            skipLoadingOnRefresh: false,
            skipLoadingOnReload: false,
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const Text(
              'Saved export is unavailable under current source/export access.',
            ),
            data: (v) => SelectableText(v),
          ),
      ],
    );
  }

  void _read() {
    try {
      ProcessMetricScope(tenantId: id.text, legalEntityId: id.text);
      setState(() {
        selected = id.text;
        message = null;
      });
      ref.invalidate(governedExportReopenProvider(id.text));
    } catch (_) {
      setState(() => message = 'Enter a valid registered export ID.');
    }
  }

  Future<void> _download() async {
    final s = ref.read(activeTenantContextProvider),
        rpc = ref.read(integrationRpcProvider),
        job = selected;
    if (s == null || rpc == null || job == null) return;
    bool current() {
      if (!mounted) return false;
      final now = ref.read(activeTenantContextProvider);
      return _same(s, now) &&
          ref.read(connectivityStateProvider).value ==
              ConnectivityState.online &&
          (ref
                  .read(businessCapabilitiesProvider)
                  .value
                  ?.contains('finance.reports.export') ??
              false);
    }

    setState(() => busy = true);
    try {
      final delivered = await GovernedAnalyticsExport(
        rpc,
        ref.read(reportExportFilesProvider),
      ).download(s, job, current);
      if (current()) {
        setState(
          () => message = delivered
              ? 'Verified export written.'
              : 'Download cancelled.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Download denied or unconfirmed; current source and export access is required.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  bool _same(TenantContext a, TenantContext? b) =>
      b != null &&
      a.actorId == b.actorId &&
      a.tenantId == b.tenantId &&
      a.legalEntityId == b.legalEntityId &&
      a.branchId == b.branchId;
}
