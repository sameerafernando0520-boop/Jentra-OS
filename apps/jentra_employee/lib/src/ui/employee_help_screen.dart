import 'package:flutter/material.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

import '../l10n/employee_strings.dart';
import 'employee_components.dart';
import 'employee_surfaces.dart';

class EmployeeHelpScreen extends StatefulWidget {
  const EmployeeHelpScreen({
    this.initialTopic = 'account',
    this.onPrepareLeaveDraft,
    super.key,
  });
  final String initialTopic;
  final VoidCallback? onPrepareLeaveDraft;
  @override
  State<EmployeeHelpScreen> createState() => _EmployeeHelpScreenState();
}

class _EmployeeHelpScreenState extends State<EmployeeHelpScreen> {
  late String _topic = widget.initialTopic;
  static const _topics = {
    'account': ('accountAccess', Icons.person_outline),
    'leave': ('leave', Icons.event_available_outlined),
    'pay': ('pay', Icons.receipt_long_outlined),
    'reviews': ('reviews', Icons.fact_check_outlined),
    'documents': ('documents', Icons.folder_outlined),
  };
  @override
  Widget build(BuildContext context) {
    final s = EmployeeStrings.of(context);
    final prefix = switch (_topic) {
      'leave' => 'helpLeave',
      'pay' => 'helpPay',
      'reviews' => 'helpReviews',
      'documents' => 'helpDocuments',
      _ => 'helpAccount',
    };
    return Scaffold(
      appBar: AppBar(title: Text(s('hrHelp'))),
      body: EmployeePageBody(
        children: [
          EmployeeHeading(s('helpTopics'), large: true),
          Text(s('helpIntro')),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final topic in _topics.entries)
                ChoiceChip(
                  key: Key('employee-help-${topic.key}'),
                  avatar: Icon(topic.value.$2, size: 18),
                  label: Text(s(topic.value.$1)),
                  selected: _topic == topic.key,
                  onSelected: (_) => setState(() => _topic = topic.key),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                ),
            ],
          ),
          EmployeeSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EmployeeHeading(s(_topics[_topic]?.$1 ?? 'accountAccess')),
                const SizedBox(height: 20),
                for (var i = 1; i <= 3; i++) ...[
                  if (i > 1) const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: context.jentraColors.infoSurface,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          '$i',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: context.jentraColors.info),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(s('$prefix$i'))),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (_topic == 'leave' && widget.onPrepareLeaveDraft != null)
            FilledButton.icon(
              onPressed: widget.onPrepareLeaveDraft,
              icon: const Icon(Icons.edit_calendar_outlined),
              label: Text(s('createDraft')),
            ),
        ],
      ),
    );
  }
}
