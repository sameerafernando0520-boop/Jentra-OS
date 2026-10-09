import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/jentra_domain.dart' show ConnectivityState;
import 'package:jentra_platform/analytics_platform.dart';

import '../../app_providers.dart';
import 'integration_screen.dart' show integrationRpcProvider;

final statementRatiosProvider = FutureProvider.autoDispose
    .family<Map<String, ExactRatio>, (String, String, String?)>((
      ref,
      ids,
    ) async {
      ref.watch(authSessionRevisionProvider);
      final actor = await ref.watch(authenticatedActorProvider.future),
          scope = ref.watch(activeTenantContextProvider);
      final caps = await ref.watch(businessCapabilitiesProvider.future);
      final online = await ref.watch(connectivityStateProvider.future);
      final rpc = ref.watch(integrationRpcProvider);
      if (actor == null ||
          scope?.actorId != actor ||
          scope?.legalEntityId == null ||
          !caps.contains('analytics.view') ||
          !caps.contains('finance.view') ||
          online != ConnectivityState.online ||
          rpc == null) {
        throw StateError('Current online financial source access required.');
      }
      return StatementRatioAdapter(rpc)
          .read(scope!, ids.$1, ids.$2, classificationId: ids.$3);
    });

class FinancialAnalyticsScreen extends ConsumerStatefulWidget {
  const FinancialAnalyticsScreen({super.key});
  @override
  ConsumerState<FinancialAnalyticsScreen> createState() =>
      _FinancialAnalyticsScreenState();
}

class _FinancialAnalyticsScreenState
    extends ConsumerState<FinancialAnalyticsScreen> {
  final profit = TextEditingController(),
      balance = TextEditingController(),
      classification = TextEditingController();
  (String, String, String?)? selection;
  @override
  void dispose() {
    profit.dispose();
    balance.dispose();
    classification.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = selection == null
        ? null
        : ref.watch(statementRatiosProvider(selection!));
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Financial ratios',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const Text(
          'Select authoritative profit-and-loss and balance-sheet publications with matching period, currency and ledger population.',
        ),
        TextField(
          controller: profit,
          decoration: const InputDecoration(
            labelText: 'Profit-and-loss publication ID',
          ),
        ),
        TextField(
          controller: balance,
          decoration: const InputDecoration(
            labelText: 'Balance-sheet publication ID',
          ),
          onSubmitted: (_) => _read(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: classification,
          decoration: const InputDecoration(
            labelText: 'Reviewed classification publication ID (optional)',
          ),
          onSubmitted: (_) => _read(),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: _read,
            child: const Text('Calculate named ratios'),
          ),
        ),
        if (value != null)
          value.when(
            skipLoadingOnRefresh: false,
            skipLoadingOnReload: false,
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const Text(
              'The selected publications are unavailable, incompatible or no longer permitted.',
            ),
            data: (ratios) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in ratios.entries)
                  ListTile(
                    title: Text(entry.key.replaceAll('_', ' ')),
                    subtitle: Text(
                      '${entry.value.exactValue ?? entry.value.unavailableReason} · numerator ${entry.value.numerator} / denominator ${entry.value.denominator}',
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        const Text(
          'A reviewed classification publication adds current, quick and gross-profit-margin formulas. Each result uses the frozen statements and exact six-decimal arithmetic.',
        ),
      ],
    );
  }

  void _read() {
    try {
      ProcessMetricScope(tenantId: profit.text, legalEntityId: balance.text);
      final c = classification.text.trim();
      if (c.isNotEmpty) ProcessMetricScope(tenantId: c, legalEntityId: c);
      setState(
        () => selection = (profit.text, balance.text, c.isEmpty ? null : c),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter two valid publication IDs.')),
      );
    }
  }
}
