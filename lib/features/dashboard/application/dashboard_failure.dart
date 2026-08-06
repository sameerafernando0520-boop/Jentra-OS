/// A safe, user-facing dashboard error with the original cause retained for
/// diagnostics. Presentation code must never render [cause] directly.
final class DashboardFailure implements Exception {
  const DashboardFailure(this.userMessage, {this.cause, this.stackTrace});

  final String userMessage;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => userMessage;
}
