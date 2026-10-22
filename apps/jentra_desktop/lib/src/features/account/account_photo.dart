import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image/image.dart' as img;

typedef AccountPhotoOwner = ({String project, String actor});

enum AccountPhotoFailure { invalidImage, tooLarge, storageUnavailable }

final class AccountPhotoException implements Exception {
  const AccountPhotoException(this.failure);
  final AccountPhotoFailure failure;
}

abstract interface class AccountPhotoStore {
  Future<Uint8List?> read(AccountPhotoOwner owner);
  Future<void> save(AccountPhotoOwner owner, Uint8List bytes);
  Future<void> remove(AccountPhotoOwner owner);
}

/// Uses the existing Windows protected store, partitioned by project and actor.
/// Photos are deliberately device-local, like employee companion portraits.
final class SecureAccountPhotoStore implements AccountPhotoStore {
  const SecureAccountPhotoStore({this._storage = const FlutterSecureStorage()});
  final FlutterSecureStorage _storage;
  static const maximumBytes = 64 * 1024;

  Future<String> _key(AccountPhotoOwner owner) async {
    if (owner.project.isEmpty ||
        owner.project.length > 255 ||
        !RegExp(
          r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
        ).hasMatch(owner.actor)) {
      throw const AccountPhotoException(AccountPhotoFailure.storageUnavailable);
    }
    final digest = await Sha256().hash(
      utf8.encode('${owner.project}/${owner.actor}'),
    );
    return 'jentra.desktop.account-photo.v1.${digest.bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}';
  }

  @override
  Future<Uint8List?> read(AccountPhotoOwner owner) async {
    try {
      final wire = await _storage.read(key: await _key(owner));
      if (wire == null) return null;
      if (wire.length > 90000) throw const FormatException();
      final bytes = base64Decode(wire);
      if (!_validThumbnail(bytes)) throw const FormatException();
      return bytes;
    } on Object {
      throw const AccountPhotoException(AccountPhotoFailure.storageUnavailable);
    }
  }

  @override
  Future<void> save(AccountPhotoOwner owner, Uint8List bytes) async {
    if (!_validThumbnail(bytes)) {
      throw const AccountPhotoException(AccountPhotoFailure.invalidImage);
    }
    try {
      final key = await _key(owner);
      final wire = base64Encode(bytes);
      await _storage.write(key: key, value: wire);
      if (await _storage.read(key: key) != wire) throw const FormatException();
    } on Object {
      throw const AccountPhotoException(AccountPhotoFailure.storageUnavailable);
    }
  }

  @override
  Future<void> remove(AccountPhotoOwner owner) async {
    try {
      final key = await _key(owner);
      await _storage.delete(key: key);
      if (await _storage.read(key: key) != null) throw const FormatException();
    } on Object {
      throw const AccountPhotoException(AccountPhotoFailure.storageUnavailable);
    }
  }

  static bool _validThumbnail(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maximumBytes) return false;
    final decoder = img.JpegDecoder();
    final info = decoder.startDecode(bytes);
    return info != null &&
        info.width == 256 &&
        info.height == 256 &&
        info.numFrames == 1 &&
        decoder.decodeFrame(0) != null;
  }
}

Future<Uint8List?> chooseAccountPhoto() async {
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Profile picture', extensions: ['jpg', 'jpeg', 'png']),
    ],
  );
  if (file == null) return null;
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in file.openRead()) {
    if (bytes.length + chunk.length > 8 * 1024 * 1024) {
      throw const AccountPhotoException(AccountPhotoFailure.tooLarge);
    }
    bytes.add(chunk);
  }
  return compute(normalizeAccountPhoto, bytes.takeBytes());
}

/// Bounded, metadata-free, oriented square thumbnail; never retain a file path.
Uint8List normalizeAccountPhoto(Uint8List source) {
  if (source.isEmpty || source.length > 8 * 1024 * 1024) {
    throw const AccountPhotoException(AccountPhotoFailure.tooLarge);
  }
  try {
    final img.Decoder decoder;
    if (source.length >= 2 && source[0] == 0xff && source[1] == 0xd8) {
      decoder = img.JpegDecoder();
    } else if (img.PngDecoder().isValidFile(source)) {
      decoder = img.PngDecoder();
    } else {
      throw const FormatException();
    }
    final info = decoder.startDecode(source);
    if (info == null ||
        info.width <= 0 ||
        info.height <= 0 ||
        info.width > 8192 ||
        info.height > 8192 ||
        info.width * info.height > 20000000 ||
        info.numFrames != 1) {
      throw const AccountPhotoException(AccountPhotoFailure.tooLarge);
    }
    final decoded = decoder.decodeFrame(0);
    if (decoded == null) throw const FormatException();
    final oriented = img.bakeOrientation(decoded);
    final side = oriented.width < oriented.height
        ? oriented.width
        : oriented.height;
    final resized = img.copyResize(
      img.copyCrop(
        oriented,
        x: (oriented.width - side) ~/ 2,
        y: (oriented.height - side) ~/ 2,
        width: side,
        height: side,
      ),
      width: 256,
      height: 256,
      interpolation: img.Interpolation.average,
    );
    final clean = img.Image(width: 256, height: 256, numChannels: 3);
    img.fill(clean, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(clean, resized);
    final jpeg = img.encodeJpg(clean, quality: 82);
    if (jpeg.length > SecureAccountPhotoStore.maximumBytes) {
      throw const AccountPhotoException(AccountPhotoFailure.tooLarge);
    }
    return jpeg;
  } on AccountPhotoException {
    rethrow;
  } on Object {
    throw const AccountPhotoException(AccountPhotoFailure.invalidImage);
  }
}
