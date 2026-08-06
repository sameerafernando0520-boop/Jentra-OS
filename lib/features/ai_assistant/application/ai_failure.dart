final class AiFailure implements Exception {
  const AiFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
