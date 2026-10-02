import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_platform/jentra_people_platform.dart';
import 'support/wave4_gateway_harness.dart';

void main() {
  late Wave4GatewayHarness h;
  late SupabasePrivateHrGateway gateway;
  Map<String, dynamic> body() =>
      jsonDecode(h.requests.last.body) as Map<String, dynamic>;
  setUp(() async {
    h = Wave4GatewayHarness();
    await h.initialize();
    gateway = SupabasePrivateHrGateway(h.client);
  });
  tearDown(() => h.dispose());
  test(
    'binary PDF transport keeps exact bytes and distinguishes export authority',
    () async {
      final bytes = Uint8List.fromList([37, 80, 68, 70, 45, 255, 0, 129]);
      final hash = (await Sha256().hash(
        bytes,
      )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final doc = HrRecord.fromJson(HrRecordKind.document, {
        'id': w4Id,
        'version': 2,
        'classification': 'review-evidence',
        'purpose': 'Synthetic binary',
        'mime': 'application/pdf',
        'byte_size': bytes.length,
        'checksum': hash,
        'status': 'active',
        'created_by': w4Scope.actorId,
        'created_at': '2026-09-28T00:00:00Z',
      });
      h.onRequest = (request) async => http.Response.bytes(
        bytes,
        200,
        headers: {'content-type': 'application/octet-stream'},
        request: request,
      );
      expect(await gateway.document(w4Scope, w4Id, doc), bytes);
      var meta =
          jsonDecode(
                utf8.decode(
                  base64Decode(h.requests.last.headers['x-jentra-hr-request']!),
                ),
              )
              as Map;
      expect(meta['operation'], 'download');
      expect(
        h.requests.last.url.path,
        endsWith('/functions/v1/people-private-documents'),
      );
      await gateway.document(w4Scope, w4Id, doc, export: true);
      meta =
          jsonDecode(
                utf8.decode(
                  base64Decode(h.requests.last.headers['x-jentra-hr-request']!),
                ),
              )
              as Map;
      expect(meta['operation'], 'export');
      h.onRequest = (request) async => http.Response.bytes(
        [1, 2, 3],
        200,
        headers: {'content-type': 'application/octet-stream'},
        request: request,
      );
      await expectLater(
        gateway.document(w4Scope, w4Id, doc),
        throwsFormatException,
      );
    },
  );
  test(
    'gateway freezes caller-owned private payload across delayed confirmation',
    () async {
      final payload = <String, Object?>{
        'action': 'profile_save',
        'id': w4Id,
        'employee_id': w4Id,
        'revision_id': w4Revision,
        'body': {for (final f in hrContactFields) f: null},
        'reason': 'Original synthetic reason',
      };
      final command = CommandEnvelope(
        commandId: w4Command,
        idempotencyKey: w4Command,
        context: w4Scope,
        payload: payload,
        expectedEntityVersion: 0,
        clientTimestamp: DateTime.utc(2026, 9, 28),
      );
      h.response = h.confirmed({
        'id': w4Id,
        ...h.scope(),
        'employee_id': w4Id,
        'version': 1,
        'action': 'profile_save',
        'revision_id': w4Revision,
        'digest': null,
      });
      h.gate = Completer();
      final pending = gateway.command(command);
      payload['id'] = w4Revision;
      payload['reason'] = 'Changed caller value';
      await Future<void>.delayed(Duration.zero);
      h.gate!.complete();
      expect((await pending).entity['id'], w4Id);
      expect(
        (body()['p_payload'] as Map)['reason'],
        'Original synthetic reason',
      );
    },
  );
  test(
    'private export retrieval validates its named scope and private allowlist',
    () async {
      h.response = {
        'format': 'w4-hr-export-v1',
        'export_id': w4Command,
        ...h.scope(),
        'employee_id': w4Id,
        'kind': 'profile',
        'source_id': w4Id,
        'source_version': 1,
        'revision_id': w4Revision,
        'body': {for (final f in hrContactFields) f: null},
        'digest': 'a' * 64,
        'recorded_by': w4Scope.actorId,
        'recorded_at': '2026-09-28T00:00:00Z',
      };
      expect(
        (await gateway.exportContent(w4Scope, w4Command))['revision_id'],
        w4Revision,
      );
      expect(
        h.requests.last.url.path,
        endsWith('/rpc/people_hr_export_content'),
      );
      (h.response as Map)['object_path'] = 'unsafe';
      await expectLater(
        gateway.exportContent(w4Scope, w4Command),
        throwsFormatException,
      );
    },
  );
  test(
    'dedicated private subject picker contains no operational/contact extras',
    () async {
      h.response = {
        ...h.scope(),
        'items': [
          {'id': w4Id, 'code': 'EMP', 'display_name': 'Synthetic Employee'},
        ],
        'next_cursor': null,
      };
      final page = await gateway.subjects(
        w4Scope,
        'people.hr.private.view',
        search: 'EMP',
      );
      expect(page.items.single.kind, HrRecordKind.subject);
      expect(h.requests.single.url.path, endsWith('/rpc/people_hr_subjects'));
      expect(body()['p_capability'], 'people.hr.private.view');
      h.response = {
        ...h.scope(),
        'items': [
          {
            'id': w4Id,
            'code': 'EMP',
            'display_name': 'Synthetic Employee',
            'personal_email': 'private',
          },
        ],
        'next_cursor': null,
      };
      await expectLater(
        gateway.subjects(w4Scope, 'people.hr.private.view'),
        throwsFormatException,
      );
    },
  );
  test(
    'profile response validates exact scope, identity and bounded nested fields',
    () async {
      final body = {for (final f in hrContactFields) f: null};
      h.response = {
        ...h.scope(),
        'employee_id': w4Id,
        'profile': {
          'employee_id': w4Id,
          'version': 1,
          'revision_id': w4Revision,
          'body': body,
          'recorded_by': w4Scope.actorId,
          'recorded_at': '2026-09-28T00:00:00Z',
        },
        'history': [],
        'next_cursor': null,
      };
      expect((await gateway.contacts(w4Scope, w4Id)).profile!.version, 1);
      (h.response as Map)['branch_id'] = w4Id;
      await expectLater(gateway.contacts(w4Scope, w4Id), throwsFormatException);
    },
  );
  test(
    'private pages reject oversize, duplicates and unrelated employee',
    () async {
      final row = {
        'id': w4Id,
        'version': 1,
        'classification': 'contact-support',
        'purpose': 'Synthetic support',
        'mime': 'text/plain',
        'byte_size': 3,
        'checksum': 'a' * 64,
        'status': 'reserved',
        'created_by': w4Scope.actorId,
        'created_at': '2026-09-28T00:00:00Z',
      };
      h.response = {
        ...h.scope(),
        'employee_id': w4Id,
        'items': [row, row],
        'next_cursor': null,
      };
      await expectLater(
        gateway.page(w4Scope, HrCollection.documents, employee: w4Id),
        throwsFormatException,
      );
      (h.response as Map)['items'] = List.filled(51, row);
      await expectLater(
        gateway.page(w4Scope, HrCollection.documents, employee: w4Id),
        throwsFormatException,
      );
    },
  );
  test(
    'current authorization checks the actual actor and discards late sign-out',
    () async {
      h.response = {'authorized': true, 'actor_id': w4Scope.actorId};
      await gateway.authorize(w4Scope, w4Id, 'people.hr.private.manage');
      h.gate = Completer<void>();
      final pending = gateway.authorize(
        w4Scope,
        w4Id,
        'people.hr.private.manage',
      );
      await Future<void>.delayed(const Duration(milliseconds: 15));
      await h.client.auth.signOut();
      h.gate!.complete();
      await expectLater(
        pending,
        throwsA(
          isA<DomainError>().having(
            (e) => e.code,
            'code',
            'AUTHENTICATION_REQUIRED',
          ),
        ),
      );
    },
  );
  test(
    'command confirmation is minimal and bound to the sealed request',
    () async {
      final p = {
        'action': 'profile_save',
        'id': w4Id,
        'employee_id': w4Id,
        'revision_id': w4Revision,
        'body': {for (final f in hrContactFields) f: null},
        'reason': 'Synthetic private reason',
      };
      final command = CommandEnvelope(
        commandId: w4Command,
        idempotencyKey: w4Command,
        context: w4Scope,
        payload: p,
        expectedEntityVersion: 0,
      );
      h.response = h.confirmed({
        'id': w4Id,
        ...h.scope(),
        'employee_id': w4Id,
        'version': 1,
        'action': 'profile_save',
        'revision_id': w4Revision,
        'digest': 'a' * 64,
      });
      expect((await gateway.command(command)).version, 1);
      expect(
        (body()['p_payload'] as Map)['reason'],
        'Synthetic private reason',
      );
      ((h.response as Map)['entity'] as Map)['personal_email'] = 'private';
      await expectLater(gateway.command(command), throwsFormatException);
    },
  );
  test(
    'retention and raw database failures map to safe messages only',
    () async {
      for (final entry in {
        '55000': 'HR_RETENTION_WORKER_UNAVAILABLE',
        '42501': 'PRIVATE_VALUE',
        'XX000': 'PRIVATE_VALUE',
      }.entries) {
        h.status = 400;
        h.response = {
          'code': entry.key,
          'message': entry.value,
          'details': 'PRIVATE_VALUE',
        };
        await expectLater(
          gateway.contacts(w4Scope, w4Id),
          throwsA(
            isA<DomainError>().having(
              (e) => e.message,
              'safe message',
              isNot(contains('PRIVATE_VALUE')),
            ),
          ),
        );
      }
    },
  );
  test(
    'minimal own receipt is actor/scoped and never accepts a private snapshot',
    () async {
      h.response = h.confirmed({
        'id': w4Id,
        ...h.scope(),
        'employee_id': w4Id,
        'version': 1,
        'action': 'profile_save',
        'revision_id': w4Revision,
        'digest': 'a' * 64,
      });
      expect((await gateway.receipt(w4Scope, w4Command))!.commandId, w4Command);
      ((h.response as Map)['entity'] as Map)['body'] = {
        'personal_phone': 'private',
      };
      await expectLater(
        gateway.receipt(w4Scope, w4Command),
        throwsFormatException,
      );
    },
  );
}
