import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'auth/google_sign_in.dart';
import 'auth/email_confirmation.dart';
import 'auth/email_confirmation_stub.dart'
    if (dart.library.io) 'auth/email_confirmation_io.dart'
    if (dart.library.js_interop) 'auth/email_confirmation_web.dart'
    as email_confirmation;
import 'auth/google_oauth_stub.dart'
    if (dart.library.io) 'auth/google_oauth_io.dart'
    as google;

enum MfaAssurance { unauthenticated, aal1, aal2 }

const _managedAdminDomain = '@admin.jentra.invalid';
final _organizationUsername = RegExp(r'^[a-z0-9][a-z0-9._-]{2,47}$');
final _accountEmail = RegExp(r'^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$');
final _passwordUppercase = RegExp(r'[A-Z]');
final _passwordLowercase = RegExp(r'[a-z]');
final _passwordDigit = RegExp(r'[0-9]');
final _passwordControl = RegExp(r'[\x00-\x1f\x7f]');

String organizationUsername(String input) =>
    input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');

bool isAccountLogin(String input) {
  final value = input.contains('@')
      ? input.trim().toLowerCase()
      : organizationUsername(input);
  return (value.length <= 254 && _accountEmail.hasMatch(value)) ||
      (_organizationUsername.hasMatch(value) &&
          !value.endsWith('.') &&
          !value.contains('..'));
}

bool isOrganizationPassword(String password) =>
    password.runes.length >= 12 &&
    utf8.encode(password).length <= 72 &&
    !_passwordControl.hasMatch(password) &&
    _passwordUppercase.hasMatch(password) &&
    _passwordLowercase.hasMatch(password) &&
    _passwordDigit.hasMatch(password);

final class AccountSecurityProfile {
  AccountSecurityProfile.fromJson(Map<String, Object?> json)
    : isAdministrator = json['is_administrator'] == true,
      username = json['username'] as String?,
      recoveryEmail = json['recovery_email'] as String?,
      pendingRecoveryEmail = json['pending_recovery_email'] as String?,
      recoveryVerified = json['recovery_verified'] == true,
      mustChangePassword = json['must_change_password'] == true,
      organizationLocked = json['organization_locked'] == true,
      accountKind = json['account_kind'] as String?,
      staffStatus = json['staff_status'] as String?;

  final bool isAdministrator;
  final String? username;
  final String? recoveryEmail;
  final String? pendingRecoveryEmail;
  final bool recoveryVerified;
  final bool mustChangePassword;
  final bool organizationLocked;
  final String? accountKind;
  final String? staffStatus;
}

final class AccountSecurityException implements Exception {
  const AccountSecurityException(this.code);

  final String code;
}

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

final class TotpFactorSummary {
  const TotpFactorSummary({
    required this.id,
    required this.verified,
    required this.recoverable,
  });

  final String id;
  final bool verified;
  final bool recoverable;
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
  bool get usesManagedUsername =>
      currentUser?.appMetadata['managed_org_admin'] == true ||
      (currentUser?.email?.toLowerCase().endsWith(_managedAdminDomain) ??
          false);

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

