import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:jentra_domain/jentra_domain.dart';

/// Network reachability signal. Commands still require a server response.
final class ConnectivityService {
  ConnectivityService({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Stream<ConnectivityState> watch() =>
      _connectivity.onConnectivityChanged.map(_map).distinct();

  Future<ConnectivityState> current() async =>
      _map(await _connectivity.checkConnectivity());

  static ConnectivityState _map(List<ConnectivityResult> results) =>
      results.isEmpty ||
          results.every((result) => result == ConnectivityResult.none)
      ? ConnectivityState.offline
      : ConnectivityState.online;
}
