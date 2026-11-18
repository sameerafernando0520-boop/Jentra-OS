// Advisory stock availability from the company catalogue. The server sends a
// state per product and per pickable warehouse with the time it was read; it
// never sends quantities and reserves nothing.

enum FieldStockState { inStock, outOfStock, notTracked, unknown }

FieldStockState _parse(Object? value) => switch (value) {
  'in_stock' => FieldStockState.inStock,
  'out_of_stock' => FieldStockState.outOfStock,
  'not_tracked' => FieldStockState.notTracked,
  _ => FieldStockState.unknown,
};

/// The state for [warehouseId], or for the whole branch when none is chosen.
/// Anything missing or unrecognised is unknown, never in stock.
FieldStockState fieldStockState(
  Map<String, dynamic> product,
  String? warehouseId,
) {
  final overall = _parse(product['stock_state']);
  if (warehouseId == null ||
      overall == FieldStockState.notTracked ||
      overall == FieldStockState.unknown) {
    return overall;
  }
  final rows = product['stock_by_warehouse'];
  if (rows is! List) return FieldStockState.unknown;
  for (final row in rows) {
    if (row is Map && row['warehouse_id'] == warehouseId) {
      final state = _parse(row['state']);
      return state == FieldStockState.notTracked
          ? FieldStockState.unknown
          : state;
    }
  }
  return FieldStockState.unknown;
}

String fieldStockLabel(FieldStockState state) => switch (state) {
  FieldStockState.inStock => 'In stock',
  FieldStockState.outOfStock => 'Out of stock',
  FieldStockState.notTracked => 'Stock not tracked',
  FieldStockState.unknown => 'Stock not known',
};

/// One line for the order form: when stock was read, and that it is a guide.
String fieldStockNote(List<Map<String, dynamic>> products) {
  for (final product in products) {
    final raw = product['stock_as_of'];
    final at = raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
    if (at == null ||
        _parse(product['stock_state']) == FieldStockState.unknown) {
      continue;
    }
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Stock checked at ${two(at.hour)}:${two(at.minute)}. It is a guide only: nothing is reserved.';
  }
  return 'Stock availability is not known right now.';
}
