/// A presentation-safe authentication failure.
///
/// Raw provider messages remain attached for diagnostics but must never be
/// rendered directly by a widget because they can disclose account state.
final class AuthFailure implements Exception {
  const AuthFailure(this.userMessage, {this.cause, this.stackTrace});

  final String userMessage;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => 'AuthFailure: $userMessage';
}
