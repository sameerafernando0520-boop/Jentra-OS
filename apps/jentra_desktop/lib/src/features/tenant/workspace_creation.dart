enum WorkspaceCreationFailure {
  unavailable,
  sessionChanged,
  invalidValues,
  duplicateSlug,
  accessDenied,
  unconfirmed,
}

final class WorkspaceCreationException implements Exception {
  const WorkspaceCreationException(this.failure);
  final WorkspaceCreationFailure failure;

  @override
  String toString() => 'WorkspaceCreationException(${failure.name})';
}

/// The actor and exact intent remain fixed while an uncertain creation retries.
final class WorkspaceCreationRequest {
  const WorkspaceCreationRequest({
    required this.actorId,
    required this.idempotencyKey,
    required this.name,
    required this.slug,
    required this.legalEntityName,
    required this.legalEntityCode,
    required this.branchName,
    required this.branchCode,
  });

  final String actorId;
  final String idempotencyKey;
  final String name;
  final String slug;
  final String legalEntityName;
  final String legalEntityCode;
  final String branchName;
  final String branchCode;
}
