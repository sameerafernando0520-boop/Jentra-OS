import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app_providers.dart';
import 'report_export_controller.dart';

class ReportExportLink extends StatelessWidget {
  const ReportExportLink({
    super.key,
    required this.sourceType,
    required this.sourceId,
    required this.section,
    this.filters = const {},
    this.enabled = true,
    this.label = 'Export filtered evidence',
  });
  final String sourceType, sourceId, section;
  final Map<String, Object?> filters;
  final bool enabled;
  final String label;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: enabled
        ? () => context.go(
            Uri(
              path: '/finance/report-export',
              queryParameters: {
                'source': sourceType,
                'id': sourceId,
                'section': section,
                for (final e in filters.entries)
                  if (e.value != null) e.key: e.value.toString(),
              },
            ).toString(),
          )
        : null,
    icon: const Icon(Icons.file_download_outlined),
    label: Text(label),
  );
}

class ReportExportScreen extends ConsumerStatefulWidget {
  const ReportExportScreen({super.key, required this.initial});
  final Map<String, Object?> initial;
  @override
  ConsumerState<ReportExportScreen> createState() => _ReportExportScreenState();
}

class _ReportExportScreenState extends ConsumerState<ReportExportScreen> {
  ReportExportController? initialized;
  @override
  Widget build(BuildContext context) {
    final caps = ref.watch(businessCapabilitiesProvider);
    if (caps.isLoading) return const Center(child: CircularProgressIndicator());
    if (caps.hasError) {
      return Center(
        child: TextButton(
          onPressed: () => ref.invalidate(businessCapabilitiesProvider),
          child: const Text('Retry export access'),
        ),
      );
    }
    final c = ref.watch(reportExportControllerProvider);
    if (c == null) {
      return const Center(
        child: Text('Current finance and report export access is required.'),
      );
    }
    if (c != initialized) {
      initialized = c;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && initialized == c) c.initialize(widget.initial);
      });
    }
    return ReportExportWorkspace(key: ValueKey(c), controller: c);
  }
}

class ReportExportWorkspace extends StatelessWidget {
  const ReportExportWorkspace({super.key, required this.controller});
  final ReportExportController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller, meta = (c.document['metadata'] as Map?) ?? {};
      if (c.denied) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Access changed. Export evidence has been cleared.'),
              if (c.error != null) Text(c.error!),
              TextButton(
                onPressed: c.busy || !c.online ? null : c.refresh,
                child: const Text('Recheck export access'),
              ),
            ],
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Export report evidence',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Export the complete filtered section of a saved report. Scope, cutoff, source identity and file hash travel with the evidence.',
          ),
          const Text(
            'XLSX keeps amounts as text. Import CSV amount columns as text to retain exact precision.',
          ),
          if (c.busy) const LinearProgressIndicator(),
          if (!c.online)
            const Text(
              'Offline — encrypted export requests are retained. Fresh access is required before local delivery.',
            ),
          if (c.error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                c.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (c.message != null)
            Semantics(liveRegion: true, child: Text(c.message!)),
          const SizedBox(height: 16),
          SelectableText(
            'Source ${c.form['source_type'] ?? 'Choose a supported saved report'} · report ${c.form['source_id'] ?? '—'}',
          ),
          Text(
            'Section ${c.form['section'] ?? '—'} · status ${c.form['status'] ?? 'local'}',
          ),
          if (meta.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${meta['entity_name'] ?? meta['legal_entity_id']} · cutoff ${meta['as_of']}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${meta['row_count']} exact evidence rows · ${meta['currency_code'] ?? meta['base_currency_code']}',
                    ),
                    SelectableText(
                      'Tenant ${meta['tenant_id']} · entity ${meta['legal_entity_id']} · working branch ${meta['working_branch_id']}',
                    ),
                    Text('Source generated ${meta['generated_at']}'),
                    SelectableText('Filters ${meta['filters']}'),
                    SelectableText(
                      'Source SHA-256 ${c.document['source_hash']}',
                    ),
                  ],
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final format in ['xlsx', 'csv'])
                ChoiceChip(
                  label: Text(format.toUpperCase()),
                  selected: c.form['file_format'] == format,
                  onSelected: c.locked ? null : (_) => c.format(format),
                ),
              TextButton(
                onPressed: c.busy || !c.online ? null : c.refresh,
                child: const Text('Refresh export access'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed:
                  c.busy ||
                      !c.online ||
                      !c.verified ||
                      c.form['status'] == 'delivered'
                  ? null
                  : c.deliver,
              icon: const Icon(Icons.save_alt),
              label: Text(
                c.pending
                    ? 'Retry saved export'
                    : c.form['status'] == 'registered'
                    ? 'Retry local delivery'
                    : 'Choose file and export',
              ),
            ),
          ),
          if (c.pending)
            const Text(
              'The registration outcome is uncertain. Only the sealed export request can be retried.',
            ),
          if (c.form['status'] == 'registered')
            const Text(
              'Export metadata is registered. Local file delivery remains unconfirmed.',
            ),
          if (c.form['status'] == 'delivered')
            TextButton(
              onPressed: c.busy ? null : c.newExport,
              child: const Text('Create another export'),
            ),
          if (c.form['job_id'] != null)
            SelectableText('Export job ${c.form['job_id']}'),
        ],
      );
    },
  );
}
