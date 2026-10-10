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
            label: 'Overview',
            tone: JentraStatusTone.info,
          ),
        ),
        const SizedBox(height: JentraSpacing.x6),
        Expanded(
          child: JentraPanel(
            child: JentraEmptyState(
              icon: Icons.architecture_outlined,
              title: '$title overview',
              description:
                  'Posting and financial reports are not available from this page. '
                  'They require a connected workspace with the appropriate '
                  'business scope and permissions.',
              action: const JentraStatusBadge(
                label: 'Posting unavailable here',
                tone: JentraStatusTone.warning,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
