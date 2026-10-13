import 'errors.dart';
import 'tenant_context.dart';

/// Idempotent mutation contract shared by desktop and server commands.
final class CommandEnvelope<T> {
  CommandEnvelope({
    required this.commandId,
    required this.idempotencyKey,
    required this.context,
    required this.payload,
    DateTime? clientTimestamp,
    this.expectedEntityVersion,
  }) : clientTimestamp = (clientTimestamp ?? DateTime.now()).toUtc();

  final String commandId;
  final String idempotencyKey;
  final TenantContext context;
  final int? expectedEntityVersion;
  final DateTime clientTimestamp;
  final T payload;

  Map<String, Object?> toJson(Object? Function(T payload) encodePayload) =>
      <String, Object?>{
        'command_id': commandId,
        'idempotency_key': idempotencyKey,
        'context': context.toJson(),
        'expected_entity_version': expectedEntityVersion,
        'client_timestamp': clientTimestamp.toIso8601String(),
        'payload': encodePayload(payload),
      };
}

/// Structured success/failure response for a server command.
final class CommandResult<T> {
  const CommandResult._({
    required this.requestId,
    this.entity,
    this.warnings = const <String>[],
    this.error,
  });

  factory CommandResult.success({
    required String requestId,
    required T entity,
    List<String> warnings = const <String>[],
  }) => CommandResult<T>._(
    requestId: requestId,
    entity: entity,
    warnings: List.unmodifiable(warnings),
  );

  factory CommandResult.failure({
    required String requestId,
    required DomainError error,
  }) => CommandResult<T>._(requestId: requestId, error: error);

  final String requestId;
  final T? entity;
  final List<String> warnings;
  final DomainError? error;

  bool get isSuccess => error == null;
  bool get isFailure => error != null;
}
