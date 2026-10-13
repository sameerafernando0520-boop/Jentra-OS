import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'employee_gateway.dart';
import 'employee_storage.dart';

/// System-controlled, single-image selection. No camera or library-wide access.
abstract interface class EmployeePhotoPicker {
  Future<Uint8List?> choose();
}

final class NativeEmployeePhotoPicker implements EmployeePhotoPicker {
  static const channel = MethodChannel('com.jentra.employee/profile-photo');
  @override
  Future<Uint8List?> choose() async {
    try {
      return await channel.invokeMethod<Uint8List>('choosePhoto');
    } on PlatformException catch (e) {
      throw EmployeeFailure(
        e.code == 'PHOTO_TOO_LARGE' ? 'PHOTO_TOO_LARGE' : 'PHOTO_PICKER_FAILED',
        'Choose a JPG or PNG photo using your device photo selector.',
      );
    } on MissingPluginException {
      throw const EmployeeFailure(
        'PHOTO_PICKER_FAILED',
        'Photo selection requires Android or iPhone.',
      );
    }
  }
}

/// Re-encode a bounded square thumbnail; discard source metadata and filenames.
Future<Uint8List> prepareEmployeePhoto(Uint8List source) =>
    compute(normalizeEmployeePhoto, source);

Uint8List normalizeEmployeePhoto(Uint8List source) {
  if (source.isEmpty || source.length > 8 * 1024 * 1024) {
    throw const EmployeeFailure(
      'PHOTO_TOO_LARGE',
      'Choose a photo smaller than 8 MB.',
    );
  }
  try {
    // Select only the two supported formats. The generic decoder registry keeps
    // unrelated TIFF, WebP, GIF and other codecs reachable in the mobile binary.
    final img.Decoder decoder;
    if (source.length >= 2 && source[0] == 0xff && source[1] == 0xd8) {
      decoder = img.JpegDecoder();
    } else if (source.length >= 8 && img.PngDecoder().isValidFile(source)) {
      decoder = img.PngDecoder();
    } else {
      throw const FormatException('Only JPG and PNG are supported.');
    }
    final info = decoder.startDecode(source);
    if (info == null ||
        info.width <= 0 ||
        info.height <= 0 ||
        info.width > 8192 ||
        info.height > 8192 ||
        info.width * info.height > 20 * 1000 * 1000 ||
        info.numFrames != 1) {
      throw const EmployeeFailure(
        'PHOTO_TOO_LARGE',
        'Choose a still photo with at most 20 megapixels.',
      );
    }
    final decoded = decoder.decodeFrame(0);
    if (decoded == null) throw const FormatException('Unreadable photo.');
    final oriented = img.bakeOrientation(decoded);
    final side = oriented.width < oriented.height
        ? oriented.width
        : oriented.height;
    final square = img.copyCrop(
      oriented,
      x: (oriented.width - side) ~/ 2,
      y: (oriented.height - side) ~/ 2,
      width: side,
      height: side,
    );
    final resized = img.copyResize(
      square,
      width: 256,
      height: 256,
      interpolation: img.Interpolation.average,
    );
    // A new canvas carries pixels only, including no EXIF/GPS/ICC source data.
    final clean = img.Image(width: 256, height: 256, numChannels: 3);
    img.fill(clean, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(clean, resized);
    final jpeg = img.encodeJpg(clean, quality: 82);
    if (jpeg.length > EmployeePhotoStore.maxPhotoBytes) {
      throw const EmployeeFailure(
        'PHOTO_TOO_LARGE',
        'The photo could not be reduced safely.',
      );
    }
    return jpeg;
  } on EmployeeFailure {
    rethrow;
  } on Object {
    throw const EmployeeFailure(
      'PHOTO_INVALID',
      'Choose a valid JPG or PNG image.',
    );
  }
}

/// Photos belong to the exact accepted employee identity and this device.
/// Persist only in the existing protected native store. Never upload to HR.
final class EmployeePhotoStore {
  EmployeePhotoStore(this.store);
  final EmployeeKeyValueStore store;
  static const maxPhotoBytes = 64 * 1024;
  static const _prefix = 'jentra.employee.v1.photo.';
  static final _uuid = RegExp(
    r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
  );
  Future<void> _tail = Future.value();
  String _key(EmployeeIdentity identity) => '$_prefix${identity.key}';
  String _index(String actor) => 'jentra.employee.v1.photo-index.$actor';
  bool _owned(String key, String actor) {
    if (!key.startsWith(_prefix) || key.length > 300) return false;
    final parts = key.substring(_prefix.length).split('/');
    return parts.length == 5 &&
        parts[3] == actor &&
        parts.every(_uuid.hasMatch);
  }

  Future<T> _serial<T>(Future<T> Function() work) {
    final result = _tail.then((_) async {
      try {
        return await work();
      } on EmployeeFailure {
        rethrow;
      } on Object {
        throw const EmployeeFailure(
          'STORAGE_UNAVAILABLE',
          'Your profile photo could not be stored securely.',
        );
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<List<String>> _keys(String actor) async {
    if (!_uuid.hasMatch(actor)) throw const FormatException('Invalid owner.');
    final wire = await store.read(_index(actor));
    if (wire == null) return [];
    if (wire.length > 32000) throw const FormatException('Oversized index.');
    final value = jsonDecode(wire);
    if (value is! List ||
        value.length > 100 ||
        value.any((k) => k is! String || !_owned(k, actor))) {
      throw const FormatException('Invalid photo owner index.');
    }
    return value.cast<String>().toSet().toList();
  }

  bool _validPhoto(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxPhotoBytes) return false;
    final decoder = img.JpegDecoder();
    final info = decoder.startDecode(bytes);
    if (info == null ||
        info.width != 256 ||
        info.height != 256 ||
        info.numFrames != 1) {
      return false;
    }
    return decoder.decodeFrame(0) != null;
  }

  Future<void> save(EmployeeIdentity identity, Uint8List bytes) =>
      _serial(() async {
        final key = _key(identity);
        if (!_owned(key, identity.actorId) || !_validPhoto(bytes)) {
          throw const FormatException('Invalid thumbnail.');
        }
        final keys = await _keys(identity.actorId);
        if (!keys.contains(key)) keys.add(key);
        if (keys.length > 100) {
          throw const FormatException('Too many photo owners.');
        }
        final wire = jsonEncode({
          'schema': 1,
          'owner': identity.key,
          'jpeg': base64Encode(bytes),
        });
        // Index first, so interrupted saves are still removed at sign-out.
        final indexWire = jsonEncode(keys);
        await store.write(_index(identity.actorId), indexWire);
        if (await store.read(_index(identity.actorId)) != indexWire) {
          throw const FormatException('Photo cleanup index was not verified.');
        }
        await store.write(key, wire);
        if (await store.read(key) != wire) {
          throw const FormatException('Photo save was not verified.');
        }
      });
  Future<Uint8List?> load(EmployeeIdentity identity) => _serial(() async {
    final key = _key(identity);
    if (!_owned(key, identity.actorId)) {
      throw const FormatException('Invalid owner.');
    }
    final wire = await store.read(key);
    if (wire == null) return null;
    try {
      if (wire.length > 90000) throw const FormatException('Oversized photo.');
      final json = jsonDecode(wire);
      if (json is! Map ||
          json.length != 3 ||
          json['schema'] != 1 ||
          json['owner'] != identity.key ||
          json['jpeg'] is! String) {
        throw const FormatException('Photo owner mismatch.');
      }
      final bytes = base64Decode(json['jpeg'] as String);
      if (!_validPhoto(bytes)) {
        throw const FormatException('Invalid thumbnail.');
      }
      return bytes;
    } on Object {
      await store.delete(key);
      return null;
    }
  });
  Future<void> remove(EmployeeIdentity identity) => _serial(() async {
    final key = _key(identity);
    if (!_owned(key, identity.actorId)) {
      throw const FormatException('Invalid owner.');
    }
    await store.delete(key);
    if (await store.read(key) != null) {
      throw const FormatException('Photo removal was not verified.');
    }
    final keys = (await _keys(identity.actorId))..remove(key);
    final indexWire = jsonEncode(keys);
    await store.write(_index(identity.actorId), indexWire);
    if (await store.read(_index(identity.actorId)) != indexWire) {
      throw const FormatException('Photo cleanup index was not verified.');
    }
  });
  Future<void> clearActor(String actor) => _serial(() async {
    for (final key in await _keys(actor)) {
      await store.delete(key);
      if (await store.read(key) != null) {
        throw const FormatException('Photo cleanup was not verified.');
      }
    }
    await store.delete(_index(actor));
  });
}
