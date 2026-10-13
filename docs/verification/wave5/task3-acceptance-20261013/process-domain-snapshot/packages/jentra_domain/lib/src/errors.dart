/// A stable, safe error contract that may cross application boundaries.
final class DomainError implements Exception {
  const DomainError({
    required this.code,
    required this.message,
    this.fieldDetails = const <String, String>{},
    this.retryable = false,
    this.correlationId,
  });

  final String code;
  final String message;
  final Map<String, String> fieldDetails;
  final bool retryable;
  final String? correlationId;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'message': message,
    'field_details': fieldDetails,
    'retryable': retryable,
    'correlation_id': correlationId,
  };

  factory DomainError.fromJson(Map<String, Object?> json) {
    final rawDetails = json['field_details'];
    return DomainError(
      code: json['code']! as String,
      message: json['message']! as String,
      fieldDetails: rawDetails is Map
          ? rawDetails.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const <String, String>{},
      retryable: json['retryable'] as bool? ?? false,
      correlationId: json['correlation_id'] as String?,
    );
  }

  @override
  String toString() => 'DomainError($code, $message)';
}
