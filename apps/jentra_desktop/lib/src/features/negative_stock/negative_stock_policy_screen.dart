import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';

import '../../app_providers.dart';
import '../operations/operational_read_access.dart';
import 'negative_stock_policy_controller.dart';

class NegativeStockPolicyScreen extends ConsumerWidget {
  const NegativeStockPolicyScreen({super.key});
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
    final controller = ref.watch(negativeStockPolicyControllerProvider);
    return controller == null
        ? const Center(
            child: Text(
              'Choose a scope with stock-view and policy-management permission.',
            ),
          )
        : NegativeStockPolicyWorkspace(
            key: ValueKey(controller),
            controller: controller,
          );
  }
}

class NegativeStockPolicyWorkspace extends StatelessWidget {
  const NegativeStockPolicyWorkspace({required this.controller, super.key});
  final NegativeStockPolicyController controller;
  Future<void> _configure(BuildContext context) async {
    final epoch = controller.readAccessEpoch;
    final accepted = await showOperationalReadDialog<bool>(
      context,
      controller,
      (context) => AlertDialog(
        title: const Text('Record negative-stock policy?'),
        content: SingleChildScrollView(
          child: Text(
            '${controller.form['active'] == true ? 'Activate' : 'Deactivate'} the policy by appending a version. Existing issue values and history remain immutable.\n\nReason: ${controller.form['reason']}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Record policy version'),
          ),
        ],
      ),
    );
    if (accepted == true &&
        controller.currentRead(epoch) &&
        !controller.locked) {
      await controller.configure();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      if (c.accessDenied) {
        return const Center(
          child: Text(
            'Access changed. Saved work is retained securely. Reopen this workspace after checking your role.',
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Negative-stock policy',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          const Text(
            'The policy starts off. Explicit shortage issues use the last authoritative positive moving-average cost. Unknown cost basis and lot or serial shortages are blocked. Later receipts post linked variance corrections.',
          ),
          const SizedBox(height: 16),
          if (c.busy) const LinearProgressIndicator(),
          if (!c.online)
            const Text(
              'Offline · saved inputs are available. Connect to read policy or record a version.',
            ),
          Text(
            c.policy == null
                ? 'Current policy is unavailable.'
                : 'Current version ${c.policy!.version} · ${c.policy!.active ? 'Active' : 'Inactive'}',
          ),
          if (c.policy?.reason != null)
            Text('Recorded reason: ${c.policy!.reason}'),
          if (c.error != null)
            Text(
              c.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (c.message != null) Text(c.message!),
          const SizedBox(height: 12),
          SwitchListTile(
            key: const Key('negative-policy-active'),
            title: const Text('Allow explicitly authorized shortage issues'),
            subtitle: const Text(
              'Activation does not authorize an issue. Each override requires its own reason and current policy version.',
            ),
            value: c.form['active'] == true,
            onChanged: c.locked
                ? null
                : (active) => c.update({...c.form, 'active': active}),
          ),
          TextFormField(
            key: ValueKey('negative-policy-reason-${c.editorEpoch}'),
            initialValue: c.form['reason'] as String? ?? '',
            enabled: !c.locked,
            maxLength: 1000,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Configuration reason',
            ),
            onChanged: (reason) => c.update({...c.form, 'reason': reason}),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                onPressed: c.online && !c.locked && c.policy != null
                    ? () => _configure(context)
                    : null,
                child: const Text('Review policy change'),
              ),
              if (c.local?.pending != null)
                FilledButton(
                  onPressed: c.online && !c.busy
                      ? () => c.configure(retry: true)
                      : null,
                  child: const Text('Retry saved request'),
                ),
              TextButton(
                onPressed: c.busy || c.local?.pending != null
                    ? null
                    : c.discard,
                child: const Text('Discard local inputs'),
              ),
              TextButton(
                onPressed: c.busy || !c.online ? null : c.initialize,
                child: const Text('Refresh policy'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Deficits and linked corrections',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (!c.canViewCost)
            const Text('Cost-view permission is required for this evidence.')
          else ...[
            Wrap(
              spacing: 12,
              children: [
                for (final kind in NegativeStockEvidenceKind.values)
                  TextButton(
                    onPressed: c.online && !c.busy
                        ? () => c.loadEvidence(kind)
                        : null,
                    child: Text(
                      kind == NegativeStockEvidenceKind.deficits
                          ? 'Load deficit issues'
                          : 'Load linked corrections',
                    ),
                  ),
              ],
            ),
            if (c.rows.isEmpty)
              const Text(
                'No evidence records are shown. Load issues or corrections to review this scope.',
              ),
            for (final row in c.rows)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${row.kind == NegativeStockEvidenceKind.deficits ? 'Deficit' : 'Correction'} ${row.ledgerId} · ${row.values['posting_date']}',
                      ),
                      Text(
                        'Quantity ${row.values['quantity']} · Provisional value ${row.values['provisional_value']}',
                      ),
                      if (row.kind == NegativeStockEvidenceKind.deficits)
                        Text(
                          'Open quantity ${row.values['open_quantity']} · Policy version ${row.values['policy_version']}',
                        )
                      else
                        Text(
                          'Actual value ${row.values['actual_value']} · Variance ${row.values['variance']}',
                        ),
                      SelectableText(
                        'Source ${row.values[row.kind == NegativeStockEvidenceKind.deficits ? 'issue_movement_line_id' : 'movement_line_id']}',
                      ),
                      if (row.values['journal_entry_id'] != null)
                        SelectableText(
                          'Correction journal ${row.values['journal_entry_id']}',
                        ),
                    ],
                  ),
                ),
              ),
            if (c.cursor != null)
              TextButton(
                onPressed: c.online && !c.busy
                    ? () => c.loadEvidence(c.section, more: true)
                    : null,
                child: const Text('Load next fifty records'),
              ),
          ],
        ],
      );
    },
  );
}
