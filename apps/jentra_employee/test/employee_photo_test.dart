import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jentra_employee/src/data/employee_gateway.dart';
import 'package:jentra_employee/src/data/employee_photo.dart';
import 'package:jentra_employee/src/data/employee_storage.dart';
import 'package:jentra_employee/src/employee_controller.dart';

import 'support/employee_fixture.dart';

Uint8List fixturePhoto({int tint = 210}) {
  final image = img.Image(width: 320, height: 240);
  img.fill(image, color: img.ColorRgb8(0, 98, tint));
  img.fillRect(
    image,
    x1: 80,
    y1: 40,
    x2: 240,
    y2: 200,
    color: img.ColorRgb8(100, 220, 200),
  );
  return img.encodePng(image);
}

class ControlledPhotoPicker implements EmployeePhotoPicker {
  var result = Completer<Uint8List?>();
  int calls = 0;
  @override
  Future<Uint8List?> choose() {
    calls++;
    return result.future;
  }
}

class PhotoGateway extends FixtureGateway {
  bool deny = false;
  String employee = fixtureEmployee;
  @override
  Future<EmployeeIdentity> resolveIdentity(EmployeeWorkspace workspace) async {
    if (deny) {
      throw const EmployeeFailure('PERMISSION_DENIED', 'Access revoked.');
    }
    return EmployeeIdentity(
      workspace: workspace,
      actorId: actorId!,
      employeeId: employee,
      displayName: 'Preview employee',
    );
  }
}

class SilentPhotoStore extends FixtureStore {
  @override
  Future<void> write(String key, String value) async {
    if (key.startsWith('jentra.employee.v1.photo.')) return;
    await super.write(key, value);
  }
}

