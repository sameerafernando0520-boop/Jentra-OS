import 'package:web/web.dart' as web;
import 'field_confirmation_link.dart';

FieldConfirmationLink captureFieldConfirmationLink() {
  final link = parseFieldConfirmationLink(web.window.location.href);
  if (link.present) {
    try {
      // Remove fragment/query secrets before any SDK, routing or UI initialization.
      web.window.history.replaceState(null, '', '/');
    } on Object {
      return const FieldConfirmationLink(null);
    }
  }
  return link;
}
