/// Transient link input. Never persist or format the bearer token in diagnostics.
final class FieldConfirmationLink {
  const FieldConfirmationLink.none() : present = false, token = null;
  const FieldConfirmationLink(this.token) : present = true;
  final bool present;
  final String? token;
}

FieldConfirmationLink parseFieldConfirmationLink(String rawLocation) {
  late final Uri location;
  try {
    location = Uri.parse(rawLocation);
  } on Object {
    return const FieldConfirmationLink(null);
  }
  // Uri normalizes unreserved escapes. Validate the original fragment so an
  // encoded parameter cannot be mistaken for the exact issued URL shape.
  final hash = rawLocation.indexOf('#');
  final fragment = hash < 0 ? '' : rawLocation.substring(hash + 1);
  bool containsConfirmation(String value) =>
      value.split(RegExp(r'[&?#]')).any((part) {
        final key = part.split('=').first;
        try {
          return Uri.decodeComponent(key).toLowerCase() == 'confirm';
        } on Object {
          return key.toLowerCase().startsWith('confirm');
        }
      });
  final suspected =
      fragment.toLowerCase().startsWith('confirm') ||
      containsConfirmation(fragment) ||
      containsConfirmation(location.query);
  if (!suspected) return const FieldConfirmationLink.none();
  try {
    final parts = Uri(query: fragment).queryParametersAll;
    final tokens = parts['confirm'];
    final local = const {
      'localhost',
      '127.0.0.1',
      '::1',
      '[::1]',
    }.contains(location.host);
    if (location.userInfo.isNotEmpty ||
        location.host.isEmpty ||
        !(location.scheme == 'https' || location.scheme == 'http' && local) ||
        location.path != '/' ||
        location.hasQuery ||
        parts.length != 1 ||
        tokens?.length != 1 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(tokens!.single) ||
        fragment != 'confirm=${tokens.single}') {
      return const FieldConfirmationLink(null);
    }
    return FieldConfirmationLink(tokens.single);
  } on Object {
    return const FieldConfirmationLink(null);
  }
}
