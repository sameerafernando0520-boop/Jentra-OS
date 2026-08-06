sealed class AppException implements Exception {
  const AppException(this.message, {this.cause, this.stackTrace});

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => '$runtimeType: $message';
}

final class AppConfigurationException extends AppException {
  const AppConfigurationException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

final class AppDataException extends AppException {
  const AppDataException(super.message, {super.cause, super.stackTrace});
}
