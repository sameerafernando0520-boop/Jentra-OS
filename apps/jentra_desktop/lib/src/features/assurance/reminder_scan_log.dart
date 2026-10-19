import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// When this device last sent audit reminders for a scope, so opening the
/// workspace reminds at most once a day. The server is idempotent anyway; this
/// only avoids needless calls.
abstract interface class ReminderScanLog {
  Future<String?> lastScan(String scopeKey);
  Future<void> record(String scopeKey, String date);
}

final class SharedPreferencesReminderScanLog implements ReminderScanLog {
  SharedPreferencesReminderScanLog([SharedPreferencesAsync? store])
    : _store = store ?? SharedPreferencesAsync();
  final SharedPreferencesAsync _store;

  static String _key(String scope) => 'jentra.assurance.reminders.$scope';

  @override
  Future<String?> lastScan(String scopeKey) async {
    try {
      return await _store.getString(_key(scopeKey));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> record(String scopeKey, String date) async {
    try {
      await _store.setString(_key(scopeKey), date);
    } catch (_) {
      // A lost record only means one more idempotent scan tomorrow.
    }
  }
}

final class MemoryReminderScanLog implements ReminderScanLog {
  final _dates = <String, String>{};

  @override
  Future<String?> lastScan(String scopeKey) async => _dates[scopeKey];

  @override
  Future<void> record(String scopeKey, String date) async =>
      _dates[scopeKey] = date;
}

final reminderScanLogProvider = Provider<ReminderScanLog>(
  (ref) => SharedPreferencesReminderScanLog(),
);
