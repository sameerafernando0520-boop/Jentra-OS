import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_sales/src/data/device_location.dart';

final class _Source implements SalesPositionSource {
  _Source({
    this.enabled = true,
    this.permission = LocationPermission.whileInUse,
    this.afterRequest = LocationPermission.whileInUse,
    this.reading,
  });
  bool enabled;
  LocationPermission permission, afterRequest;
  Future<Position> Function()? reading;
  int requests = 0, readings = 0;
  LocationSettings? settings;

  @override
  Future<bool> serviceEnabled() async => enabled;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return afterRequest;
  }

  @override
  Future<Position> currentPosition(LocationSettings settings) {
    readings++;
    this.settings = settings;
    return reading?.call() ?? Future.value(_position(6.9270786, 79.8612430));
  }
}

Position _position(double latitude, double longitude) => Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: DateTime.utc(2026, 11, 18),
  accuracy: 8,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

Matcher _failure(String code) =>
    throwsA(isA<FieldSalesFailure>().having((e) => e.code, 'code', code));

void main() {
  test('one high-accuracy reading becomes a six-place location', () async {
    final source = _Source();
    final location = await deviceLocation(source: source)();
    expect(location!.payload, {
      'latitude': '6.927079',
      'longitude': '79.861243',
    });
    expect(source.readings, 1);
    expect(source.requests, 0);
    expect(source.settings!.accuracy, LocationAccuracy.high);
    expect(source.settings!.timeLimit, const Duration(seconds: 20));
  });

  test('permission is asked for only when it has not been decided', () async {
    final source = _Source(permission: LocationPermission.denied);
    expect(await deviceLocation(source: source)(), isNotNull);
    expect(source.requests, 1);
  });

  test('a refused permission records nothing and says why', () async {
    final refused = _Source(
      permission: LocationPermission.denied,
      afterRequest: LocationPermission.denied,
    );
    await expectLater(
      deviceLocation(source: refused)(),
      _failure('LOCATION_PERMISSION_DENIED'),
    );
    expect(refused.readings, 0);
    final forever = _Source(permission: LocationPermission.deniedForever);
    await expectLater(
      deviceLocation(source: forever)(),
      _failure('LOCATION_PERMISSION_DENIED'),
    );
    expect(forever.requests, 0);
    expect(forever.readings, 0);
  });

  test(
    'location switched off is refused before any permission prompt',
    () async {
      final source = _Source(
        enabled: false,
        permission: LocationPermission.denied,
      );
      await expectLater(
        deviceLocation(source: source)(),
        _failure('LOCATION_SERVICE_OFF'),
      );
      expect(source.requests, 0);
      expect(source.readings, 0);
    },
  );

  test('a reading that never arrives or fails gives no location', () async {
    final slow = _Source(reading: () => Completer<Position>().future);
    expect(
      await deviceLocation(
        source: slow,
        timeout: const Duration(milliseconds: 10),
      )(),
      isNull,
    );
    final broken = _Source(reading: () async => throw StateError('gps'));
    expect(await deviceLocation(source: broken)(), isNull);
  });

  test('an out-of-range reading is refused rather than stored', () async {
    final source = _Source(reading: () async => _position(95, 0));
    await expectLater(
      deviceLocation(source: source)(),
      _failure('LOCATION_INVALID'),
    );
  });
}
