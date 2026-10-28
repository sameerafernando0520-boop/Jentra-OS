import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/employee_gateway.dart';
import '../data/employee_self_service.dart';
import '../data/employee_workplace_time.dart';
import '../employee_self_service_controller.dart';
import '../l10n/employee_strings.dart';
import 'employee_components.dart';

String employeeServiceFailure(EmployeeFailure failure, EmployeeStrings s) =>
    switch (failure.code) {
      'FEATURE_NOT_INSTALLED' => s('serviceNotInstalled'),
      'PENDING_EXPIRED' => s('serviceExpired'),
      'PENDING_REQUEST' => s('servicePending'),
      'LOCAL_TIME_INVALID' => s('requestDateInvalid'),
      'DOCUMENT_EXPORT_UNAVAILABLE' => s('documentUnsupported'),
      _ => s.failure(failure),
    };

String serviceDate(
  Object? value,
  EmployeeStrings s, {
  bool time = false,
  String? zone,
}) {
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (parsed == null) return '—';
  final display = time && parsed.isUtc && zone != null
      ? employeeWorkplaceTime(parsed, zone)
      : parsed;
  return time
      ? DateFormat.yMMMd(s.language).add_Hm().format(display)
      : DateFormat.yMMMd(s.language).format(display);
}

String employeeServiceTitle(EmployeeService service) => switch (service) {
  EmployeeService.attendance => 'attendanceTitle',
  EmployeeService.attendanceRequests => 'attendanceRequests',
  EmployeeService.leavePolicies => 'leavePolicies',
  EmployeeService.leaveRequests => 'leaveHistory',
  EmployeeService.payslips => 'payTitle',
  EmployeeService.cases => 'casesTitle',
  EmployeeService.documents => 'documents',
  EmployeeService.inbox => 'inboxTitle',
};

class EmployeeServiceFeedback extends StatelessWidget {
  const EmployeeServiceFeedback({required this.controller, super.key});
  final EmployeeSelfServiceController controller;
  @override
  Widget build(BuildContext context) {
    final s = EmployeeStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.actionBusy) const LinearProgressIndicator(),
        if (controller.actionError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: EmployeeMessage(
              title: employeeServiceFailure(controller.actionError!, s),
              error: true,
            ),
          ),
        if (controller.pending != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: EmployeeMessage(
              title: s('servicePending'),
              warning: true,
              action: OutlinedButton(
                onPressed: controller.actionBusy ? null : controller.reconcile,
                child: Text(s('serviceCheck')),
              ),
            ),
          ),
        if (controller.confirmed)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: EmployeeMessage(
              title: s('serviceConfirmed'),
              icon: Icons.check_circle_outline,
            ),
          ),
        if (controller.notApplied)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: EmployeeMessage(
              title: s('serviceNotApplied'),
              icon: Icons.info_outline,
            ),
          ),
        if (controller.exportSaved)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: EmployeeMessage(
              title: s('documentSavedCopy'),
              icon: Icons.check_circle_outline,
            ),
          ),
      ],
    );
  }
}

class EmployeeServiceListState extends StatelessWidget {
  const EmployeeServiceListState({
    required this.controller,
    required this.service,
    super.key,
  });
  final EmployeeSelfServiceController controller;
  final EmployeeService service;
  @override
  Widget build(BuildContext context) {
    final s = EmployeeStrings.of(context);
    final error = controller.errors[service];
    if (controller.loading.contains(service)) {
      return const LinearProgressIndicator();
    }
    if (error != null) {
      return EmployeeMessage(
        title: employeeServiceFailure(error, s),
        error: true,
        action: OutlinedButton(
          onPressed: () => controller.load(service),
          child: Text(s('retry')),
        ),
      );
    }
    if (controller.pages[service]?.items.isEmpty ?? false) {
      return EmployeeMessage(title: s('serviceEmpty'));
    }
    return const SizedBox.shrink();
  }
}

class EmployeeServiceMore extends StatelessWidget {
  const EmployeeServiceMore({
    required this.controller,
    required this.service,
    super.key,
  });
  final EmployeeSelfServiceController controller;
  final EmployeeService service;
  @override
  Widget build(BuildContext context) =>
      controller.pages[service]?.nextCursor == null
      ? const SizedBox.shrink()
      : OutlinedButton(
          onPressed: controller.loading.contains(service)
              ? null
              : () => controller.load(service, more: true),
          child: Text(EmployeeStrings.of(context)('serviceLoadMore')),
        );
}

Future<DateTime?> pickEmployeeWallTime(
  BuildContext context,
  DateTime initial, {
  DateTime? firstDate,
  DateTime? lastDate,
}) async {
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: firstDate ?? DateTime.now().subtract(const Duration(days: 366)),
    lastDate: lastDate ?? DateTime.now().add(const Duration(days: 730)),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  return time == null
      ? null
      : DateTime(date.year, date.month, date.day, time.hour, time.minute);
}
