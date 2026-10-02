/// Keep exact count/disposition inputs without caching server cost evidence.
/// In particular, empty_unit_cost is a user input and must survive unchanged.
Map<String, Object?> inventoryRecoveryInputs(Map<String, Object?> form) {
  const serverEvidence = {
    'grand_total',
    'variance_value',
    'carrying_value',
    'post_state',
    'journal_entry_id',
    'stock_movement_id',
    'base_value',
    'events',
  };
  Object? inputs(Object? value) {
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          if (!serverEvidence.contains(entry.key))
            entry.key as String: inputs(entry.value),
      };
    }
    if (value is List) return [for (final item in value) inputs(item)];
    return value;
  }

  return inputs(form) as Map<String, Object?>;
}