class PausingPhotoStore extends FixtureStore {
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> write(String key, String value) async {
    if (key.startsWith('jentra.employee.v1.photo.')) {
      started.complete();
      await release.future;
    }
    await super.write(key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final explicitLock in [false, true]) {
    test(
      'return during an in-flight photo write ${explicitLock ? 'waits for manual-lock cleanup' : 'restores the authorized save'}',
      () async {
        final kv = PausingPhotoStore();
        final gateway = PhotoGateway();
        final picker = ControlledPhotoPicker();
        final controller = EmployeeController(
          gateway: gateway,
          draftStore: EmployeeDraftStore(kv),
          photoPicker: picker,
          photoNormalizer: (bytes) async => normalizeEmployeePhoto(bytes),
        );
        addTearDown(controller.dispose);
        addTearDown(gateway.close);
        await controller.start();
        final owner = controller.identity!;
        final selection = controller.chooseProfilePhoto();
        picker.result.complete(fixturePhoto());
        await kv.started.future;
        controller.background();
        if (explicitLock) controller.lock();
        final returning = controller.resume();
        await Future<void>.delayed(Duration.zero);
        expect(controller.profilePhoto, isNull);
        kv.release.complete();
        await returning;
        await selection;
        final saved = await EmployeePhotoStore(kv).load(owner);
        expect(saved == null, explicitLock);
        expect(controller.profilePhoto, saved);
      },
    );
  }
  test(
    'sign-out cleans up a photo whose secure write was already in flight',
    () async {
      final kv = PausingPhotoStore();
      final gateway = PhotoGateway();
      final picker = ControlledPhotoPicker();
      final controller = EmployeeController(
        gateway: gateway,
        draftStore: EmployeeDraftStore(kv),
        photoPicker: picker,
        photoNormalizer: (bytes) async => normalizeEmployeePhoto(bytes),
      );
      addTearDown(controller.dispose);
      addTearDown(gateway.close);
      await controller.start();
      final owner = controller.identity!;
      final selection = controller.chooseProfilePhoto();
      picker.result.complete(fixturePhoto());
      await kv.started.future;
      final logout = controller.signOut();
      kv.release.complete();
      await logout;
      await selection;
      expect(controller.profilePhoto, isNull);
      expect(await EmployeePhotoStore(kv).load(owner), isNull);
      expect(controller.notice, isNot('Profile photo saved on this device.'));
    },
  );
  test('normalization makes a metadata-free 256 pixel JPEG and rejects malformed or oversized input', () {
    final photo = normalizeEmployeePhoto(fixturePhoto());
    final decoded = img.decodeJpg(photo)!;
    expect((decoded.width, decoded.height), (256, 256));
    expect(decoded.exif.isEmpty, isTrue);
    expect(photo.length, lessThanOrEqualTo(EmployeePhotoStore.maxPhotoBytes));
    expect(
      () => normalizeEmployeePhoto(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<EmployeeFailure>()),
    );
    expect(
      () => normalizeEmployeePhoto(Uint8List(8 * 1024 * 1024 + 1)),
      throwsA(isA<EmployeeFailure>()),
    );
  });

  test('normalization removes an actual source EXIF description', () {
    final source = img.Image(width: 200, height: 300);
    img.fill(source, color: img.ColorRgb8(100, 180, 210));
    source.exif.imageIfd[0x010e] = 'private source description';
    final jpeg = img.encodeJpg(source);
    expect(img.decodeJpg(jpeg)!.exif.isEmpty, isFalse);
    expect(img.decodeJpg(normalizeEmployeePhoto(jpeg))!.exif.isEmpty, isTrue);
  });

  test(
    'unsupported still image formats cannot bypass the photo format limit',
    () {
      final source = img.Image(width: 12, height: 12);
      for (final bytes in [img.encodeGif(source), img.encodeBmp(source)]) {
        expect(
          () => normalizeEmployeePhoto(bytes),
          throwsA(
            isA<EmployeeFailure>().having(
              (failure) => failure.code,
              'code',
              'PHOTO_INVALID',
            ),
          ),
        );
      }
    },
  );

  test('an unverified photo write reports storage failure without claiming success', () async {
    final kv = SilentPhotoStore();
    final gateway = PhotoGateway();
    final picker = ControlledPhotoPicker();
    final controller = EmployeeController(
      gateway: gateway,
      draftStore: EmployeeDraftStore(kv),
      photoPicker: picker,
      photoNormalizer: (bytes) async => normalizeEmployeePhoto(bytes),
    );
    addTearDown(controller.dispose);
    addTearDown(gateway.close);
    await controller.start();
    final selection = controller.chooseProfilePhoto();
    picker.result.complete(fixturePhoto());
    await selection;
    expect(controller.profilePhoto, isNull);
    expect(controller.notice, isNull);
    expect(controller.photoError?.code, 'STORAGE_UNAVAILABLE');
  });

  test('invalid selection while backgrounded reports its error only after the exact employee is reverified', () async {
    final gateway = PhotoGateway();
    final picker = ControlledPhotoPicker();
    final controller = EmployeeController(
      gateway: gateway,
      draftStore: EmployeeDraftStore(FixtureStore()),
      photoPicker: picker,
      photoNormalizer: (bytes) async => normalizeEmployeePhoto(bytes),
    );
    addTearDown(controller.dispose);
    addTearDown(gateway.close);
    await controller.start();
    final selection = controller.chooseProfilePhoto();
    controller.background();
    picker.result.complete(Uint8List.fromList([1, 2, 3]));
    await Future<void>.delayed(Duration.zero);
    expect(controller.photoError, isNull);
    await controller.resume();
    await selection;
    expect(controller.photoError?.code, 'PHOTO_INVALID');
    expect(controller.profilePhoto, isNull);
  });

  test('native selector cancellation and platform errors are handled without fabricated bytes', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(NativeEmployeePhotoPicker.channel, (
      call,
    ) async {
      expect(call.method, 'choosePhoto');
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        NativeEmployeePhotoPicker.channel,
        null,
      ),
    );
    expect(await NativeEmployeePhotoPicker().choose(), isNull);
    messenger.setMockMethodCallHandler(
      NativeEmployeePhotoPicker.channel,
      (_) async => throw PlatformException(code: 'PHOTO_TOO_LARGE'),
    );
    await expectLater(
      NativeEmployeePhotoPicker().choose(),
      throwsA(
        isA<EmployeeFailure>().having((e) => e.code, 'code', 'PHOTO_TOO_LARGE'),
      ),
    );
  });

  test('protected store scopes photos to exact employee and removes only the current actor photos', () async {
    final kv = FixtureStore();
    final store = EmployeePhotoStore(kv);
    final owner = EmployeeIdentity(
      workspace: fixtureWorkspace,
      actorId: fixtureActor,
      employeeId: fixtureEmployee,
      displayName: 'One',
    );
    final other = EmployeeIdentity(
      workspace: fixtureWorkspace,
      actorId: '20000000-0000-4000-8000-000000000004',
      employeeId: fixtureEmployee,
      displayName: 'Two',
    );
    final photo = normalizeEmployeePhoto(fixturePhoto());
    await store.save(owner, photo);
    expect(await store.load(other), isNull);
    await store.save(other, photo);
    await store.clearActor(fixtureActor);
    expect(await store.load(owner), isNull);
    expect(await store.load(other), photo);
  });

