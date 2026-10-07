import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_milestones.dart';
import 'package:jentra_platform/jentra_milestones_platform.dart';
import 'support/wave4_gateway_harness.dart';

void main() {
  late Wave4GatewayHarness h;
  late SupabaseMilestoneGateway g;
  setUp(() async {
    h = Wave4GatewayHarness();
    await h.initialize();
    g = SupabaseMilestoneGateway(h.client);
  });
  tearDown(() async => h.dispose());
  test(
    'uninstalled named milestone endpoint reports an explicit gate',
    () async {
      h.status = 404;
      h.response = {'code': 'PGRST202', 'message': 'Function not found'};
      await expectLater(
        g.list(w4Scope, w4Id),
        throwsA(
          isA<DomainError>().having(
            (e) => e.code,
            'code',
            'FEATURE_NOT_INSTALLED',
          ),
        ),
      );
    },
  );
  test(
    'late account read is rejected before project data can be shown',
    () async {
      h.gate = Completer<void>();
      h.response = {
        ...h.scope(),
        'project_id': w4Id,
        'items': [],
        'next_after': null,
      };
      final read = g.list(w4Scope, w4Id);
      while (h.requests.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      await h.client.auth.signOut();
      h.gate!.complete();
      await expectLater(
        read,
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
  test('malformed scoped page never crosses typed adapter', () async {
    h.response = {
      ...h.scope(),
      'project_id': w4Id,
      'items': [],
      'next_after': w4Revision,
    };
    await expectLater(g.list(w4Scope, w4Id), throwsFormatException);
    h.response = {
      ...h.scope(),
      'branch_id': w4Revision,
      'project_id': w4Id,
      'items': [],
      'next_after': null,
    };
    await expectLater(g.list(w4Scope, w4Id), throwsFormatException);
  });
  test(
    'actual rollback projections cross strict directory and history boundaries',
    () async {
      final samples = milestoneMap(
        jsonDecode(
          File(
            'test/fixtures/milestone_rollback_projections.json',
          ).readAsStringSync(),
        ),
      );
      for (final name in ['events', 'revisions', 'corrected_revisions']) {
        final raw = milestoneMap(samples[name]),
            record = milestoneMap(raw['record']);
        final s = TenantContext(
          tenantId: record['tenant_id'] as String,
          actorId: w4Scope.actorId,
          legalEntityId: record['legal_entity_id'] as String,
          branchId: record['branch_id'] as String,
        );
        h.response = raw;
        final d = await g.detail(
          s,
          record['project_id'] as String,
          record['id'] as String,
          kind: raw['kind'] as String,
        );
        expect(d.rows, isNotEmpty);
        h.response = {
          ...raw,
          'record': {...record, 'private_cost': '1'},
        };
        await expectLater(
          g.detail(
            s,
            record['project_id'] as String,
            record['id'] as String,
            kind: raw['kind'] as String,
          ),
          throwsFormatException,
        );
      }
      final directory = milestoneMap(samples['directory']),
          first = milestoneMap((directory['items'] as List).first);
      final s = TenantContext(
        tenantId: first['tenant_id'] as String,
        actorId: w4Scope.actorId,
        legalEntityId: first['legal_entity_id'] as String,
        branchId: first['branch_id'] as String,
      );
      h.response = directory;
      expect(
        (await g.list(
          s,
          first['project_id'] as String,
        )).rows.single.amount.toDecimalString(),
        '125.250000',
      );
    },
  );
  test(
    'late known command receipt stays valid for original-scope acknowledgement',
    () async {
      final samples = milestoneMap(
            jsonDecode(
              File(
                'test/fixtures/milestone_rollback_projections.json',
              ).readAsStringSync(),
            ),
          ),
          raw = milestoneMap(samples['create_receipt']),
          e = milestoneMap(raw['entity']),
          rev = milestoneMap(
            (milestoneMap(samples['revisions'])['rows'] as List).first,
          );
      final s = TenantContext(
        tenantId: e['tenant_id'] as String,
        actorId: w4Scope.actorId,
        legalEntityId: e['legal_entity_id'] as String,
        branchId: e['branch_id'] as String,
      );
      final c = CommandEnvelope<Map<String, Object?>>(
        commandId: raw['command_id'] as String,
        idempotencyKey: w4Command,
        context: s,
        expectedEntityVersion: 0,
        payload: {
          'action': 'create',
          'id': e['id'],
          'project_id': e['project_id'],
          'reason': rev['reason'],
          for (final k in [
            'plan_id',
            'task_id',
            'owner_id',
            'name',
            'due_date',
            'amount',
            'commercial_terms',
            'payment_terms',
            'payment_due_days',
            'evidence_reference',
          ])
            k: rev[k],
        },
      );
      h.response = raw;
      h.gate = Completer<void>();
      final work = g.execute(c);
      while (h.requests.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      await h.client.auth.signOut();
      h.gate!.complete();
      expect((await work)['command_id'], c.commandId);
    },
  );
}
