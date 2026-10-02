import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../report_export/report_export_screen.dart';
import '../shared/report_wait.dart';
import 'operational_report_controller.dart';

class OperationalReportExport extends ConsumerWidget {
  const OperationalReportExport({
    super.key,
    required this.kind,
    required this.inputs,
    required this.label,
  });

  final String kind;
  final Map<String, Object?> inputs;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(operationalReportControllerProvider(kind));
    if (controller == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final id = controller.summary['id'] as String?;
        final prior = controller.local?.form['report_id'] as String?;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: controller.online && !controller.busy
                      ? () => controller.freeze(inputs)
                      : null,
                  icon: const Icon(Icons.inventory_outlined),
                  label: Text(
                    controller.pending ? 'Retry saved report request' : label,
                  ),
                ),
                if (prior != null && !controller.pending)
                  TextButton(
                    onPressed: controller.online && !controller.busy
                        ? controller.refresh
                        : null,
                    child: const Text('Recheck saved report'),
                  ),
              ],
            ),
            if (controller.reportWait.active)
              ReportWaitIndicator(
                state: controller.reportWait,
                onCancel: controller.cancelReportWait,
              )
            else if (controller.busy)
              const LinearProgressIndicator(),
            if (!controller.online)
              const Text('Offline. Saved report evidence has been cleared.'),
            if (controller.error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  controller.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (controller.pending)
              const Text(
                'An uncertain request is sealed. Retry uses the original selection and command identity.',
              ),
            if (id != null && controller.online) ...[
              Text(
                'Saved ${controller.summary['as_of']} · ${controller.summary['row_count']} rows · ${controller.summary['generated_at']}',
              ),
              if (controller.summary['open_amount'] != null)
                Text(
                  'Open ${controller.summary['currency_code']} ${controller.summary['open_amount']} · base ${controller.summary['open_base_amount']}',
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ReportExportLink(
                    sourceType: 'operational',
                    sourceId: id,
                    section: 'rows',
                    label: 'Export saved rows',
                  ),
                  if (kind != 'bank_reconciliation')
                    ReportExportLink(
                      sourceType: 'operational',
                      sourceId: id,
                      section: 'aging',
                      label: 'Export saved aging',
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}
