import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:jentra_sales/src/data/sales_gateway.dart';
import 'package:jentra_sales/src/data/sales_store.dart';
import 'package:jentra_sales/src/models.dart';
import 'package:jentra_sales/src/field_sales_controller.dart';
import 'package:jentra_sales/src/sales_controller.dart';

import 'support/field_sales_fixture.dart';

AuthResponse response() {
  final user = User(
    id: 'rep',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-10-31T00:00:00Z',
  );
  return AuthResponse(
    user: user,
    session: Session(
      accessToken: 'synthetic',
      refreshToken: 'synthetic',
      tokenType: 'bearer',
      user: user,
      expiresIn: 3600,
    ),
  );
}

class _Account implements SalesAccountGateway {
  final login = Completer<void>();
  int logouts = 0;
  @override
  Future<void> signIn(String email, String password) => login.future;
  @override
  Future<void> signOut() async {
    logouts++;
  }
}

void main() {
  test(
    'late credential completion is cleaned up and cannot overlap a new attempt',
    () async {
      final login = Completer<AuthResponse>();
      bool installed = false;
      int calls = 0;
      final account = SupabaseSalesAccountGateway.withAuth(
        enableCandidate: true,
        signInTimeout: const Duration(milliseconds: 5),
        signIn: (_, _) {
          calls++;
          return login.future;
        },
        signOut: () async {
          installed = false;
        },
      );
      await expectLater(
        account.signIn('synthetic@sales.invalid', 'synthetic'),
        throwsA(
          isA<SalesFailure>().having(
            (e) => e.code,
            'code',
            'CONNECTION_UNAVAILABLE',
          ),
        ),
      );
      await expectLater(
        account.signIn('synthetic@sales.invalid', 'synthetic'),
        throwsA(
          isA<SalesFailure>().having((e) => e.code, 'code', 'SIGN_IN_PENDING'),
        ),
      );
      expect(calls, 1);
      installed = true;
      login.complete(response());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(installed, isFalse);
    },
  );
  test(
    'leaving while sign-in is pending cannot reopen a governed workspace',
    () async {
      final account = _Account(),
          store = MemorySalesStore(),
          gateway = FakeFieldSalesGateway();
      final field = FieldSalesController(gateway: gateway, store: store);
      addTearDown(field.dispose);
      final c = SalesController(store: store, account: account, field: field);
      addTearDown(c.dispose);
      final login = c.signIn('synthetic@sales.invalid', 'synthetic');
      await c.leave();
      account.login.complete();
      await login;
      expect(field.isOpen, isFalse);
      expect(field.customers, isEmpty);
      expect(c.preview, isFalse);
      expect(account.logouts, greaterThanOrEqualTo(1));
    },
  );
  test(
    'default account mode clears the session and retains rollout-pending state',
    () async {
      var signedOut = false;
      final account = SupabaseSalesAccountGateway.withAuth(
        signIn: (_, _) async => response(),
        signOut: () async {
          signedOut = true;
        },
      );
      await expectLater(
        account.signIn('synthetic@sales.invalid', 'synthetic'),
        throwsA(
          isA<SalesFailure>().having(
            (e) => e.code,
            'code',
            'FIELD_SALES_ROLLOUT_PENDING',
          ),
        ),
      );
      expect(signedOut, isTrue);
    },
  );
}
