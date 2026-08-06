final class InvoiceFailure implements Exception {
  const InvoiceFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
