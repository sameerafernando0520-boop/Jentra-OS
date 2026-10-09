import 'package:flutter/material.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

import '../employee_controller.dart';
import '../l10n/employee_strings.dart';
import 'employee_components.dart';
import 'employee_identity.dart';
import 'employee_surfaces.dart';

class EmployeeProfileScreen extends StatelessWidget {
  const EmployeeProfileScreen({required this.controller, super.key});
  final EmployeeController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final s = EmployeeStrings.of(context);
      final person = controller.identity;
      if (person == null) return const SizedBox.shrink();
      return Scaffold(
        appBar: AppBar(title: Text(s('profile'))),
        body: EmployeePageBody(
          children: [
            EmployeeIdentityHero(
              identity: person,
              photo: controller.profilePhoto,
              centered: true,
            ),
            EmployeeSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EmployeeHeading(s('makeItYours')),
                  const SizedBox(height: 8),
                  Text(
                    s('photoCopy'),
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: context.jentraColors.textSecondary),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    key: const Key('employee-choose-photo'),
                    onPressed: controller.photoBusy || controller.busy
                        ? null
                        : controller.chooseProfilePhoto,
                    icon: const Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 21,
                    ),
                    label: Text(
                      s(
                        controller.photoBusy
                            ? 'preparingPhoto'
                            : controller.profilePhoto == null
                            ? 'choosePhoto'
                            : 'changePhoto',
                      ),
                    ),
                  ),
                  if (controller.profilePhoto != null) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      key: const Key('employee-remove-photo'),
                      onPressed: controller.photoBusy || controller.busy
                          ? null
                          : controller.removeProfilePhoto,
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      label: Text(s('removePhoto')),
                    ),
                  ],
                  if (controller.photoBusy) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.phonelink_lock_outlined,
                        size: 18,
                        color: context.jentraColors.textSecondary,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          s('photoDeviceCopy'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: context.jentraColors.textSecondary,
                              ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (controller.photoError != null)
              EmployeeMessage(
                title: s.failure(controller.photoError!),
                error: true,
              ),
            EmployeeSectionHeader(title: s('workplaceDetails')),
            EmployeeSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in [
                    (s('company'), person.workspace.tenantName),
                    (s('entity'), person.workspace.entityName),
                    (s('branch'), person.workspace.branchName),
                    (s('timeZone'), person.workspace.timeZone),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.$1,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: context.jentraColors.textSecondary,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            entry.$2,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                  Text(
                    s('profileCopy'),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: context.jentraColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
