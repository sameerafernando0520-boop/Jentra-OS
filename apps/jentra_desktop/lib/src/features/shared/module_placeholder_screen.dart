import 'package:flutter/material.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

class ModulePlaceholderScreen extends StatelessWidget {
  const ModulePlaceholderScreen({
    required this.title,
    required this.description,
    super.key,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(JentraSpacing.x6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        JentraSectionHeader(
          title: title,
          description: description,
          trailing: const JentraStatusBadge(
            label: 'Foundation route',
            tone: JentraStatusTone.info,
          ),
        ),
        const SizedBox(height: JentraSpacing.x6),
        Expanded(
          child: JentraPanel(
            child: JentraEmptyState(
              icon: Icons.architecture_outlined,
              title: '$title is mapped and ready',
              description:
                  'Its public facade, permissions, workflows, RPC contracts and acceptance criteria are defined in the approved blueprint. Delivery follows the phased roadmap.',
              action: const JentraStatusBadge(
                label: 'No legacy module restored',
                tone: JentraStatusTone.success,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
