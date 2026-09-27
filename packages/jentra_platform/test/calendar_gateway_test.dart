import 'dart:convert';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_platform/jentra_people_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _tenant = '10000000-0000-0000-0000-000000000001';
const _entity = '10000000-0000-0000-0000-000000000002';
const _branch = '10000000-0000-0000-0000-000000000003';
const _actor = '10000000-0000-0000-0000-000000000004';
const _calendar = '20000000-0000-0000-0000-000000000001';
const _version = '30000000-0000-0000-0000-000000000001';
const _command = '40000000-0000-0000-0000-000000000001';
const _scope = TenantContext(
  tenantId: _tenant,
  legalEntityId: _entity,
  branchId: _branch,
  actorId: _actor,
);

void main() {
  late SupabaseClient client;
  late SupabaseCalendarGateway gateway;
  Object response = {};
  var status = 200;
  Completer<void>? responseGate;
  final requests = <http.Request>[];
  setUp(() async {
    response = {};
    status = 200;
    requests.clear();
    responseGate = null;
    client = SupabaseClient(
      'https://example.test',
      'synthetic-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/token')) {
          final claims = base64Url
              .encode(
                utf8.encode(
                  jsonEncode({
                    'sub': _actor,
                    'role': 'authenticated',
                    'exp': 4102444800,
                  }),
                ),
              )
              .replaceAll('=', '');
          return http.Response(
            jsonEncode({
              'access_token':
                  'eyJhbGciOiJIUzI1NiJ9.$claims.synthetic-signature',
              'refresh_token': 'synthetic',
              'expires_in': 3600,
              'token_type': 'bearer',
              'user': {
                'id': _actor,
                'aud': 'authenticated',
                'app_metadata': {},
                'user_metadata': {},
                'created_at': '2026-09-01T00:00:00Z',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        requests.add(request);
        if (request.url.path.contains('/rpc/')) {
          await responseGate?.future;
        }
        return http.Response(
          jsonEncode(response),
          status,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'actor@example.test',
      password: 'synthetic-only',
    );
    gateway = SupabaseCalendarGateway(client);
  });
  tearDown(() => client.dispose());
  Map<String, Object?> identity({String id = _calendar, int version = 1}) => {
    'id': id,
    'tenant_id': _tenant,
    'legal_entity_id': _entity,
    'code': 'HQ',
    'name': 'Head Office',
    'version': version,
  };
  Map<String, Object?> coverage({String id = _version}) => {
    'id': id,
    'start_date': '2026-09-01',
    'end_date_exclusive': '2027-01-01',
    'timezone': 'Asia/Colombo',
  };
  Map<String, Object?> summary() => {
    ...coverage(),
    'published_by': _actor,
    'published_at': '2026-09-26T00:00:00+00:00',
  };
  Map<String, Object?> page(List<Object?> items, {bool directory = false}) => {
    'tenant_id': _tenant,
    'legal_entity_id': _entity,
    'branch_id': _branch,
    if (directory) 'as_of': '2026-09-26' else 'calendar_id': _calendar,
    'items': items,
  };
  Map<String, Object?> detail() => {
    'tenant_id': _tenant,
    'legal_entity_id': _entity,
    'branch_id': _branch,
    'calendar': identity(),
    'calendar_version': {
      ...summary(),
      'calendar_id': _calendar,
      'tenant_id': _tenant,
      'legal_entity_id': _entity,
      'weekly_intervals': [
        {
          'day_of_week': 7,
          'start_minute': 1320,
          'end_minute': 360,
          'end_day_offset': 1,
        },
      ],
      'date_overrides': [
        {
          'date': '2026-09-28',
          'is_working_day': false,
          'reason': 'Synthetic closure',
        },
      ],
    },
  };
  Map<String, Object?> payload() => {
    'id': _calendar,
    'code': 'HQ',
    'name': 'Head Office',
    'version_id': _version,
    'start_date': '2026-09-01',
    'end_date_exclusive': '2027-01-01',
    'timezone': 'Asia/Colombo',
    'weekly_intervals': <Object?>[],
    'date_overrides': <Object?>[],
    'reason': 'Synthetic calendar',
  };
  CommandEnvelope<Map<String, Object?>> command() => CommandEnvelope(
    commandId: _command,
    idempotencyKey: '40000000-0000-0000-0000-000000000002',
    context: _scope,
    payload: payload(),
    expectedEntityVersion: 0,
    clientTimestamp: DateTime.utc(2026, 9, 26),
  );
  Map<String, Object?> confirmation() => {
    'request_id': _command,
    'command_id': _command,
    'correlation_id': _command,
    'entity': {...identity(), 'published_version_id': _version},
    'warnings': <Object?>[],
  };

  test(
    'directory keeps literal filters and explicit missing coverage',
    () async {
      response = page([
        {...identity(), 'selected_version': null},
      ], directory: true);
      final result = await gateway.directory(
        _scope,
        asOfDate: '2026-09-26',
        search: '_%',
      );
      expect(result.page.items.single.coverage, isNull);
      expect(result.asOf.value, '2026-09-26');
      expect(requests.single.headers['content-profile'], 'api');
      expect(jsonDecode(requests.single.body), containsPair('p_search', '_%'));
      expect(
        jsonDecode(requests.single.body),
        containsPair('p_branch_id', _branch),
      );
    },
  );
  test(
    'directory refuses foreign scope, date drift and unexpected fields',
    () async {
      for (final mutation in ['scope', 'date', 'private', 'coverage']) {
        final row = {...identity(), 'selected_version': coverage()};
        final data = page([row], directory: true);
        if (mutation == 'scope') data['branch_id'] = _entity;
        if (mutation == 'date') data['as_of'] = '2026-09-27';
        if (mutation == 'private') {
          row['private_profile'] = {'phone': 'must not be visible'};
        }
        if (mutation == 'coverage') {
          row['selected_version'] = {...coverage(), 'start_date': '2026-10-01'};
        }
        response = data;
        await expectLater(
          gateway.directory(_scope, asOfDate: '2026-09-26'),
          throwsA(anything),
        );
      }
    },
  );
  test(
    'UUID keyset pages enforce order and expose continuation at the bound',
    () async {
      final rows = [
        for (var i = 1; i <= 50; i++)
          {
            ...identity(
              id: '20000000-0000-0000-0000-${i.toString().padLeft(12, '0')}',
            ),
            'selected_version': null,
          },
      ];
      response = page(rows, directory: true);
      final result = await gateway.directory(_scope);
      expect(result.page.nextCursor, rows.last['id']);
      response = page([rows.last, rows.first], directory: true);
      await expectLater(gateway.directory(_scope), throwsFormatException);
      response = page([rows.first], directory: true);
      await expectLater(
        gateway.directory(_scope, after: _calendar),
        throwsFormatException,
      );
    },
  );
  test(
    'detail validates immutable version ancestry and overnight pattern',
    () async {
      response = detail();
      final result = await gateway.detail(_scope, _calendar, _version);
      expect(result.version.pattern.weeklyIntervals.single.endDayOffset, 1);
      final changed = detail();
      (changed['calendar_version'] as Map)['calendar_id'] = _version;
      response = changed;
      await expectLater(
        gateway.detail(_scope, _calendar, _version),
        throwsFormatException,
      );
      final outside = detail();
      ((outside['calendar_version'] as Map)['date_overrides'] as List)
              .single['date'] =
          '2027-01-01';
      response = outside;
      await expectLater(
        gateway.detail(_scope, _calendar, _version),
        throwsFormatException,
      );
    },
  );
  test(
    'version pages reject unbounded schedules and hidden response fields',
    () async {
      response = page([summary()]);
      expect(
        (await gateway.versions(
          _scope,
          _calendar,
        )).items.single.coverage.timezone,
        'Asia/Colombo',
      );
      response = page([
        {...summary(), 'end_date_exclusive': null},
      ]);
      await expectLater(gateway.versions(_scope, _calendar), throwsA(anything));
      response = page([
        {...summary(), 'bank_details': 'forbidden'},
      ]);
      await expectLater(
        gateway.versions(_scope, _calendar),
        throwsFormatException,
      );
    },
  );
  test('history validates scope and attributable revision lineage', () async {
    final event = <String, Object?>{
      'id': _command,
      'action': 'create',
      'published_version_id': _version,
      'effective_date': '2026-09-01',
      'reason': 'Synthetic setup',
      'actor_id': _actor,
      'recorded_at': '2026-09-26T00:00:00Z',
      'before_state': <String, Object?>{},
      'after_state': {...identity(), 'published_version_id': _version},
    };
    response = page([event]);
    expect(
      (await gateway.history(
        _scope,
        _calendar,
      )).items.single.after.calendar.version,
      1,
    );
    response = page([
      {
        ...event,
        'after_state': {
          ...identity(version: 2),
          'published_version_id': _version,
        },
      },
    ]);
    await expectLater(
      gateway.history(_scope, _calendar),
      throwsFormatException,
    );
    response = page([
      {...event, 'actor_id': null},
    ]);
    await expectLater(
      gateway.history(_scope, _calendar),
      throwsFormatException,
    );
  });
  test(
    'command confirmation matches identity, revision and published version',
    () async {
      response = confirmation();
      final result = await gateway.execute('create', command());
      expect(result.calendar.code, 'HQ');
      expect(result.publishedVersionId, _version);
      final wire = jsonDecode(requests.single.body) as Map;
      expect(wire['p_expected_version'], 0);
      expect((wire['p_payload'] as Map)['action'], 'create');
      expect(wire['p_command_id'], _command);
    },
  );
  test(
    'malformed or substituted write results are uncertain, never confirmed',
    () async {
      for (final field in [
        'command',
        'identity',
        'version',
        'publication',
        'raw',
      ]) {
        final data = confirmation();
        if (field == 'command') data['command_id'] = _version;
        if (field == 'identity') (data['entity'] as Map)['id'] = _version;
        if (field == 'version') (data['entity'] as Map)['version'] = 2;
        if (field == 'publication') {
          (data['entity'] as Map)['published_version_id'] = null;
        }
        response = field == 'raw' ? <Object?>[] : data;
        await expectLater(
          gateway.execute('create', command()),
          throwsA(
            isA<DomainError>().having(
              (e) => e.code,
              'code',
              'UNCERTAIN_RESULT',
            ),
          ),
        );
      }
    },
  );
  test(
    'missing service, MFA, entitlement, overlap and historical denial are distinct',
    () async {
      for (final row in [
        ('PGRST202', 'missing', 'FEATURE_NOT_INSTALLED'),
        ('42501', 'PEOPLE_ENTITLEMENT_REQUIRED', 'FEATURE_NOT_ENTITLED'),
        ('42501', 'MFA_REQUIRED', 'PERMISSION_DENIED'),
        ('23P01', 'date exclusion', 'CALENDAR_OVERLAP'),
        (
          '55000',
          'CALENDAR_RETROACTIVE_CHANGE_REQUIRED',
          'CALENDAR_RETROACTIVE_CHANGE_REQUIRED',
        ),
      ]) {
        status = 400;
        response = {
          'code': row.$1,
          'message': row.$2,
          'details': null,
          'hint': null,
        };
        await expectLater(
          gateway.execute('create', command()),
          throwsA(isA<DomainError>().having((e) => e.code, 'code', row.$3)),
        );
      }
    },
  );
  test(
    'AC-405 local resolver binds version zone boundary and exact UTC',
    () async {
      final version = CalendarVersionDetail.fromJson(
        detail()['calendar_version'] as Map<String, Object?>,
      );
      response = {
        'tenant_id': _tenant,
        'legal_entity_id': _entity,
        'branch_id': _branch,
        'resolution': {
          'calendar_version_id': _version,
          'date': '2026-09-26',
          'minute': 540,
          'timezone': 'Asia/Colombo',
          'local_datetime': '2026-09-26T09:00:00',
          'algorithm': 'pg-iana-roundtrip-v1',
          'candidates': [
            {'utc': '2026-09-26T03:30:00Z', 'offset_seconds': 19800},
          ],
        },
      };
      final result = await gateway.localCandidates(
        _scope,
        version,
        CivilDate.parse('2026-09-26'),
        540,
      );
      expect(result.choose().utc, DateTime.utc(2026, 9, 26, 3, 30));
      final sent = jsonDecode(requests.single.body) as Map;
      expect(sent['p_version_id'], _version);
      expect(sent['p_branch_id'], _branch);
      expect(sent['p_minute'], 540);
      expect(
        requests.single.url.path,
        endsWith('/rpc/people_calendar_local_candidates'),
      );
    },
  );
  test(
    'AC-401 resolution response cannot substitute scope or calendar zone',
    () async {
      final version = CalendarVersionDetail.fromJson(
        detail()['calendar_version'] as Map<String, Object?>,
      );
      final row = {
        'calendar_version_id': _version,
        'date': '2026-09-26',
        'minute': 540,
        'timezone': 'Asia/Colombo',
        'local_datetime': '2026-09-26T09:00:00',
        'algorithm': 'pg-iana-roundtrip-v1',
        'candidates': [
          {'utc': '2026-09-26T03:30:00Z', 'offset_seconds': 19800},
        ],
      };
      for (final replacement in [
        {'tenant_id': _actor},
        {'branch_id': _actor},
        {
          'resolution': {...row, 'timezone': 'Asia/Kolkata'},
        },
        {
          'resolution': {...row, 'calendar_version_id': _calendar},
        },
      ]) {
        response = {
          'tenant_id': _tenant,
          'legal_entity_id': _entity,
          'branch_id': _branch,
          'resolution': row,
          ...replacement,
        };
        await expectLater(
          gateway.localCandidates(
            _scope,
            version,
            CivilDate.parse('2026-09-26'),
            540,
          ),
          throwsFormatException,
        );
      }
    },
  );
  test('AC-405 out-of-coverage resolution is rejected before RPC', () async {
    final version = CalendarVersionDetail.fromJson(
      detail()['calendar_version'] as Map<String, Object?>,
    );
    await expectLater(
      gateway.localCandidates(
        _scope,
        version,
        CivilDate.parse('2027-01-01'),
        540,
      ),
      throwsFormatException,
    );
    expect(requests, isEmpty);
  });
  test('actor substitution is rejected before a calendar request', () async {
    await expectLater(
      gateway.directory(
        const TenantContext(
          tenantId: _tenant,
          legalEntityId: _entity,
          branchId: _branch,
          actorId: _branch,
        ),
      ),
      throwsA(
        isA<DomainError>().having(
          (e) => e.code,
          'code',
          'AUTHENTICATION_REQUIRED',
        ),
      ),
    );
    expect(requests, isEmpty);
  });
  test('a calendar response arriving after sign-out is not exposed', () async {
    response = page([
      {...identity(), 'selected_version': null},
    ], directory: true);
    responseGate = Completer<void>();
    final pending = gateway.directory(_scope);
    final assertion = expectLater(
      pending,
      throwsA(
        isA<DomainError>().having(
          (e) => e.code,
          'code',
          'AUTHENTICATION_REQUIRED',
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await client.auth.signOut(scope: SignOutScope.local);
    responseGate!.complete();
    await assertion;
  });
}
