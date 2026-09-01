/// Authorization resolved from server-managed role assignments and scopes.
final class PermissionSet {
  PermissionSet({required Iterable<String> permissions})
    : _permissions = Set.unmodifiable(permissions);

  final Set<String> _permissions;

  bool allows(String permission) => _permissions.contains(permission);
  bool allowsAny(Iterable<String> permissions) => permissions.any(allows);
  bool allowsAll(Iterable<String> permissions) => permissions.every(allows);
  Set<String> get values => _permissions;
}
