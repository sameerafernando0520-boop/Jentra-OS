import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import 'period_fx_controller.dart';
import '../operations/operational_read_access.dart';

class PeriodFxScreen extends ConsumerWidget {
  const PeriodFxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities = ref.watch(businessCapabilitiesProvider);
    if (capabilities.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (capabilities.hasError) {
      return Center(
        child: TextButton(
          onPressed: () => ref.invalidate(businessCapabilitiesProvider),
          child: const Text('Retry access check'),
        ),
      );
    }
    final controller = ref.watch(periodFxControllerProvider);
    return controller == null
        ? const Center(child: Text('Choose a branch with finance access.'))
        : PeriodFxWorkspace(key: ValueKey(controller), controller: controller);
  }
}

class PeriodFxWorkspace extends StatefulWidget {
  const PeriodFxWorkspace({super.key, required this.controller});
  final PeriodFxController controller;

  @override
  State<PeriodFxWorkspace> createState() => _PeriodFxWorkspaceState();
}

class _PeriodFxWorkspaceState extends State<PeriodFxWorkspace> {
  PeriodFxController get c => widget.controller;

  Future<void> confirm(String action, {String? sourceId}) async {
    final controller = c;
    final epoch = controller.readAccessEpoch;
    final accepted = await showOperationalReadDialog<bool>(
      context,
      controller,
      (dialogContext) => AlertDialog(
        title: Text(switch (action) {
          'soft_lock' => 'Soft lock this period?',
          'hard_lock' => 'Check and hard close?',
          'request_reopen' => 'Request a reopen?',
          'approve_reopen' => 'Approve independent reopen?',
          'post' => 'Post exchange revaluation?',
          _ => 'Reverse this revaluation?',
        }),
        content: SingleChildScrollView(
          child: Text(switch (action) {
            'soft_lock' => 'Ordinary posting will stop. Authorized period-end FX adjustments remain available.',
            'hard_lock' => 'The server checks bank, AR/AP and FX evidence. Failed checks are recorded as close exceptions.',
            'request_reopen' || 'approve_reopen' => 'A recent second-factor session is required. Complete MFA in your account security flow, then return here. The prior close stays in history.',
            'post' => 'The selected closing rate values remaining foreign open items. A prior active run is reversed and linked.',
            _ => 'The original frozen run and journal remain in history. An exact reversal posts in the selected period.',
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (accepted == true &&
        mounted &&
        identical(c, controller) &&
        controller.currentRead(epoch)) {
      await controller.execute(action, sourceId: sourceId);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      if (!c.verified || c.denied) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                c.error ?? 'Connect to verify finance access and restore the encrypted period draft.',
              ),
              if (c.busy) const CircularProgressIndicator(),
              TextButton(
                onPressed: c.online && !c.busy ? c.initialize : null,
                child: const Text('Verify access'),
              ),
            ],
          ),
        );
      }

      final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.7);
      Widget field(String key, String label, {double width = 260}) => SizedBox(
        width: width * scale,
        child: TextFormField(
          key: ValueKey('${c.periodId}-${c.formEpoch}-$key'),
          initialValue: c.form[key] as String? ?? '',
          enabled: !c.locked,
          decoration: InputDecoration(labelText: label),
          onChanged: (value) => c.field(key, value),
        ),
      );
      Widget button(String label, String action, {String? sourceId}) =>
          OutlinedButton(
            onPressed: c.online && !c.locked && c.can(action)
                ? () => confirm(action, sourceId: sourceId)
                : null,
            child: Text(label),
          );
      Widget next(String resource) => c.cursors[resource] == null
          ? const SizedBox.shrink()
          : TextButton(
              onPressed: c.busy ? null : () => c.page(resource),
              child: Text('More $resource'),
            );
      final rates = c.rows('rates');
      final currencies =
          rates
              .map((row) => row['source_currency_code'] as String)
              .toSet()
              .toList()
            ..sort();
      final selectedCurrency = c.form['currency_code'] as String?;
      final selectedRate = c.form['exchange_rate_id'] as String?;
      final eligibleRates = rates
          .where((row) => row['source_currency_code'] == selectedCurrency)
          .toList();
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Period & FX close',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Govern fiscal locks and value foreign open items against persisted closing rates.',
            ),
            if (c.error != null) ...[
              const SizedBox(height: 12),
              Text(
                c.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (c.message != null) ...[
              const SizedBox(height: 12),
              Text(c.message!),
            ],
            if (c.pending) ...[
              const SizedBox(height: 12),
              const Text(
                'A sealed request is pending. Retry it with the same identity.',
              ),
              FilledButton(
                onPressed: c.online && !c.busy ? c.retry : null,
                child: const Text('Retry saved request'),
              ),
            ],
            if (c.local?.errorCode == 'VERSION_CONFLICT' && !c.pending)
              TextButton(
                onPressed: c.busy ? null : c.resolveConflict,
                child: const Text('Reload current period before editing'),
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 340 * scale,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('period-${c.periodId}-${c.formEpoch}'),
                    initialValue: c.periodId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Fiscal period',
                    ),
                    items: [
                      for (final row in c.rows('periods'))
                        DropdownMenuItem(
                          value: row['id'] as String,
                          child: Text(
                            '${row['name']} · ${row['start_date']}–${row['end_date']} · ${row['state']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: c.locked
                        ? null
                        : (id) {
                            if (id != null) c.selectPeriod(id);
                          },
                  ),
                ),
                field('reason', 'Reason', width: 420),
                TextButton(
                  onPressed: c.busy ? null : c.refresh,
                  child: const Text('Refresh evidence'),
                ),
              ],
            ),
            next('periods'),
            if (c.period != null) ...[
              const SizedBox(height: 20),
              Text(
                'Period governance',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                'Current state: ${c.period!['state']} · version ${c.period!['version']}',
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (c.period!['state'] == 'open')
                    button('Soft lock', 'soft_lock'),
                  if (c.period!['state'] == 'soft_locked')
                    button('Check & hard close', 'hard_lock'),
                  if (c.period!['state'] == 'hard_locked')
                    button('Request reopen', 'request_reopen'),
                ],
              ),
              for (final request in c.rows('reopen_requests'))
                ListTile(
                  dense: true,
                  title: Text('Reopen request · ${request['reason']}'),
                  subtitle: Text('Requested ${request['requested_at']}'),
                  trailing: c.period!['state'] == 'hard_locked'
                      ? button(
                          'Approve reopen',
                          'approve_reopen',
                          sourceId: request['id'] as String,
                        )
                      : null,
                ),
              next('reopen_requests'),
              for (final event in c.rows('events'))
                ExpansionTile(
                  title: Text(
                    '${event['action']} · ${event['from_state']} → ${event['to_state']}',
                  ),
                  subtitle: Text('${event['created_at']} · ${event['reason']}'),
                  children: [
                    for (final exception
                        in (event['exceptions'] as List? ?? []))
                      ListTile(
                        title: Text((exception as Map)['code'].toString()),
                      ),
                  ],
                ),
              next('events'),
              const SizedBox(height: 24),
              Text(
                'Exchange revaluation',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text(
                'The source-currency open item remains unchanged; valuation journals are reversible.',
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  field('as_of', 'As-of date (YYYY-MM-DD)'),
                  SizedBox(
                    width: 240 * scale,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(
                        'currency-${c.formEpoch}-$selectedCurrency',
                      ),
                      initialValue: currencies.contains(selectedCurrency)
                          ? selectedCurrency
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Foreign currency',
                      ),
                      items: [
                        for (final currency in currencies)
                          DropdownMenuItem(
                            value: currency,
                            child: Text(currency),
                          ),
                      ],
                      onChanged: c.locked
                          ? null
                          : (value) => c.field('currency_code', value ?? ''),
                    ),
                  ),
                  SizedBox(
                    width: 350 * scale,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(
                        'rate-${c.formEpoch}-$selectedCurrency-$selectedRate',
                      ),
                      initialValue:
                          eligibleRates.any((row) => row['id'] == selectedRate)
                          ? selectedRate
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Persisted closing rate',
                      ),
                      items: [
                        for (final rate in eligibleRates)
                          DropdownMenuItem(
                            value: rate['id'] as String,
                            child: Text(
                              '${rate['rate']} · ${rate['effective_date']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: c.locked
                          ? null
                          : (value) => c.field('exchange_rate_id', value ?? ''),
                    ),
                  ),
                  button('Post revaluation', 'post'),
                ],
              ),
              next('rates'),
              for (final run in c.rows('runs'))
                ListTile(
                  title: Text(
                    '${run['currency_code']} · ${run['as_of']} · ${run['control_delta_base']} ${run['base_currency_code']}',
                  ),
                  subtitle: Text(
                    'Rate ${run['exchange_rate']} · ${run['item_count']} source items · ${run['reversal'] == null ? 'active' : 'reversed'}',
                  ),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: c.busy
                            ? null
                            : () => c.openDetail(run['id'] as String),
                        child: const Text('Source items'),
                      ),
                      if (run['reversal'] == null)
                        button(
                          'Reverse',
                          'reverse',
                          sourceId: run['id'] as String,
                        ),
                    ],
                  ),
                ),
              next('runs'),
              if (c.detailRunId != null) ...[
                const Divider(),
                Text(
                  'Frozen source snapshot · ${c.detailRunId}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final item in c.detail)
                  ListTile(
                    dense: true,
                    title: Text(
                      '${item['document_number']} · ${item['kind']} · ${item['open_amount']}',
                    ),
                    subtitle: Text(
                      'Original base ${item['open_base_amount']} · Control ${item['control_account_id']}',
                    ),
                  ),
                if (c.detailNext != null)
                  TextButton(
                    onPressed: c.busy ? null : c.moreDetail,
                    child: const Text('More source items'),
                  ),
              ],
            ],
          ],
        ),
      );
    },
  );
}