  Future<AuthResponse> signInWithLogin({
    required String login,
    required String password,
  }) async {
    final value = login.trim();
    if (value.contains('@')) {
      return signInWithPassword(email: value, password: password);
    }
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]{2,39}$').hasMatch(value.toLowerCase())) {
      throw const AuthException('Invalid sign-in details.');
    }
    try {
      final response = await _client.functions.invoke(
        'workspace-staff',
        body: {
          'operation': 'login',
          'username': value.toLowerCase(),
          'password': password,
        },
      );
      final data = response.data;
      if (response.status != 200 ||
          data is! Map ||
          data['refresh_token'] is! String) {
        throw const AuthException('Invalid sign-in details.');
      }
      return await _client.auth.setSession(data['refresh_token'] as String);
    } on FunctionException {
      throw const AuthException(
        'Sign-in failed. Check your details and try again.',
      );
    }
  }

  Future<AuthResponse> signInWithAccountLogin({
    required String login,
    required String password,
  }) {
    final value = login.contains('@')
        ? login.trim().toLowerCase()
        : organizationUsername(login);
    if (!isAccountLogin(value)) {
      throw const AccountSecurityException('invalid_login');
    }
    return signInWithPassword(
      email: value.contains('@') ? value : '$value$_managedAdminDomain',
      password: password,
    );
  }

  Future<AccountSecurityProfile> accountSecurityProfile() async =>
      AccountSecurityProfile.fromJson(await _accountSecurity('profile'));

  Future<void> requestPasswordReset(String login) async {
    await _accountSecurity('request_reset', {'login': login.trim()});
  }

  Future<void> resetPassword({
    required String login,
    required String code,
    required String newPassword,
  }) async {
    await _accountSecurity('reset_password', {
      'login': login.trim(),
      'code': code.trim(),
      'new_password': newPassword,
    });
  }

  Future<void> requestRecoveryEmail({
    required String email,
    required String currentPassword,
  }) async {
    await _accountSecurity('request_recovery_email', {
      'email': email.trim(),
      'current_password': currentPassword,
    });
  }

  Future<void> verifyRecoveryEmail(String code) async {
    await _accountSecurity('verify_recovery_email', {'code': code.trim()});
  }

  Future<void> changeOrganizationPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _accountSecurity('change_password', {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
  }

  Future<List<Map<String, Object?>>> departmentAccounts(String tenantId) async {
    final data = await _client
        .schema('api')
        .rpc(
          'organization_department_staff',
          params: {'p_tenant_id': tenantId},
        );
    return (data as List)
        .map((row) => Map<String, Object?>.from(row as Map))
        .toList(growable: false);
  }

  Future<void> createDepartmentAccount({
    required String tenantId,
    required String name,
    required String username,
    required String department,
    required String password,
    required String confirmation,
    required String currentPassword,
  }) async {
    await _accountSecurity('create_department_account', {
      'tenant_id': tenantId,
      'name': name,
      'username': organizationUsername(username),
      'department': department,
      'password': password,
      'confirm_password': confirmation,
      'current_password': currentPassword,
    });
  }

  Future<Map<String, Object?>> _accountSecurity(
    String action, [
    Map<String, Object?> fields = const {},
  ]) async {
    try {
      final response = await _client.functions.invoke(
        'org-identity',
        body: {'action': action, ...fields},
      );
      final data = response.data;
      if (data is! Map ||
          (action == 'profile'
              ? data['is_administrator'] is! bool ||
                    data['must_change_password'] is! bool
              : data['ok'] != true)) {
        throw const AccountSecurityException('unexpected_response');
      }
      return Map<String, Object?>.from(data);
    } on FunctionException catch (error) {
      final details = error.details;
      final code = details is Map ? details['error'] : null;
      throw AccountSecurityException(code is String ? code : 'unavailable');
    }
  }

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
    final factors = await listTotpFactors();
    return factors
        .where((factor) => factor.verified)
        .map((factor) => factor.id)
        .toList(growable: false);
  }

  Future<List<TotpFactorSummary>> listTotpFactors() async {
    final actor = currentUser?.id;
    final factors = await _client.auth.mfa.listFactors();
    if (actor == null || currentUser?.id != actor) {
      throw StateError('The signed-in account changed.');
    }
    return [
      for (final factor in factors.all)
        if (factor.factorType == FactorType.totp)
          TotpFactorSummary(
            id: factor.id,
            verified: factor.status == FactorStatus.verified,
            recoverable:
                factor.status == FactorStatus.unverified &&
                (factor.friendlyName == 'Jentra desktop' ||
                    (factor.friendlyName?.startsWith('Jentra desktop ') ??
                        false)),
          ),
    ];
  }

  Future<void> cancelTotpEnrollment(String factorId) async {
    final actor = currentUser?.id;
    final factors = await listTotpFactors();
    if (actor == null || currentUser?.id != actor) {
      throw StateError('The signed-in account changed.');
    }
    final factor = factors.where((factor) => factor.id == factorId).firstOrNull;
    if (factor == null) return;
    if (factor.verified || !factor.recoverable) {
      throw StateError(
        'Only an unfinished Jentra desktop setup can be removed.',
      );
    }
    await _client.auth.mfa.unenroll(factorId);
  }

  Future<TotpEnrollment> enrollTotp() async {
    final response = await _client.auth.mfa.enroll(
      factorType: FactorType.totp,
      issuer: 'Jentra OS',
      friendlyName: 'Jentra desktop ${const Uuid().v4()}',
    );
    final totp = response.totp;
    if (totp == null || totp.secret.isEmpty) {
      throw StateError('TOTP enrollment details are missing.');
    }
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
