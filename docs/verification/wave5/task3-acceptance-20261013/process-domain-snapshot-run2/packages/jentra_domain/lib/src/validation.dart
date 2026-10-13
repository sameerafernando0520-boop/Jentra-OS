final class ValidationIssue {
  const ValidationIssue({required this.field, required this.message});

  final String field;
  final String message;
}

final class ValidationResult {
  ValidationResult(Iterable<ValidationIssue> issues)
    : issues = List.unmodifiable(issues);

  final List<ValidationIssue> issues;
  bool get isValid => issues.isEmpty;

  static ValidationResult valid() => ValidationResult(const []);
}
