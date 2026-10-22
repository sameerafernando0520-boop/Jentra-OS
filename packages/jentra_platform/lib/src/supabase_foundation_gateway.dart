import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'auth/google_sign_in.dart';
import 'auth/email_confirmation.dart';
import 'auth/email_confirmation_stub.dart'
    if (dart.library.io) 'auth/email_confirmation_io.dart'
    as email_confirmation;
import 'auth/google_oauth_stub.dart'
    if (dart.library.io) 'auth/google_oauth_io.dart'
    as google;

enum MfaAssurance { unauthenticated, aal1, aal2 }

enum TenantBootstrapFailure {
  invalidValues,
  duplicate,
  accessDenied,
  unconfirmed,
}

final class TenantBootstrapException implements Exception {
  const TenantBootstrapException(this.failure);
  final TenantBootstrapFailure failure;

  @override
  String toString() => 'TenantBootstrapException(${failure.name})';
}

final class TotpEnrollment {
  const TotpEnrollment({
    required this.factorId,
    required this.secret,
    required this.uri,
  });

  final String factorId;
  final String secret;
  final String uri;
}

final class TenantSummary {
  const TenantSummary({
    required this.id,
    required this.name,
    required this.slug,
    required this.status,
    required this.membershipStatus,
  });

  final String id;
  final String name;
  final String slug;
  final String status;
  final String membershipStatus;

  factory TenantSummary.fromJson(Map<String, Object?> json) => TenantSummary(
    id: json['tenant_id']! as String,
    name: json['tenant_name']! as String,
    slug: json['tenant_slug']! as String,
    status: json['tenant_status']! as String,
    membershipStatus: json['membership_status']! as String,
  );
}

final class LegalEntitySummary {
  const LegalEntitySummary({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.code,
    required this.currencyCode,
    required this.timezone,
    required this.status,
  });

  final String id;
  final String tenantId;
  final String name;
  final String code;
  final String currencyCode;
  final String timezone;
  final String status;

  factory LegalEntitySummary.fromJson(Map<String, Object?> json) =>
      LegalEntitySummary(
        id: json['id']! as String,
        tenantId: json['tenant_id']! as String,
        name: json['name']! as String,
        code: json['code']! as String,
        currencyCode: json['currency_code']! as String,
        timezone: json['timezone']! as String,
        status: json['status']! as String,
      );
}

final class BranchSummary {
  const BranchSummary({
    required this.id,
    required this.tenantId,
    required this.legalEntityId,
    required this.name,
    required this.code,
    required this.timezone,
    required this.status,
  });

  final String id;
  final String tenantId;
  final String legalEntityId;
  final String name;
  final String code;
  final String timezone;
  final String status;

  factory BranchSummary.fromJson(Map<String, Object?> json) => BranchSummary(
    id: json['id']! as String,
    tenantId: json['tenant_id']! as String,
    legalEntityId: json['legal_entity_id']! as String,
    name: json['name']! as String,
    code: json['code']! as String,
    timezone: json['timezone']! as String,
    status: json['status']! as String,
  );
}

/// The only desktop boundary for foundation authentication and tenant RPCs.
final class SupabaseFoundationGateway {
  SupabaseFoundationGateway(this._client);

  final SupabaseClient _client;

  Stream<AuthState> get authChanges => _client.auth.onAuthStateChange;
  User? get currentUser => _client.auth.currentUser;

