import 'package:web/web.dart' as web;
import 'browser_auth_return.dart';

BrowserAuthReturn captureBrowserAuthReturn() {
  final location = Uri.parse(web.window.location.href);
  final pending = parseBrowserAuthReturn(location);
  if (pending.present) {
    markBrowserAuthReturnCaptured();
    // Strip secrets and provider messages before SDK initialization or routing,
    // including failed exchanges. The remaining path is an ordinary login.
    web.window.history.replaceState(null, '', '${location.origin}/#/login');
  }
  return pending;
}
