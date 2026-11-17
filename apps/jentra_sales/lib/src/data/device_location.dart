import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:jentra_domain/jentra_field_sales.dart';

/// The device position service, behind a seam so tests need no plugin.
abstract interface class SalesPositionSource {
  Future<bool> serviceEnabled();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<Position> currentPosition(LocationSettings settings);
}

final class GeolocatorPositionSource implements SalesPositionSource {
  const GeolocatorPositionSource();
  @override
  Future<bool> serviceEnabled() => Geolocator.isLocationServiceEnabled();
  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();
  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();
  @override
  Future<Position> currentPosition(LocationSettings settings) =>
      Geolocator.getCurrentPosition(locationSettings: settings);
}

/// Reads the device position once, for the visit action the rep is taking.
/// It never listens to a position stream and never asks for background
/// access. Permission is asked for only here, when the rep has chosen to add
/// a location. Returns null when no reading arrives in time.
Future<FieldSalesLocation?> Function() deviceLocation({
  SalesPositionSource source = const GeolocatorPositionSource(),
  Duration timeout = const Duration(seconds: 20),
}) => () async {
  if (!await source.serviceEnabled()) {
    throw const FieldSalesFailure(
      'LOCATION_SERVICE_OFF',
      'Location is switched off on this device. Nothing was recorded; switch it on or continue without location.',
    );
  }
  var permission = await source.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await source.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever ||
      permission == LocationPermission.unableToDetermine) {
    throw const FieldSalesFailure(
      'LOCATION_PERMISSION_DENIED',
      'Jentra Sales may not read your location. Nothing was recorded; allow it in settings or continue without location.',
    );
  }
  try {
    final position = await source
        .currentPosition(
          LocationSettings(accuracy: LocationAccuracy.high, timeLimit: timeout),
        )
        .timeout(timeout + const Duration(seconds: 2));
    return FieldSalesLocation.fromDegrees(
      position.latitude,
      position.longitude,
    );
  } on FieldSalesFailure {
    rethrow;
  } on Object {
    // A timeout or a platform error: no reading, so nothing is recorded.
    return null;
  }
};
