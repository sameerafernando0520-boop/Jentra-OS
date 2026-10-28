import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final class EmployeeMfaFactor {
  const EmployeeMfaFactor(
    this.id,
    this.label, {
    this.verified = true,
    this.recoverable = false,
  });
  final String id, label;
  final bool verified;
  final bool recoverable;
}

final class EmployeeMfaEnrollment {
  const EmployeeMfaEnrollment(this.factorId, this.secret);
  final String factorId, secret;
}

abstract interface class EmployeeMfaGateway {
  String? get actorId;
  Stream<String?> get actorChanges;
  bool get isVerifiedSession;
  Future<List<EmployeeMfaFactor>> factors();
  Future<EmployeeMfaEnrollment> enroll();
  Future<void> cancelEnrollment(String factorId);
  Future<void> verify(String factorId, String code);
}

final class SupabaseEmployeeMfaGateway implements EmployeeMfaGateway {
  SupabaseEmployeeMfaGateway(this.client);
  final SupabaseClient client;
  @override
  String? get actorId => client.auth.currentUser?.id;
  @override
  Stream<String?> get actorChanges => client.auth.onAuthStateChange
      .map((event) => event.session?.user.id)
      .distinct();
  @override
  bool get isVerifiedSession =>
      client.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel ==
      AuthenticatorAssuranceLevels.aal2;
  @override
  Future<List<EmployeeMfaFactor>> factors() async {
    final response = await client.auth.mfa.listFactors();
    final totp = response.all
        .where((factor) => factor.factorType == FactorType.totp)
        .toList();
    return [
      for (var index = 0; index < totp.length; index++)
        EmployeeMfaFactor(
          totp[index].id,
          'Authenticator ${index + 1}',
          verified: totp[index].status == FactorStatus.verified,
          recoverable:
              totp[index].status == FactorStatus.unverified &&
              (totp[index].friendlyName?.startsWith('Jentra Employee ') ??
                  false),
        ),
    ];
  }

  @override
  Future<EmployeeMfaEnrollment> enroll() async {
    final response = await client.auth.mfa.enroll(
      factorType: FactorType.totp,
      issuer: 'Jentra Employee',
      friendlyName: 'Jentra Employee ${DateTime.now().microsecondsSinceEpoch}',
    );
    final totp = response.totp;
    if (totp == null || totp.secret.isEmpty) {
      throw StateError('Authenticator setup is unavailable.');
    }
    return EmployeeMfaEnrollment(response.id, totp.secret);
  }

  @override
  Future<void> verify(String factorId, String code) async {
    await client.auth.mfa.challengeAndVerify(factorId: factorId, code: code);
  }

  @override
  Future<void> cancelEnrollment(String factorId) async {
    final owner = actorId;
    final response = await client.auth.mfa.listFactors();
    if (owner == null || actorId != owner) {
      throw StateError('The signed-in account changed.');
    }
    final factor = response.all
        .where((item) => item.id == factorId)
        .firstOrNull;
    if (factor == null) return;
    if (factor.factorType != FactorType.totp ||
        factor.status != FactorStatus.unverified) {
      throw StateError(
        'Only an unfinished authenticator setup can be cancelled.',
      );
    }
    await client.auth.mfa.unenroll(factorId);
  }
}

/// Private, memory-only verification intent owned by one original actor.
/// Codes are never retained as fields. Setup keys are cleared on every pause,
/// account change, expiry, successful verification and disposal.
final class EmployeeMfaController extends ChangeNotifier {
  EmployeeMfaController(this.gateway) : actor = gateway.actorId {
    _subscription = gateway.actorChanges.listen((value) {
      if (value != actor) {
        _accountChanged = true;
        suspend();
      }
    });
  }
  final EmployeeMfaGateway gateway;
  final String? actor;
  StreamSubscription<String?>? _subscription;
  Timer? _setupExpiry;
  String? _setupFactorId;
  int _generation = 0;
  bool _disposed = false, _foreground = true, _accountChanged = false;
  bool busy = false, loaded = false, verified = false;
  String? error, selectedFactorId;
  List<EmployeeMfaFactor> factors = const [];
  List<EmployeeMfaFactor> recoverableSetups = const [];
  EmployeeMfaEnrollment? enrollment;
  bool get hasPendingSetup => _setupFactorId != null;

  bool get current =>
      !_disposed &&
      _foreground &&
      !_accountChanged &&
      actor != null &&
      gateway.actorId == actor;
  bool _owns(int generation) => current && generation == _generation;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _armSetupExpiry(String factorId) {
    _setupExpiry?.cancel();
    _setupExpiry = Timer(const Duration(minutes: 5), () {
      if (_disposed ||
          _accountChanged ||
          gateway.actorId != actor ||
          _setupFactorId != factorId) {
        return;
      }
      _generation++;
      _clear();
      if (_foreground) {
        error = 'Private setup details expired. Check authenticators again.';
      }
      _emit();
    });
  }

  void _clear({bool preserveSetupReceipt = false}) {
    if (!preserveSetupReceipt) {
      _setupExpiry?.cancel();
      _setupExpiry = null;
      _setupFactorId = null;
    }
    enrollment = null;
    selectedFactorId = null;
    factors = const [];
    recoverableSetups = const [];
    busy = false;
    loaded = false;
    verified = false;
    error = null;
  }

