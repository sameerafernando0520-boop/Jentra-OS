import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/supabase_auth_repository.dart';
import 'auth_models.dart';

/// Restored session plus subsequent sign-in, refresh, and sign-out events.
final authSessionProvider = StreamProvider<AuthSession?>((ref) {
  return ref.watch(authRepositoryProvider).sessionChanges();
});
