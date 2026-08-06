/// Safe customer-module failure. The original cause is retained for logging,
/// but presentation code must display only [userMessage].
final class CustomerFailure implements Exception {
  const CustomerFailure(this.userMessage, {this.cause, this.stackTrace});

  final String userMessage;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => userMessage;
}
