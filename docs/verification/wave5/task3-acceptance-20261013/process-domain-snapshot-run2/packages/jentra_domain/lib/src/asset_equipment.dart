import 'dart:convert';
import '../jentra_domain.dart';
import '../jentra_people.dart';
import '../jentra_service.dart';

final class AssetEquipmentSource {
  AssetEquipmentSource.fromJson(Map<String, Object?> row, TenantContext scope)
    : id = calendarUuid(row['id']),
      version = serviceInt(row['version'], min: 1),
      name = serviceText(row['name']),
      code = serviceCode(row['code']),
      digest = row['digest'] as String,
      _wire = jsonEncode(row) {
    calendarFields(row, {
      'id',
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'code',
      'name',
      'ownership',
      'in_service',
      'location_id',
      'location_name',
      'custodian_id',
      'custodian_name',
      'status',
      'version',
      'digest',
    });
    serviceScope(row, scope);
    serviceText(row['ownership']);
    CivilDate.parse(row['in_service'] as String);
    calendarUuid(row['location_id']);
    serviceText(row['location_name']);
    if (row['custodian_id'] != null) {
      calendarUuid(row['custodian_id']);
      serviceText(row['custodian_name']);
    } else if (row['custodian_name'] != null) {
      throw const FormatException('Custodian source identity changed.');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) ||
        row['status'] != 'active') {
      throw const FormatException('Choose an active exact asset source.');
    }
  }
  final String id, name, code, digest, _wire;
  final int version;
  Map<String, Object?> toJson() => serviceMap(jsonDecode(_wire));
}

final class AssetEquipmentLink {
  AssetEquipmentLink.fromJson(Map<String, Object?> row, TenantContext scope)
    : equipmentId = calendarUuid(row['equipment_id']),
      source = AssetEquipmentSource.fromJson(
        serviceMap(row['source_basis']),
        scope,
      ),
      reason = serviceText(row['reason'], 1000) {
    calendarFields(row, {
      'equipment_id',
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'asset_id',
      'asset_version',
      'source_digest',
      'source_basis',
      'reason',
      'created_by',
      'created_at',
    });
    serviceScope(row, scope);
    calendarUuid(row['created_by']);
    if (row['asset_id'] != source.id ||
        row['asset_version'] != source.version ||
        row['source_digest'] != source.digest) {
      throw const FormatException(
        'Immutable equipment source lineage changed.',
      );
    }
    DateTime.parse(row['created_at'] as String);
  }
  final String equipmentId, reason;
  final AssetEquipmentSource source;
}

final class AssetEquipmentCommands {
  static Set<String> fields(String action) => ServiceCommands.fields(action);
  static void validate(String action, Map<String, Object?> body) {
    if (action != 'equipment' || body['kind'] != 'asset') {
      throw const FormatException('Internal asset link action required.');
    }
    ServiceCommands.validate(action, body);
  }
}

abstract interface class AssetEquipmentRepository implements ServiceRepository {
  Future<ServicePage<AssetEquipmentSource>> sources(
    TenantContext scope, {
    String? after,
  });
  Future<AssetEquipmentLink> link(TenantContext scope, String equipmentId);
}
