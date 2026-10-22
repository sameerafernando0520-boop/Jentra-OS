import 'dart:convert';

enum RuntimeStartupMode { connected, preview }

enum RuntimeStartupFailure {
  invalidEnvironment,
  missingConnection,
  invalidServerAddress,
  invalidPublicKey,
  projectMismatch,
  previewConnection,
  initializationFailed,
}

/// Contains only a static category, never configuration values or SDK errors.
final class RuntimeStartupException implements Exception {
  const RuntimeStartupException(this.failure);
  final RuntimeStartupFailure failure;

  @override
  String toString() => 'RuntimeStartupException(${failure.name})';
}

/// Compile-time configuration. Only the public Supabase key enters the client.
final class RuntimeConfig {
  const RuntimeConfig({
    required this.environment,
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    this.supabaseProjectRef = '',
  });

  factory RuntimeConfig.fromEnvironment() => const RuntimeConfig(
    environment: String.fromEnvironment(
      'JENTRA_ENVIRONMENT',
      defaultValue: 'development',
    ),
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabasePublishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    supabaseProjectRef: String.fromEnvironment('SUPABASE_PROJECT_REF'),
  );

  final String environment;
  final String supabaseUrl;
  final String supabasePublishableKey;
  final String supabaseProjectRef;

  /// Presence used by presentation adapters; startup also validates key format,
  /// environment, and project binding before constructing any real client.
  bool get isSupabaseConfigured =>
      _validServerAddress &&
      supabasePublishableKey.trim().isNotEmpty &&
      !supabasePublishableKey.startsWith('sb_secret_') &&
      (_legacyKeyClaims?['role'] == null ||
          _legacyKeyClaims?['role'] == 'anon');

  bool get isProduction => environment == 'production';

  String get workspaceLabel => switch (environment) {
    'production' => 'Production workspace',
    'staging' => 'Staging workspace',
    'preview' => 'Preview workspace • Sample data',
    _ =>
      isSupabaseConfigured
          ? 'Development workspace'
          : 'Development preview • Sample data',
  };

  String get supabaseOrigin => Uri.parse(supabaseUrl).origin;

  RuntimeStartupMode startupMode({required bool isRelease}) {
    if (!const {
      'development',
      'staging',
      'production',
      'preview',
    }.contains(environment)) {
      throw const RuntimeStartupException(
        RuntimeStartupFailure.invalidEnvironment,
      );
    }
    final noConnection = supabaseUrl.isEmpty && supabasePublishableKey.isEmpty;
    if (environment == 'preview') {
      if (!noConnection || supabaseProjectRef.isNotEmpty) {
        throw const RuntimeStartupException(
          RuntimeStartupFailure.previewConnection,
        );
      }
      return RuntimeStartupMode.preview;
    }
    // Keep local developer/test previews, while an ordinary release without
    // build configuration must never silently become a synthetic workspace.
    if (!isRelease &&
        environment == 'development' &&
        noConnection &&
        supabaseProjectRef.isEmpty) {
      return RuntimeStartupMode.preview;
    }
    if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
      throw const RuntimeStartupException(
        RuntimeStartupFailure.missingConnection,
      );
    }
    if (!_validServerAddress) {
      throw const RuntimeStartupException(
        RuntimeStartupFailure.invalidServerAddress,
      );
    }
    if (!_validPublicKey) {
      throw const RuntimeStartupException(
        RuntimeStartupFailure.invalidPublicKey,
      );
    }
    final host = Uri.parse(supabaseUrl).host;
    final hosted = RegExp(r'^([a-z0-9-]+)\.supabase\.co$').firstMatch(host);
    final hostedRef = hosted?.group(1);
    final keyRef = _legacyKeyClaims?['ref'];
    if ((keyRef != null && keyRef is! String) ||
        (hostedRef != null && keyRef != null && keyRef != hostedRef) ||
        (isProduction && supabaseProjectRef.isEmpty) ||
        (supabaseProjectRef.isNotEmpty &&
            (!RegExp(
                  r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$',
                ).hasMatch(supabaseProjectRef) ||
                hostedRef != supabaseProjectRef ||
                (keyRef != null && keyRef != supabaseProjectRef)))) {
      throw const RuntimeStartupException(
        RuntimeStartupFailure.projectMismatch,
      );
    }
    return RuntimeStartupMode.connected;
  }

  bool get _validServerAddress {
    try {
      final uri = Uri.parse(supabaseUrl);
      return supabaseUrl == supabaseUrl.trim() &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty &&
          (uri.path.isEmpty || uri.path == '/') &&
          !uri.hasQuery &&
          !uri.hasFragment &&
          uri.port > 0 &&
          uri.port <= 65535;
    } on Object {
      return false;
    }
  }

  bool get _validPublicKey {
    final key = supabasePublishableKey;
    if (key.length > 8192 || key != key.trim()) return false;
    if (RegExp(r'^sb_publishable_[A-Za-z0-9_-]+$').hasMatch(key)) return true;
    return _legacyKeyClaims?['role'] == 'anon';
  }

  Map<String, Object?>? get _legacyKeyClaims {
    try {
      final parts = supabasePublishableKey.split('.');
      if (supabasePublishableKey.length > 8192 ||
          parts.length != 3 ||
          parts.any((part) => part.isEmpty)) {
        return null;
      }
      final header = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))),
      );
      if (header is! Map || header['alg'] == 'none') return null;
      final value = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return value is Map<String, Object?> ? value : null;
    } on Object {
      return null;
    }
  }
}