  void suspend() {
    if (_disposed) return;
    _generation++;
    _foreground = false;
    _clear(preserveSetupReceipt: !_accountChanged);
    _emit();
  }

  Future<void> resume() async {
    if (_disposed || _accountChanged) return;
    _foreground = true;
    await load();
  }

  Future<void> load() async {
    if (!current || busy) return;
    final generation = ++_generation;
    busy = true;
    error = null;
    _emit();
    try {
      final available = await gateway.factors();
      if (!_owns(generation)) return;
      if (_setupFactorId != null &&
          (!available.any((factor) => factor.id == _setupFactorId) ||
              available.any(
                (factor) => factor.id == _setupFactorId && factor.verified,
              ))) {
        _setupExpiry?.cancel();
        _setupExpiry = null;
        _setupFactorId = null;
        enrollment = null;
      }
      factors = List.unmodifiable([
        ...available.where((factor) => factor.verified),
        if (_setupFactorId != null)
          EmployeeMfaFactor(
            _setupFactorId!,
            'Authenticator setup',
            verified: false,
          ),
      ]);
      recoverableSetups = List.unmodifiable(
        available.where(
          (factor) =>
              !factor.verified &&
              factor.recoverable &&
              factor.id != _setupFactorId,
        ),
      );
      selectedFactorId = factors.firstOrNull?.id;
      loaded = true;
    } on Object {
      if (_owns(generation)) {
        error = 'Authenticator access could not be checked. Try again.';
      }
    } finally {
      if (_owns(generation)) {
        busy = false;
        _emit();
      }
    }
  }

  void selectFactor(String? id) {
    if (!current ||
        busy ||
        enrollment != null ||
        !factors.any((factor) => factor.id == id)) {
      return;
    }
    selectedFactorId = id;
    error = null;
    _emit();
  }

  void restoreSetup(String id) {
    if (!current ||
        busy ||
        _setupFactorId != null ||
        !recoverableSetups.any((factor) => factor.id == id)) {
      return;
    }
    _generation++;
    _setupFactorId = id;
    enrollment = null;
    selectedFactorId = id;
    factors = List.unmodifiable([
      ...factors.where((factor) => factor.verified),
      EmployeeMfaFactor(id, 'Authenticator setup', verified: false),
    ]);
    recoverableSetups = const [];
    error = null;
    _armSetupExpiry(id);
    _emit();
  }

  Future<void> enroll() async {
    if (!current ||
        busy ||
        !loaded ||
        factors.isNotEmpty ||
        enrollment != null) {
      return;
    }
    final generation = ++_generation;
    busy = true;
    error = null;
    _emit();
    try {
      final result = await gateway.enroll();
      if (!_owns(generation)) {
        // This user-initiated setup never became visible. Remove only its
        // still-unverified factor when the original account remains current.
        if (!_accountChanged && actor != null && gateway.actorId == actor) {
          try {
            await gateway.cancelEnrollment(result.factorId);
          } on Object {
            /* A later explicit setup check can recover. */
          }
        }
        return;
      }
      enrollment = result;
      selectedFactorId = result.factorId;
      _setupFactorId = result.factorId;
      _armSetupExpiry(result.factorId);
    } on Object {
      if (_owns(generation)) {
        error = 'Authenticator setup could not start. Try again or ask your administrator.';
      }
    } finally {
      if (_owns(generation)) {
        busy = false;
        _emit();
      }
    }
  }

  Future<void> cancelSetup() async {
    if (!current || busy || _setupFactorId == null) return;
    final generation = ++_generation, factorId = _setupFactorId!;
    busy = true;
    error = null;
    _emit();
    try {
      await gateway.cancelEnrollment(factorId);
      if (!_owns(generation)) return;
      _clear();
      await load();
    } on Object {
      if (_owns(generation)) {
        error = 'The unfinished setup could not be cancelled. Check authenticators again before retrying.';
      }
    } finally {
      if (_owns(generation)) {
        busy = false;
        _emit();
      }
    }
  }

  Future<bool> verify(String code) async {
    if (!current || busy || selectedFactorId == null) return false;
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      error = 'Enter the six-digit code from your authenticator.';
      _emit();
      return false;
    }
    final generation = ++_generation, factorId = selectedFactorId!;
    busy = true;
    error = null;
    _emit();
    try {
      await gateway.verify(factorId, code);
      if (!_owns(generation)) return false;
      if (!gateway.isVerifiedSession) {
        error = 'A verified session could not be confirmed. Check authenticators again.';
        return false;
      }
      _clear();
      verified = true;
      return true;
    } on Object {
      if (_owns(generation)) {
        error =
            'The code could not be verified. Use a fresh code and try again.';
      }
      return false;
    } finally {
      if (_owns(generation)) {
        busy = false;
        _emit();
      }
    }
  }

  bool confirmVerifiedSession() {
    if (!current || busy || !gateway.isVerifiedSession) return false;
    _clear();
    verified = true;
    _emit();
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _clear();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
