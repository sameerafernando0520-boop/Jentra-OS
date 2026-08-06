/// User-safe company feature failure.
///
/// [cause] and [stackTrace] are retained for diagnostics, while [toString]
/// exposes only the deliberately safe message.
final class CompanyFailure implements Exception {
  const CompanyFailure(this.userMessage, {this.cause, this.stackTrace});

  final String userMessage;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => userMessage;
}
