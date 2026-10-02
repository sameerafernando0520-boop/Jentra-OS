import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';

import '../operations/operational_read_access.dart';

Future<void> reviewAndReloadProcurementConflict(
  BuildContext context, {
  required OperationalReadAccess access,
  required ProcurementGateway gateway,
  required TenantContext scope,
  required String kind,
  required Map<String, Object?> local,
  required Future<void> Function() discard,
  required bool Function() hasForm,
  required void Function(Map<String, Object?>) select,
  required Future<void> Function(Map<String, Object?>) edit,
}) async {
  final epoch = access.readAccessEpoch;
  final current = await compareProcurementConflict(
    context,
    access: access,
    gateway: gateway,
    scope: scope,
    kind: kind,
    local: local,
  );
  if (current == null || !access.currentRead(epoch)) return;
  await discard();
  if (hasForm() || !access.currentRead(epoch)) return;
  select(current);
  if (current['status'] == 'draft') await edit(current);
}

Future<Map<String, Object?>?> compareProcurementConflict(
  BuildContext context, {
  required OperationalReadAccess access,
  required ProcurementGateway gateway,
  required TenantContext scope,
  required String kind,
  required Map<String, Object?> local,
}) => showOperationalReadDialog<Map<String, Object?>>(
  context,
  access,
  (_) => _ConflictComparison(
    access: access,
    gateway: gateway,
    scope: scope,
    kind: kind,
    local: local,
  ),
);

class _ConflictComparison extends StatefulWidget {
  const _ConflictComparison({
    required this.access,
    required this.gateway,
    required this.scope,
    required this.kind,
    required this.local,
  });
  final OperationalReadAccess access;
  final ProcurementGateway gateway;
  final TenantContext scope;
  final String kind;
  final Map<String, Object?> local;
  @override
  State<_ConflictComparison> createState() => _ConflictComparisonState();
}

class _ConflictComparisonState extends State<_ConflictComparison> {
  Map<String, Object?>? current;
  String? error;
  late final int epoch;
  @override
  void initState() {
    super.initState();
    epoch = widget.access.readAccessEpoch;
    load();
  }

  Future<void> load() async {
    try {
      final gateway = widget.gateway;
      if (gateway is! ProcurementConflictGateway) {
        throw const DomainError(
          code: 'READ_UNAVAILABLE',
          message: 'Current comparison is unavailable. Keep this local draft and retry after reconnecting.',
        );
      }
      final result = await (gateway as ProcurementConflictGateway)
          .conflictDocument(
            widget.scope,
            widget.kind,
            widget.local['id'] as String,
          );
      if (mounted && widget.access.currentRead(epoch)) {
        setState(() => current = result);
      }
    } catch (failure) {
      if (!mounted || !widget.access.currentRead(epoch)) return;
      if (failure is DomainError &&
          const {
            'PERMISSION_DENIED',
            'ACCESS_DENIED',
            'MFA_REQUIRED',
            'AUTHENTICATION_REQUIRED',
          }.contains(failure.code)) {
        widget.access.denyReadAccess();
        return;
      }
      setState(
        () => error = failure is DomainError ? failure.message : 'The current comparison could not be verified. Keep your local draft and retry.',
      );
    }
  }

  Map<String, String> material(Map<String, Object?> document) {
    final result = <String, String>{};
    const audit = {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'created_by',
      'updated_by',
      'submitted_by',
      'approved_by',
      'created_at',
      'updated_at',
      'commercial_editor_id',
      'requester_id',
      'posted_by',
      'posted_at',
    };
    void visit(Object? value, String path) {
      if (value is Map) {
        for (final entry in value.entries) {
          final key = entry.key.toString();
          if (!key.startsWith('_') && !audit.contains(key)) {
            visit(entry.value, path.isEmpty ? key : '$path.$key');
          }
        }
      } else if (value is List) {
        if (value.isEmpty) result[path] = '[]';
        for (var i = 0; i < value.length; i++) {
          visit(value[i], '$path[${i + 1}]');
        }
      } else {
        result[path] = value == null
            ? '—'
            : value is String
            ? value
            : jsonEncode(value);
      }
    }

    visit(document, '');
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final localFields = material(widget.local);
    final serverFields = current == null
        ? <String, String>{}
        : material(current!);
    final fields = {...localFields.keys, ...serverFields.keys}.toList()..sort();
    return AlertDialog(
      title: const Text('Compare current and local revision'),
      content: SizedBox(
        width: 760,
        child: current == null
            ? error != null
                  ? Text(error!)
                  : const LinearProgressIndicator()
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Your encrypted local draft is preserved. Reload replaces this local editor with the reviewed current revision.',
                    ),
                    const SizedBox(height: 16),
                    for (final field in fields)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              field,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            SelectableText(
                              'Local: ${localFields[field] ?? 'Absent'}',
                            ),
                            SelectableText(
                              'Current: ${serverFields[field] ?? 'Absent'}',
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Keep local draft'),
        ),
        FilledButton(
          onPressed: current == null || !widget.access.currentRead(epoch)
              ? null
              : () => Navigator.pop(context, current),
          child: const Text('Reload current revision'),
        ),
      ],
    );
  }
}
