import 'package:flutter/material.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_assurance.dart';

import 'assurance_planning_controller.dart';

/// Builds the existing template command with ordinary fields rather than JSON.
class AssuranceTemplateEditor extends StatelessWidget {
  const AssuranceTemplateEditor({super.key, required this.controller});
  final AssurancePlanningController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final locked = c.busy || c.pending;
    final controls = c.templateControls, requests = c.templateRequests;
    final codes = controls
        .map((row) => '${row['control_code']}')
        .where((code) => code.trim().isNotEmpty)
        .toSet();
    final theme = Theme.of(context);
    Widget heading(String title) => Padding(
      padding: const EdgeInsets.only(
        top: JentraSpacing.x4,
        bottom: JentraSpacing.x2,
      ),
      child: Semantics(
        header: true,
        child: Text(title, style: theme.textTheme.titleMedium),
      ),
    );
    Future<void> removeControl(int index) async {
      final code = controls[index]['control_code'];
      final linked = requests
          .where((request) => request['control_code'] == code)
          .length;
      if (linked > 0) {
        final remove = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove this draft control?'),
            content: Text(
              'This also removes $linked linked evidence request${linked == 1 ? '' : 's'} from this template draft. The saved template is unchanged.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep control'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove control'),
              ),
            ],
          ),
        );
        if (remove != true) return;
      }
      if (context.mounted && !c.pending && !c.busy) {
        c.removeTemplateControl(index);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Templates copy controls and evidence requests into each planned engagement. Their owners come from the audit area. Saving an existing template code creates a new immutable version; engagements already created keep their original controls.',
        ),
        heading('Controls (${controls.length}/50)'),
        if (controls.isEmpty)
          const Text('Add at least one control to save this template.'),
        for (var index = 0; index < controls.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: JentraSpacing.x3),
            child: JentraPanel(
              child: Column(
                key: ValueKey('template-control-$index-${controls.length}'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Control ${index + 1}',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove control ${index + 1}',
                        onPressed: locked ? null : () => removeControl(index),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  TextFormField(
                    key: ValueKey('template-control-code-$index'),
                    initialValue: '${controls[index]['control_code']}',
                    enabled: !locked,
                    decoration: const InputDecoration(
                      labelText: 'Control code, e.g. TRS-SIGN',
                    ),
                    onChanged: (value) =>
                        c.templateControlField(index, 'control_code', value),
                  ),
                  const SizedBox(height: JentraSpacing.x2),
                  TextFormField(
                    key: ValueKey('template-control-title-$index'),
                    initialValue: '${controls[index]['title']}',
                    enabled: !locked,
                    decoration: const InputDecoration(
                      labelText: 'Control title',
                    ),
                    onChanged: (value) =>
                        c.templateControlField(index, 'title', value),
                  ),
                  const SizedBox(height: JentraSpacing.x2),
                  const Text('Control risk'),
                  Wrap(
                    spacing: JentraSpacing.x2,
                    runSpacing: JentraSpacing.x1,
                    children: [
                      for (final risk in AssuranceSeverity.values)
                        ChoiceChip(
                          label: Text(
                            '${risk.name[0].toUpperCase()}${risk.name.substring(1)}',
                          ),
                          selected: controls[index]['risk'] == risk.name,
                          onSelected: locked
                              ? null
                              : (_) => c.templateControlField(
                                  index,
                                  'risk',
                                  risk.name,
                                ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: locked || controls.length >= 50
              ? null
              : c.addTemplateControl,
          icon: const Icon(Icons.add),
          label: const Text('Add template control'),
        ),
        heading('Evidence requests (${requests.length}/100)'),
        const Text(
          'Requests are optional. Each due date is the engagement period start plus the number of days below.',
        ),
        const SizedBox(height: JentraSpacing.x2),
        for (var index = 0; index < requests.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: JentraSpacing.x3),
            child: JentraPanel(
              child: Column(
                key: ValueKey('template-request-$index-${requests.length}'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Evidence request ${index + 1}',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove evidence request ${index + 1}',
                        onPressed: locked
                            ? null
                            : () => c.removeTemplateRequest(index),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      'template-request-control-$index-${requests[index]['control_code']}',
                    ),
                    initialValue:
                        codes.contains(requests[index]['control_code'])
                        ? requests[index]['control_code'] as String
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Control'),
                    items: [
                      for (final code in codes)
                        DropdownMenuItem(value: code, child: Text(code)),
                    ],
                    onChanged: locked
                        ? null
                        : (value) => c.templateRequestField(
                            index,
                            'control_code',
                            value,
                          ),
                  ),
                  const SizedBox(height: JentraSpacing.x2),
                  TextFormField(
                    key: ValueKey('template-request-description-$index'),
                    initialValue: '${requests[index]['description']}',
                    enabled: !locked,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Evidence needed',
                    ),
                    onChanged: (value) =>
                        c.templateRequestField(index, 'description', value),
                  ),
                  const SizedBox(height: JentraSpacing.x2),
                  TextFormField(
                    key: ValueKey('template-request-days-$index'),
                    initialValue: '${requests[index]['due_offset_days']}',
                    enabled: !locked,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Days after period start (1–365)',
                    ),
                    onChanged: (value) =>
                        c.templateRequestField(index, 'due_offset_days', value),
                  ),
                ],
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: locked || requests.length >= 100 || codes.isEmpty
              ? null
              : c.addTemplateRequest,
          icon: const Icon(Icons.add),
          label: const Text('Add template evidence request'),
        ),
      ],
    );
  }
}
