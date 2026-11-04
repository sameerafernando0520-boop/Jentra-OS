import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:jentra_employee/src/data/employee_account_actions.dart';

class _Accounts implements EmployeeAccountGateway {
  @override
  String? actorId;
  int googleCalls = 0, resendCalls = 0;
  Uri? callback;
  Object? error;
  Completer<void>? wait;
  @override
  Future<void> google(Uri destination) async {
    googleCalls++;
    callback = destination;
    if (wait != null) await wait!.future;
    if (error != null) throw error!;
  }

  @override
  Future<void> resend(String email, Uri destination) async {
    resendCalls++;
    callback = destination;
    if (wait != null) await wait!.future;
    if (error != null) throw error!;
  }
}

void main() {
  final native = EmployeeAuthCallbackPolicy.native(development: true);
  test('native PKCE callback is restricted to this app identity and exact path', () {
    expect(
      native.callback.toString(),
      'com.jentra.employee.dev://auth/callback',
    );
    expect(
      native.allows(Uri.parse('${native.callback}?code=one-time-code')),
      isTrue,
    );
    for (final value in [
      'com.jentra.employee://auth/callback?code=x',
      'com.jentra.employee.dev://foreign/callback?code=x',
      'com.jentra.employee.dev://auth/callback/extra?code=x',
      '${native.callback}?code=x&code=y',
      '${native.callback}?code=x&error=denied',
      '${native.callback}#access_token=private-token&refresh_token=private-refresh',
      '${native.callback}?code=',
    ]) {
      expect(
        native.allows(Uri.parse(value)),
        isFalse,
        reason: 'Unexpected callback accepted',
      );
    }
  });
  test(
    'browser callbacks use a concrete approved HTTPS origin and same path',
    () {
      final web = EmployeeAuthCallbackPolicy.browser(
        Uri.parse('https://jentra-os--employee-qa-20261023-j8c2pxwt.web.app/'),
      );
      expect(web.callback.path, '/auth/callback');
      expect(web.allows(Uri.parse('${web.callback}?code=x')), isTrue);
      expect(
        web.allows(Uri.parse('https://attacker.example/auth/callback?code=x')),
        isFalse,
      );
      expect(web.allows(Uri.parse('${web.callback.origin}/?code=x')), isFalse);
      expect(web.allows(Uri.parse('${web.callback}#code=x')), isFalse);
      expect(
        web.allows(
          Uri.parse(
            '${web.callback}#error=access_denied&error_description=cancelled',
          ),
        ),
        isTrue,
      );
      for (final value in [
        'http://jentra-os.web.app/',
        'https://jentra-os.web.app:444/',
        'https://attacker.example/',
        'https://jentra-os.web.app.attacker.example/',
      ]) {
        expect(
          () => EmployeeAuthCallbackPolicy.browser(Uri.parse(value)),
          throwsStateError,
        );
      }
    },
  );
  test('signed-in users cannot start a competing sign-in or resend', () async {
    final backend = _Accounts()..actorId = 'current-account';
    final actions = EmployeeAccountActions(gateway: backend, policy: native);
    addTearDown(actions.dispose);
    await actions.google();
    await actions.resend('employee@example.test');
    expect(backend.googleCalls, 0);
    expect(backend.resendCalls, 0);
    expect(actions.failure, EmployeeAccountFailure.signInRequired);
  });
  test(
    'pending Google launch blocks overlapping actions and uses exact callback',
    () async {
      final backend = _Accounts()..wait = Completer<void>();
      final actions = EmployeeAccountActions(gateway: backend, policy: native);
      addTearDown(actions.dispose);
      final pending = actions.google();
      await actions.resend('employee@example.test');
      await actions.google();
      expect(actions.busy, isTrue);
      expect(backend.googleCalls, 1);
      expect(backend.resendCalls, 0);
      backend.wait!.complete();
      await pending;
      expect(backend.callback, native.callback);
      expect(actions.notice, EmployeeAccountNotice.googleOpened);
      expect(actions.busy, isFalse);
    },
  );
  test(
    'disabled provider produces a fixed category without provider output',
    () async {
      final backend = _Accounts()
        ..error = const GoogleSignInException(
          GoogleSignInFailure.providerDisabled,
        );
      final actions = EmployeeAccountActions(gateway: backend, policy: native);
      addTearDown(actions.dispose);
      await actions.google();
      expect(actions.failure, EmployeeAccountFailure.googleDisabled);
      expect(actions.notice, isNull);
    },
  );
  test(
    'invalid email is rejected and does not send or reserve resend cooldown',
    () async {
      final backend = _Accounts();
      final actions = EmployeeAccountActions(gateway: backend, policy: native);
      addTearDown(actions.dispose);
      await actions.resend('not-an-email');
      expect(backend.resendCalls, 0);
      expect(actions.failure, EmployeeAccountFailure.invalidEmail);
      await actions.resend('employee@example.test');
      expect(backend.resendCalls, 1);
      expect(actions.notice, EmployeeAccountNotice.confirmationRequested);
    },
  );
  test(
    'uncertain resend stays throttled; elapsed cooldown permits a new attempt',
    () async {
      var now = DateTime.utc(2026, 10, 26);
      final backend = _Accounts()
        ..error = TimeoutException('untrusted provider response');
      final actions = EmployeeAccountActions(
        gateway: backend,
        policy: native,
        now: () => now,
      );
      addTearDown(actions.dispose);
      await actions.resend('employee@example.test');
      await actions.resend('employee@example.test');
      expect(backend.resendCalls, 1);
      expect(actions.failure, EmployeeAccountFailure.waitBeforeResend);
      now = now.add(const Duration(minutes: 1));
      backend.error = null;
      await actions.resend('employee@example.test');
      expect(backend.resendCalls, 2);
      expect(actions.notice, EmployeeAccountNotice.confirmationRequested);
    },
  );
  test(
    'late provider error cannot overwrite a newly signed-in account',
    () async {
      final backend = _Accounts()
        ..wait = Completer<void>()
        ..error = StateError('sensitive return');
      final actions = EmployeeAccountActions(gateway: backend, policy: native);
      addTearDown(actions.dispose);
      final pending = actions.google();
      backend.actorId = 'new-account';
      backend.wait!.complete();
      await pending;
      expect(actions.failure, isNull);
      expect(actions.notice, isNull);
    },
  );
  test(
    'SDK callback errors become a fixed message rather than uncaught errors',
    () async {
      final events = StreamController<AuthState>.broadcast(sync: true);
      final actions = EmployeeAccountActions(
        gateway: _Accounts(),
        policy: native,
        authEvents: events.stream,
      );
      events.addError(
        StateError('private callback and token must not be shown'),
      );
      expect(actions.failure, EmployeeAccountFailure.callbackRejected);
      expect(actions.failure.toString(), isNot(contains('private callback')));
      actions.dispose();
      await events.close();
    },
  );
}
