/// A bounded page backed by an opaque server cursor.
final class CursorPage<T> {
  CursorPage({
    required List<T> items,
    required this.limit,
    this.nextCursor,
    this.filters = const <String, Object?>{},
    this.sort = const <String>[],
  }) : assert(limit > 0 && limit <= 200, 'limit must be from 1 to 200'),
       items = List.unmodifiable(items);

  final List<T> items;
  final int limit;
  final String? nextCursor;
  final Map<String, Object?> filters;
  final List<String> sort;

  bool get hasNextPage => nextCursor != null;
}
