import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jentra_domain/jentra_domain.dart';
import '../../app_providers.dart';
import 'posted_journal_controller.dart';

String postedJournalLocation(TenantContext scope, String journalId) => Uri(
  path: '/finance/journal-evidence',
  queryParameters: {
    'tenant': scope.tenantId,
    'entity': scope.legalEntityId!,
    'branch': scope.branchId!,
    'journal': journalId,
  },
).toString();

class PostedJournalLink extends StatelessWidget {
  const PostedJournalLink({
    super.key,
    required this.scope,
    required this.journalId,
    this.enabled = true,
  });
  final TenantContext scope;
  final String journalId;
  final bool enabled;
  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: enabled && scope.hasOperationalScope && journalId.isNotEmpty
        ? () => context.push(postedJournalLocation(scope, journalId))
        : null,
    icon: const Icon(Icons.receipt_long_outlined),
    label: const Text('Open posted journal'),
  );
}

class PostedJournalScreen extends ConsumerWidget {
  const PostedJournalScreen({super.key, required this.target});
  final PostedJournalTarget target;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(businessCapabilitiesProvider);
    if (caps.isLoading) return const Center(child: CircularProgressIndicator());
    if (caps.hasError) {
      return Center(
        child: TextButton(
          onPressed: () => ref.invalidate(businessCapabilitiesProvider),
          child: const Text('Retry access check'),
        ),
      );
    }
    final c = ref.watch(postedJournalControllerProvider(target));
    return c == null
        ? const Center(
            child: Text(
              'This journal destination is unavailable. Select a permitted finance scope.',
            ),
          )
        : PostedJournalWorkspace(key: ValueKey(c), controller: c);
  }
}

class PostedJournalWorkspace extends StatelessWidget {
  const PostedJournalWorkspace({super.key, required this.controller});
  final PostedJournalController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller, j = c.journal;
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Posted journal evidence',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: c.online && !c.busy ? c.refresh : null,
                icon: const Icon(Icons.refresh),
                label: const Text('Verify and refresh'),
              ),
              if (c.busy) const CircularProgressIndicator(),
            ],
          ),
          if (!c.online)
            const Text('Offline. Financial evidence has been cleared.'),
          if (c.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(c.error!),
            ),
          if (c.verified) ...[
            const SizedBox(height: 24),
            Text(
              '${j['document_number']} · ${j['posting_date']}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              '${j['branch_name']} · ${j['branch_status']} · ${j['line_count']} immutable lines',
            ),
            Text(
              'Transaction ${j['currency_code']} · base ${j['base_currency_code']} · FX ${j['exchange_rate']}',
            ),
            Text(
              'Whole journal base debit ${j['base_debit']} · credit ${j['base_credit']}',
            ),
            Text(
              'Transaction debit ${j['transaction_debit']} · credit ${j['transaction_credit']}',
            ),
            const SizedBox(height: 12),
            for (final k in [
              'id',
              'tenant_id',
              'legal_entity_id',
              'branch_id',
              'fiscal_period_id',
              'source_type',
              'source_id',
              'command_id',
              'request_id',
              'correlation_id',
              'created_at',
              'created_by',
            ])
              SelectableText('${_label(k)}: ${j[k]}'),
            const SizedBox(height: 12),
            const Text(
              'Account and branch labels are from the current catalogue. Amounts and dimension snapshots are immutable posted evidence.',
            ),
            if (j['stock_cost_access_required'] == true)
              const Text(
                'Current stock and cost access was verified for the linked movement branches.',
              ),
            const Divider(height: 32),
            Text(
              'Lines ${c.afterLine + 1}–${c.afterLine + c.rows.length} of ${j['line_count']}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final r in c.rows)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${r['line_number']}. ${r['account_code']} · ${r['account_name']}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Base debit ${r['base_debit']} · credit ${r['base_credit']}',
                      ),
                      Text(
                        '${r['currency_code']} debit ${r['transaction_debit']} · credit ${r['transaction_credit']}',
                      ),
                      SelectableText(
                        'Line ${r['id']} · Account ${r['account_id']} · ${r['account_status']}',
                      ),
                      if (r['source_line_id'] != null)
                        SelectableText('Source line ${r['source_line_id']}'),
                      if (r['party_id'] != null)
                        SelectableText('Party ${r['party_id']}'),
                      if (r['dimension_snapshot'] is Map)
                        for (final kind in ['cost_centre', 'project'])
                          if ((r['dimension_snapshot'] as Map)[kind] is Map)
                            Text(
                              _dimensionLabel(
                                kind,
                                (r['dimension_snapshot'] as Map)[kind] as Map,
                              ),
                            ),
                    ],
                  ),
                ),
              ),
            Wrap(
              spacing: 12,
              children: [
                if (c.previousPages.isNotEmpty)
                  OutlinedButton(
                    onPressed: c.busy ? null : c.previous,
                    child: const Text('Previous lines'),
                  ),
                if (c.nextCursor != null)
                  FilledButton(
                    onPressed: c.busy ? null : c.next,
                    child: const Text('Next lines'),
                  ),
              ],
            ),
          ],
        ],
      );
    },
  );
}

String _dimensionLabel(String kind, Map value) =>
    '${kind == 'cost_centre' ? 'Cost centre' : 'Project tag'} ${value['code']} · ${value['name']} · frozen version ${value['version']} · ${value['id']}';
String _label(String key) => switch (key) {
  'id' => 'Journal',
  'tenant_id' => 'Tenant',
  'legal_entity_id' => 'Entity',
  'branch_id' => 'Source branch',
  'fiscal_period_id' => 'Period',
  'source_type' => 'Source type',
  'source_id' => 'Source document',
  'command_id' => 'Command',
  'request_id' => 'Request',
  'correlation_id' => 'Correlation',
  'created_at' => 'Created',
  'created_by' => 'Actor',
  _ => key,
};