  test('corrupt owner records are discarded and hostile cleanup indexes cannot delete another actor', () async {
    final kv = FixtureStore();
    final store = EmployeePhotoStore(kv);
    final owner = EmployeeIdentity(
      workspace: fixtureWorkspace,
      actorId: fixtureActor,
      employeeId: fixtureEmployee,
      displayName: 'One',
    );
    final key = 'jentra.employee.v1.photo.${owner.key}';
    kv.values[key] = jsonEncode({
      'schema': 1,
      'owner': 'someone else',
      'jpeg': 'invalid',
    });
    expect(await store.load(owner), isNull);
    expect(kv.values.containsKey(key), isFalse);
    kv.values['jentra.employee.v1.photo-index.$fixtureActor'] = jsonEncode([
      'jentra.employee.v1.photo.other-owner',
    ]);
    kv.values['jentra.employee.v1.photo.other-owner'] = 'keep';
    await expectLater(
      store.clearActor(fixtureActor),
      throwsA(isA<EmployeeFailure>()),
    );
    expect(kv.values['jentra.employee.v1.photo.other-owner'], 'keep');
  });

  for (final action in [
    'resume',
    'sign-out',
    'manual-lock',
    'access-denied',
    'employee-changed',
  ]) {
    test(
      'gallery return after $action preserves exact identity and background privacy',
      () async {
        final kv = FixtureStore();
        final gateway = PhotoGateway();
        final picker = ControlledPhotoPicker();
        final controller = EmployeeController(
          gateway: gateway,
          draftStore: EmployeeDraftStore(kv),
          photoPicker: picker,
          photoNormalizer: (bytes) async => normalizeEmployeePhoto(bytes),
        );
        addTearDown(controller.dispose);
        addTearDown(gateway.close);
        await controller.start();
        final owner = controller.identity!;
        final selection = controller.chooseProfilePhoto();
        expect(picker.calls, 1);
        controller.background();
        expect(controller.profilePhoto, isNull);
        expect(controller.identity, isNull);
        if (action == 'sign-out') await controller.signOut();
        if (action == 'manual-lock') controller.lock();
        if (action == 'access-denied') gateway.deny = true;
        if (action == 'employee-changed') {
          gateway.employee = '30000000-0000-4000-8000-000000000005';
        }
        picker.result.complete(fixturePhoto());
        await Future<void>.delayed(Duration.zero);
        expect(controller.profilePhoto, isNull);
        await controller.resume();
        await selection;
        final saved = await EmployeePhotoStore(kv).load(owner);
        if (action == 'resume') {
          expect(saved, isNotNull);
          expect(controller.profilePhoto, saved);
          expect(controller.photoBusy, isFalse);
          controller.lock();
          expect(controller.profilePhoto, isNull);
          await controller.resume();
          expect(controller.profilePhoto, saved);
          await controller.removeProfilePhoto();
          expect(controller.profilePhoto, isNull);
          expect(await EmployeePhotoStore(kv).load(owner), isNull);
        } else {
          expect(saved, isNull);
          expect(controller.profilePhoto, isNull);
        }
      },
    );
  }

  test('selection cancellation keeps the previous protected photo', () async {
    final kv = FixtureStore();
    final gateway = PhotoGateway();
    final picker = ControlledPhotoPicker();
    final controller = EmployeeController(
      gateway: gateway,
      draftStore: EmployeeDraftStore(kv),
      photoPicker: picker,
      photoNormalizer: (bytes) async => normalizeEmployeePhoto(bytes),
    );
    addTearDown(controller.dispose);
    addTearDown(gateway.close);
    await controller.start();
    final photo = normalizeEmployeePhoto(fixturePhoto());
    await EmployeePhotoStore(kv).save(controller.identity!, photo);
    await controller.refresh();
    final selection = controller.chooseProfilePhoto();
    picker.result.complete(null);
    await selection;
    expect(controller.profilePhoto, photo);
    expect(controller.photoError, isNull);
  });
}
