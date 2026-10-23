import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'employee_gateway.dart';
import 'employee_photo.dart';

/// Browser-only factory; import conditionally with dart.library.js_interop.
EmployeePhotoPicker createBrowserEmployeePhotoPicker() =>
    BrowserEmployeePhotoPicker();

/// One explicit user selection, without camera capture or directory access.
/// The controller still normalizes pixels and verifies identity before saving.
final class BrowserEmployeePhotoPicker implements EmployeePhotoPicker {
  static const _maxBytes = 8 * 1024 * 1024;

  @override
  Future<Uint8List?> choose() {
    if (!web.window.isSecureContext || web.document.body == null) {
      throw const EmployeeFailure(
        'PHOTO_PICKER_FAILED',
        'Open the secure Jentra Employee website to choose a photo.',
      );
    }
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = 'image/jpeg,image/png'
      ..multiple = false;
    input.style.display = 'none';
    input.setAttribute('aria-hidden', 'true');
    final result = Completer<Uint8List?>();
    Timer? timeout;
    late final JSFunction changed, cancelled;
    void finish(Uint8List? bytes, [Object? failure]) {
      if (result.isCompleted) return;
      timeout?.cancel();
      input.removeEventListener('change', changed);
      input.removeEventListener('cancel', cancelled);
      input.remove();
      if (failure == null) {
        result.complete(bytes);
      } else {
        result.completeError(failure);
      }
    }

    Future<void> readSelection() async {
      if (result.isCompleted) return;
      try {
        final files = input.files;
        if (files == null || files.length == 0) {
          finish(null);
          return;
        }
        final file = files.length == 1 ? files.item(0) : null;
        if (file == null ||
            !{'image/jpeg', 'image/png'}.contains(file.type.toLowerCase())) {
          throw const EmployeeFailure(
            'PHOTO_INVALID',
            'Choose one JPG or PNG photo.',
          );
        }
        if (file.size <= 0 || file.size > _maxBytes) {
          throw const EmployeeFailure(
            'PHOTO_TOO_LARGE',
            'Choose a photo smaller than 8 MB.',
          );
        }
        final buffer = await file.arrayBuffer().toDart;
        if (result.isCompleted) return;
        final bytes = buffer.toDart.asUint8List();
        if (bytes.length != file.size || bytes.length > _maxBytes) {
          throw const EmployeeFailure(
            'PHOTO_INVALID',
            'The selected photo could not be read safely.',
          );
        }
        finish(bytes);
      } on Object catch (error) {
        finish(
          null,
          error is EmployeeFailure
              ? error
              : const EmployeeFailure(
                  'PHOTO_PICKER_FAILED',
                  'The photo could not be opened. Choose a JPG or PNG again.',
                ),
        );
      }
    }

    changed = ((web.Event _) => unawaited(readSelection())).toJS;
    cancelled = ((web.Event _) => finish(null)).toJS;
    input.addEventListener('change', changed);
    input.addEventListener('cancel', cancelled);
    // Older browsers may omit cancel. Bound both the input lifetime and any
    // late file read to the controller's existing selection-intent lifetime.
    timeout = Timer(const Duration(minutes: 2), () => finish(null));
    web.document.body!.appendChild(input);
    try {
      input.click();
    } on Object {
      finish(
        null,
        const EmployeeFailure(
          'PHOTO_PICKER_FAILED',
          'The browser could not open its photo selector. Try again.',
        ),
      );
    }
    return result.future;
  }
}