  Future<UserResponse> updateAccountDisplayName(String name) async {
    if (_client.auth.currentUser == null) {
      throw StateError('ACCOUNT_SIGN_IN_REQUIRED');
    }
    final value = name.trim();
    if (value.isEmpty ||
        value.runes.length > 100 ||
        RegExp(r'[\u0000-\u001F\u007F-\u009F\u2028\u2029]').hasMatch(name)) {
      throw const FormatException('ACCOUNT_NAME_INVALID');
    }
    return _client.auth.updateUser(UserAttributes(data: {'full_name': value}));
  }

  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) => _client.auth.signInWithPassword(email: email, password: password);

  Future<AuthResponse> createAccount({
    required String email,
    required String password,
  }) => _client.auth.signUp(email: email, password: password);

  Future<AuthResponse> createAccountAndConfirm({
    required String email,
    required String password,
    EmailConfirmationCancellation? cancellation,
    void Function()? onEmailSent,
    void Function()? onExchangeStarted,
  }) => email_confirmation.createAccountAndConfirm(
    _client,
    email: email,
    password: password,
    cancellation: cancellation,
    onEmailSent: onEmailSent,
    onExchangeStarted: onExchangeStarted,
  );

  Future<AuthResponse> resendAndConfirmEmail({
    required String email,
    EmailConfirmationCancellation? cancellation,
    void Function()? onEmailSent,
    void Function()? onExchangeStarted,
  }) => email_confirmation.resendAndConfirmEmail(
    _client,
    email: email,
    cancellation: cancellation,
    onEmailSent: onEmailSent,
    onExchangeStarted: onExchangeStarted,
  );

  Future<AuthResponse> confirmEmailFromLink({required String link}) =>
      confirmSignupEmailFromLink(_client, link: link);

  Future<bool> signInWithGoogle({
    String? redirectTo,
    GoogleSignInCancellation? cancellation,
    void Function()? onExchangeStarted,
  }) => google.signInWithGoogle(
    _client,
    redirectTo: redirectTo,
    cancellation: cancellation,
    onExchangeStarted: onExchangeStarted,
  );

  Future<void> signOut() => _client.auth.signOut();

  MfaAssurance currentAssurance() {
    final token = _client.auth.currentSession?.accessToken;
    if (token == null) return MfaAssurance.unauthenticated;
    try {
      final parts = token.split('.');
      final payload =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
              )
              as Map<String, Object?>;
      return payload['aal'] == 'aal2' ? MfaAssurance.aal2 : MfaAssurance.aal1;
    } on Object {
      return MfaAssurance.aal1;
    }
  }

  Future<List<String>> listVerifiedTotpFactorIds() async {
    final factors = await _client.auth.mfa.listFactors();
    return factors.totp.map((factor) => factor.id).toList(growable: false);
  }

  Future<TotpEnrollment> enrollTotp() async {
    final response = await _client.auth.mfa.enroll(
      factorType: FactorType.totp,
      issuer: 'Jentra OS',
      friendlyName: 'Jentra desktop',
    );
    final totp = response.totp;
    if (totp == null) throw StateError('TOTP enrollment details are missing.');
    return TotpEnrollment(
      factorId: response.id,
      secret: totp.secret,
      uri: totp.uri,
    );
  }

  Future<void> verifyTotp({
    required String factorId,
    required String code,
  }) async {
    await _client.auth.mfa.challengeAndVerify(factorId: factorId, code: code);
  }

  Future<List<TenantSummary>> listMyTenants() async {
    final rows = await _client.schema('api').rpc('list_my_tenants') as List;
    return rows
        .cast<Map<String, Object?>>()
        .map(TenantSummary.fromJson)
        .toList(growable: false);
  }

  Future<List<LegalEntitySummary>> listLegalEntities(String tenantId) async {
    final rows =
        await _client
                .schema('api')
                .from('legal_entities')
                .select()
                .eq('tenant_id', tenantId)
                .eq('status', 'active')
                .order('name')
            as List;
    return rows
        .map(
          (row) =>
              LegalEntitySummary.fromJson((row as Map).cast<String, Object?>()),
        )
        .toList(growable: false);
  }

  Future<List<BranchSummary>> listBranches({
    required String tenantId,
    required String legalEntityId,
  }) async {
    final rows =
        await _client
                .schema('api')
                .from('branches')
                .select()
                .eq('tenant_id', tenantId)
                .eq('legal_entity_id', legalEntityId)
                .eq('status', 'active')
                .order('name')
            as List;
    return rows
        .map(
          (row) => BranchSummary.fromJson((row as Map).cast<String, Object?>()),
        )
        .toList(growable: false);
  }

  Future<Map<String, Object?>> bootstrapTenant({
    required String name,
    required String slug,
    required String legalEntityName,
    required String legalEntityCode,
    required String branchName,
    required String branchCode,
    String timezone = 'Asia/Colombo',
    String currencyCode = 'LKR',
    String? idempotencyKey,
  }) async {
    try {
      final result = await _client
          .schema('api')
          .rpc(
            'bootstrap_tenant',
            params: <String, Object?>{
              'p_name': name,
              'p_slug': slug,
              'p_legal_entity_name': legalEntityName,
              'p_legal_entity_code': legalEntityCode,
              'p_branch_name': branchName,
              'p_branch_code': branchCode,
              'p_timezone': timezone,
              'p_currency_code': currencyCode,
              'p_idempotency_key': idempotencyKey ?? const Uuid().v4(),
            },
          );
      return (result as Map).cast<String, Object?>();
    } on PostgrestException catch (error) {
      throw TenantBootstrapException(switch (error.code) {
        '22023' || '23514' => TenantBootstrapFailure.invalidValues,
        '23505' => TenantBootstrapFailure.duplicate,
        '42501' => TenantBootstrapFailure.accessDenied,
        _ => TenantBootstrapFailure.unconfirmed,
      });
    } on Object {
      throw const TenantBootstrapException(TenantBootstrapFailure.unconfirmed);
    }
  }

  Future<Set<String>> getCapabilities(String tenantId) async {
    final rows =
        await _client
                .schema('api')
                .rpc('get_my_capabilities', params: {'p_tenant_id': tenantId})
            as List;
    return rows
        .cast<Map<String, Object?>>()
        .map((row) => row['permission_code']! as String)
        .toSet();
  }

  Future<Map<String, Object?>> createInvitation({
    required String tenantId,
    required String email,
    required String roleId,
    String? legalEntityId,
    String? branchId,
    int expiresInHours = 72,
  }) async {
    final result = await _client
        .schema('api')
        .rpc(
          'create_invitation',
          params: <String, Object?>{
            'p_tenant_id': tenantId,
            'p_email': email,
            'p_role_id': roleId,
            'p_legal_entity_id': legalEntityId,
            'p_branch_id': branchId,
            'p_expires_in_hours': expiresInHours,
          },
        );
    return (result as Map).cast<String, Object?>();
  }

  Future<Map<String, Object?>> acceptInvitation(String token) async {
    final result = await _client
        .schema('api')
        .rpc('accept_invitation', params: <String, Object?>{'p_token': token});
    return (result as Map).cast<String, Object?>();
  }
}
