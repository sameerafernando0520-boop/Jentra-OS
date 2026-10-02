import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';

String operationalLocation(TenantContext scope, String kind, {String? id}) =>
    Uri(
      path: '/operations/documents',
      queryParameters: {
        'tenant': scope.tenantId,
        'entity': scope.legalEntityId!,
        'branch': scope.branchId!,
        'kind': kind,
        'id': ?id,
      },
    ).toString();

String? parseOperationalDocumentLocation(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null ||
      uri.hasAuthority ||
      uri.scheme.isNotEmpty ||
      uri.fragment.isNotEmpty ||
      uri.path != '/operations/documents' ||
      uri.queryParametersAll.length != 5 ||
      uri.queryParametersAll.values.any((values) => values.length != 1)) {
    return null;
  }
  final values = uri.queryParameters;
  if (!{'tenant', 'entity', 'branch', 'kind', 'id'}.containsAll(values.keys) ||
      !SupabaseOperationalGateway.kinds.contains(values['kind'])) {
    return null;
  }
  final uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  if ([
    'tenant',
    'entity',
    'branch',
    'id',
  ].any((key) => !uuid.hasMatch(values[key] ?? ''))) {
    return null;
  }
  return Uri(
    path: '/operations/documents',
    queryParameters: {
      'tenant': values['tenant'],
      'entity': values['entity'],
      'branch': values['branch'],
      'kind': values['kind'],
      'id': values['id'],
    },
  ).toString();
}

String? operationalNotificationLocation(SetupRecord record) {
  if (record.resource != BusinessSetupResource.notifications ||
      record.legalEntityId == null ||
      record.fields['branch_id'] is! String ||
      record.fields['aggregate_type'] is! String ||
      record.fields['aggregate_id'] is! String) {
    return null;
  }
  return parseOperationalDocumentLocation(
    Uri(
      path: '/operations/documents',
      queryParameters: {
        'tenant': record.tenantId,
        'entity': record.legalEntityId!,
        'branch': record.fields['branch_id'] as String,
        'kind': record.fields['aggregate_type'] as String,
        'id': record.fields['aggregate_id'] as String,
      },
    ).toString(),
  );
}

class OperationalLink extends StatelessWidget {
  const OperationalLink({
    super.key,
    required this.scope,
    required this.kind,
    this.id,
    this.label = 'Open source document',
  });
  final TenantContext scope;
  final String kind, label;
  final String? id;
  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed:
        scope.hasOperationalScope &&
            SupabaseOperationalGateway.kinds.contains(kind)
        ? () => context.push(operationalLocation(scope, kind, id: id))
        : null,
    icon: const Icon(Icons.description_outlined),
    label: Text(label),
  );
}
