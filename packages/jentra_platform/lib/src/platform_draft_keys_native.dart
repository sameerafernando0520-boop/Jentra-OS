import 'draft_cipher.dart';

SecretKeyStore createPlatformDraftKeyStore() => WindowsCredentialKeyStore();
