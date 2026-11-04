/// Transient link input. Never persist or format the bearer token in diagnostics.
final class FieldConfirmationLink {
  const FieldConfirmationLink.none()
    : present = false,
      token = null,
      delivery = false;
  const FieldConfirmationLink(this.token, {this.delivery = false})
    : present = true;
  final bool present;
  final bool delivery;
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
          return const {
            'confirm',
            'delivery',
          }.contains(Uri.decodeComponent(key).toLowerCase());
        } on Object {
          return key.toLowerCase().startsWith('confirm') ||
              key.toLowerCase().startsWith('delivery');
        }
      });
  final suspected =
      fragment.toLowerCase().startsWith('confirm') ||
      fragment.toLowerCase().startsWith('delivery') ||
      containsConfirmation(fragment) ||
      containsConfirmation(location.query);
  if (!suspected) return const FieldConfirmationLink.none();
  try {
    final parts = Uri(query: fragment).queryParametersAll;
    final delivery = parts.containsKey('delivery');
    final key = delivery ? 'delivery' : 'confirm';
    final tokens = parts[key];
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
        fragment != '$key=${tokens.single}') {
      return FieldConfirmationLink(null, delivery: delivery);
    }
    return FieldConfirmationLink(tokens.single, delivery: delivery);
  } on Object {
    return const FieldConfirmationLink(null);
  }
}
