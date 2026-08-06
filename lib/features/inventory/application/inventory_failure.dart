final class InventoryFailure implements Exception {
  const InventoryFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
