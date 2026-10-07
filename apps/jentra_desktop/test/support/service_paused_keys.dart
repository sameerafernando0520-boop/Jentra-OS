import 'dart:async';

import 'package:jentra_platform/jentra_platform.dart';

class PausedKeys implements SecretKeyStore {
  final values = <String, String>{};
  bool armed = false;
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<String?> read(String key) async {
    if (armed && !entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
