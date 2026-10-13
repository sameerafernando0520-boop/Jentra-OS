/// The complete authorization and business scope for a Jentra operation.
final class TenantContext {
  const TenantContext({
    required this.tenantId,
    required this.actorId,
    this.legalEntityId,
    this.branchId,
    this.warehouseId,
    this.projectId,
  });

  final String tenantId;
  final String actorId;
  final String? legalEntityId;
  final String? branchId;
  final String? warehouseId;
  final String? projectId;

  bool get hasAccountingScope => legalEntityId != null;
  bool get hasOperationalScope => legalEntityId != null && branchId != null;

  Map<String, Object?> toJson() => <String, Object?>{
    'tenant_id': tenantId,
    'actor_id': actorId,
    'legal_entity_id': legalEntityId,
    'branch_id': branchId,
    'warehouse_id': warehouseId,
    'project_id': projectId,
  };

  factory TenantContext.fromJson(Map<String, Object?> json) => TenantContext(
    tenantId: json['tenant_id']! as String,
    actorId: json['actor_id']! as String,
    legalEntityId: json['legal_entity_id'] as String?,
    branchId: json['branch_id'] as String?,
    warehouseId: json['warehouse_id'] as String?,
    projectId: json['project_id'] as String?,
  );

  TenantContext copyWith({
    String? tenantId,
    String? actorId,
    String? legalEntityId,
    String? branchId,
    String? warehouseId,
    String? projectId,
    bool clearLegalEntity = false,
    bool clearBranch = false,
    bool clearWarehouse = false,
    bool clearProject = false,
  }) => TenantContext(
    tenantId: tenantId ?? this.tenantId,
    actorId: actorId ?? this.actorId,
    legalEntityId: clearLegalEntity
        ? null
        : legalEntityId ?? this.legalEntityId,
    branchId: clearBranch ? null : branchId ?? this.branchId,
    warehouseId: clearWarehouse ? null : warehouseId ?? this.warehouseId,
    projectId: clearProject ? null : projectId ?? this.projectId,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TenantContext &&
          tenantId == other.tenantId &&
          actorId == other.actorId &&
          legalEntityId == other.legalEntityId &&
          branchId == other.branchId &&
          warehouseId == other.warehouseId &&
          projectId == other.projectId;

  @override
  int get hashCode => Object.hash(
    tenantId,
    actorId,
    legalEntityId,
    branchId,
    warehouseId,
    projectId,
  );
}
