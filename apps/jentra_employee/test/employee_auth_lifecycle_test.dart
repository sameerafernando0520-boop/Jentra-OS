import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:jentra_employee/src/data/employee_gateway.dart';
import 'package:jentra_employee/src/data/employee_storage.dart';
import 'package:jentra_employee/src/employee_controller.dart';

import 'support/employee_fixture.dart';

class AuthStore extends FixtureStore {
  bool deletionFails = false;
  Completer<void>? writeGate;
  final writeStarted = Completer<void>();
  @override
  Future<void> write(String key, String value) async {
    if (!writeStarted.isCompleted) writeStarted.complete();
    await writeGate?.future;
    await super.write(key, value);
  }

  @override
  Future<void> delete(String key) async {
    if (deletionFails && key.contains('auth.session')) {
      throw StateError('synthetic native deletion failure');
    }
    await super.delete(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AuthStore store;
  late EmployeeAuthStorage auth;
  late Supabase supabase;
  setUp(() async {
    store = AuthStore();
    auth = EmployeeAuthStorage(store);
    final claims = base64Url.encode(
      utf8.encode(
        jsonEncode({
          'sub': fixtureActor,
          'role': 'authenticated',
          'exp': 4102444800,
        }),
      ),
    );
    supabase = await Supabase.initialize(
      url: 'https://auth-lifecycle.example.test',
      publishableKey: 'synthetic',
      debug: false,
      authOptions: FlutterAuthClientOptions(
        localStorage: auth,
        pkceAsyncStorage: EmployeePkceStorage(store),
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/token')) {
          return http.Response(
            jsonEncode({
              'access_token': 'e30.$claims.synthetic',
              'refresh_token': 'synthetic',
              'expires_in': 3600,
              'token_type': 'bearer',
              'user': {
                'id': fixtureActor,
                'aud': 'authenticated',
                'app_metadata': {},
                'user_metadata': {},
                'created_at': '2026-09-01T00:00:00Z',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  });
  tearDown(() async {
    await supabase.dispose();
  });

  test('initialized auth lifecycle cannot claim durable logout when deletion fails', () async {
    final gateway = SupabaseEmployeeGateway(supabase.client, authStorage: auth);
    await gateway.signIn('synthetic@example.test', 'synthetic');
    await store.writeStarted.future;
    await Future<void>.delayed(Duration.zero);
    store.deletionFails = true;
    final controller = EmployeeController(
      gateway: gateway,
      draftStore: EmployeeDraftStore(store),
    );
    await controller.signOut();
    expect(gateway.actorId, isNull);
    expect(controller.phase, EmployeePhase.locked);
    expect(controller.error?.code, 'DURABLE_LOGOUT_INCOMPLETE');
    expect(await auth.accessToken(), isNotNull);
    await controller.resume();
    expect(controller.phase, EmployeePhase.locked);
    store.deletionFails = false;
    await controller.signOut();
    expect(controller.phase, EmployeePhase.signedOut);
    expect(await auth.accessToken(), isNull);
    controller.dispose();
  });

  test('initialized auth logout drains overlapping old session writes before confirming removal', () async {
    final gateway = SupabaseEmployeeGateway(supabase.client, authStorage: auth);
    store.writeGate = Completer();
    await gateway.signIn('synthetic@example.test', 'synthetic');
    await store.writeStarted.future;
    var finished = false;
    final logout = gateway.signOut().then((_) {
      finished = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    store.writeGate!.complete();
    await logout;
    await Future<void>.delayed(Duration.zero);
    expect(await auth.accessToken(), isNull);
    expect(gateway.actorId, isNull);
  });
}
