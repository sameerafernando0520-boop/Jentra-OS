import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

import '../data/employee_push.dart';
import '../l10n/employee_strings.dart';
import 'employee_components.dart';

class EmployeePushSettings extends StatelessWidget {
  const EmployeePushSettings({
    required this.coordinator,
    required this.authorized,
    required this.onRefresh,
    super.key,
  });
  final EmployeePushCoordinator? coordinator;
  final bool Function() authorized;
  final Future<void> Function() onRefresh;
  @override
  Widget build(BuildContext context) {
    final s = EmployeeStrings.of(context);
    final push = coordinator;
    if (push == null) {
      return EmployeeMessage(
        title: s('pushTitle'),
        message: s(
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android
              ? 'pushSetup'
              : 'pushAndroid',
        ),
      );
    }
    return AnimatedBuilder(
      animation: push,
      builder: (context, _) => JentraPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s('pushTitle'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              s(
                !authorized()
                    ? 'pushIdentity'
                    : push.error
                    ? 'pushError'
                    : push.enabled
                    ? 'pushEnabled'
                    : 'pushCopy',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('employee-push-enable'),
              onPressed: push.busy || !authorized()
                  ? null
                  : () => unawaited(push.enable()),
              icon: const Icon(Icons.notifications_outlined),
              label: Text(s(push.busy ? 'pushConnecting' : 'pushEnable')),
            ),
            if (push.enabled || push.error)
              TextButton(
                key: const Key('employee-push-disable'),
                onPressed: push.busy
                    ? null
                    : () async {
                        try {
                          await push.disconnect();
                        } on Object {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(s('pushError'))),
                            );
                          }
                        }
                      },
                child: Text(s('pushDisable')),
              ),
            if (push.updateAvailable)
              TextButton.icon(
                onPressed: () async {
                  await onRefresh();
                  push.clearUpdate();
                },
                icon: const Icon(Icons.refresh),
                label: Text(s('pushUpdate')),
              ),
          ],
        ),
      ),
    );
  }
}
