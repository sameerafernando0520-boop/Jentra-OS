import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_platform/jentra_platform.dart';

const _project = 'aaaaaaaaaaaaaaaaaaaa';
const _otherProject = 'bbbbbbbbbbbbbbbbbbbb';
const _publicKey = 'sb_publishable_synthetic-public-key';

String _jwt({
  String role = 'anon',
  Object? ref = _project,
  String algorithm = 'HS256',
}) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': algorithm, 'typ': 'JWT'})}.${part({'role': role, 'ref': ?ref})}.synthetic-signature';
}

RuntimeConfig _config({
  String environment = 'development',
  String url = 'https://$_project.supabase.co',
  String key = _publicKey,
  String project = '',
}) => RuntimeConfig(
  environment: environment,
  supabaseUrl: url,
  supabasePublishableKey: key,
  supabaseProjectRef: project,
);

Matcher _failure(RuntimeStartupFailure failure) =>
    isA<RuntimeStartupException>().having((e) => e.failure, 'failure', failure);

void main() {
  test('only local debug defaults and explicit preview can omit backend', () {
    final missing = _config(url: '', key: '');
    expect(missing.startupMode(isRelease: false), RuntimeStartupMode.preview);
    expect(
      () => missing.startupMode(isRelease: true),
      throwsA(_failure(RuntimeStartupFailure.missingConnection)),
    );
    expect(
      _config(
        environment: 'preview',
        url: '',
        key: '',
      ).startupMode(isRelease: true),
      RuntimeStartupMode.preview,
    );
    for (final environment in ['production', 'staging']) {
      expect(
        () => _config(
          environment: environment,
          url: '',
          key: '',
        ).startupMode(isRelease: false),
        throwsA(_failure(RuntimeStartupFailure.missingConnection)),
      );
    }
  });

  test('preview cannot accidentally connect to a real backend', () {
    for (final config in [
      _config(environment: 'preview'),
      _config(environment: 'preview', url: '', key: '', project: _project),
    ]) {
      expect(
        () => config.startupMode(isRelease: true),
        throwsA(_failure(RuntimeStartupFailure.previewConnection)),
      );
    }
  });

  test('unknown environment never falls back to preview', () {
    expect(
      () => _config(
        environment: 'prod',
        url: '',
        key: '',
      ).startupMode(isRelease: true),
      throwsA(_failure(RuntimeStartupFailure.invalidEnvironment)),
    );
  });

  test('partial connection cannot become a debug preview', () {
    for (final config in [_config(key: ''), _config(url: '')]) {
      expect(
        () => config.startupMode(isRelease: false),
        throwsA(_failure(RuntimeStartupFailure.missingConnection)),
      );
    }
  });

  for (final url in [
    'http://$_project.supabase.co',
    'ftp://$_project.supabase.co',
    'javascript:alert(1)',
    'https://',
    'https://user:private@$_project.supabase.co',
    'https://$_project.supabase.co/auth/v1',
    'https://$_project.supabase.co?key=private',
    'https://$_project.supabase.co#private',
    ' https://$_project.supabase.co',
    'https://$_project.supabase.co ',
  ]) {
    test('invalid server address is rejected before initialization: $url', () {
      final config = _config(url: url);
      expect(config.isSupabaseConfigured, isFalse);
      expect(
        () => config.startupMode(isRelease: true),
        throwsA(_failure(RuntimeStartupFailure.invalidServerAddress)),
      );
    });
  }

  test(
    'publishable and legacy anon keys support a bound connected release',
    () {
      for (final key in [_publicKey, _jwt()]) {
        expect(
          _config(
            environment: 'production',
            key: key,
            project: _project,
          ).startupMode(isRelease: true),
          RuntimeStartupMode.connected,
        );
      }
      expect(
        _config(url: 'https://$_project.supabase.co/').supabaseOrigin,
        'https://$_project.supabase.co',
      );
    },
  );

  test(
    'secret, elevated, malformed and opaque keys cannot initialize client',
    () {
      for (final key in [
        'sb_secret_synthetic-private-key',
        _jwt(role: 'service_role'),
        _jwt(role: 'authenticated'),
        _jwt(algorithm: 'none'),
        'not-a-public-api-key',
        'sb_publishable_',
        '$_publicKey\n',
        'eyJbroken.payload.signature',
      ]) {
        expect(
          () => _config(key: key).startupMode(isRelease: true),
          throwsA(
            allOf(
              _failure(RuntimeStartupFailure.invalidPublicKey),
              predicate((error) => !error.toString().contains(key)),
            ),
          ),
        );
      }
    },
  );

  test(
    'project binding catches wrong URL, wrong legacy key and absent production target',
    () {
      for (final config in [
        _config(environment: 'production'),
        _config(project: _otherProject),
        _config(key: _jwt(ref: _otherProject)),
        _config(key: _jwt(ref: 12)),
        _config(project: 'invalid.project'),
      ]) {
        expect(
          () => config.startupMode(isRelease: true),
          throwsA(_failure(RuntimeStartupFailure.projectMismatch)),
        );
      }
    },
  );

  test(
    'environment caption does not invent region or synthetic data status',
    () {
      expect(
        _config(environment: 'production').workspaceLabel,
        'Production workspace',
      );
      expect(
        _config(environment: 'staging').workspaceLabel,
        'Staging workspace',
      );
      expect(_config().workspaceLabel, 'Development workspace');
      expect(
        _config(environment: 'preview', url: '', key: '').workspaceLabel,
        'Preview workspace • Sample data',
      );
    },
  );

  test(
    'platform rejects unconfigured release before Supabase initialization',
    () async {
      await expectLater(
        SupabasePlatform.initialize(_config(url: '', key: ''), isRelease: true),
        throwsA(_failure(RuntimeStartupFailure.missingConnection)),
      );
      expect(
        await SupabasePlatform.initialize(
          _config(environment: 'preview', url: '', key: ''),
          isRelease: true,
        ),
        isNull,
      );
    },
  );
}
