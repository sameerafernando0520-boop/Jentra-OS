import 'package:jentra_domain/jentra_domain.dart';

import 'browser_protected_store.dart';
import 'draft_cipher.dart';
import 'runtime_config.dart';

ProtectedBrowserKeyValueStore? _store;

SecretKeyStore createPlatformDraftKeyStore() {
  final config = RuntimeConfig.fromEnvironment();
  return BrowserDraftKeyStore(
    _store ??= ProtectedBrowserKeyValueStore(
      projectUrl: config.isSupabaseConfigured
          ? config.supabaseOrigin
          : 'https://preview.invalid',
    ),
  );
}

final class BrowserDraftKeyStore implements SecretKeyStore {
  BrowserDraftKeyStore(this.store);
  final ProtectedBrowserKeyValueStore store;
  String _key(String key) => 'jentra.desktop.draft-key.$key';
  @override
  Future<String?> read(String key) async {
    try {
      return await store.read(_key(key));
    } on BrowserStorageFailure catch (e) {
      throw _failure(e);
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await store.write(_key(key), value);
    } on BrowserStorageFailure catch (e) {
      throw _failure(e);
    }
  }

  DomainError _failure(BrowserStorageFailure e) => DomainError(
    code: 'LOCAL_STORAGE_FULL',
    message: e.message,
    fieldDetails: const {'storage': 'unavailable'},
    retryable: true,
  );
}
