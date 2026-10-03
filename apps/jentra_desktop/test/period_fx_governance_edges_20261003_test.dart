import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:jentra_desktop/src/features/period_fx/period_fx_controller.dart';

import 'period_fx_workspace_test.dart' show PeriodFxFake;
import 'support/procurement_fakes.dart' show Keys;

class GovernanceGateway implements PeriodFxGateway {
  final delegate = PeriodFxFake();
  bool blocked = false;
  Completer<void>? detailPause;
  final detailEntered = Completer<void>();
  final offsets = <int>[];
  @override
  Future<Map<String, Object?>> periodOptions(
    TenantContext scope,
    String resource, {
    String? periodId,
    String? after,
  }) =>
      delegate.periodOptions(scope, resource, periodId: periodId, after: after);
  @override
  Future<Map<String, Object?>> fxOptions(
    TenantContext scope,
    String resource, {
    String? after,
  }) => delegate.fxOptions(scope, resource, after: after);
  @override
  Future<Map<String, Object?>> govern(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    final result = await delegate.govern(command);
    return blocked ? {...result, 'status': 'blocked'} : result;
  }

  @override
  Future<Map<String, Object?>> revalue(
    CommandEnvelope<Map<String, Object?>> command,
  ) => delegate.revalue(command);
  @override
  Future<Map<String, Object?>> fxDetail(
    TenantContext scope,
    String runId, {
    int offset = 0,
  }) async {
    offsets.add(offset);
    if (!detailEntered.isCompleted) detailEntered.complete();
    await detailPause?.future;
    return {
      'items': [
        {
          'id': 'source-$offset',
          'kind': offset == 0 ? 'AR' : 'AP',
          'open_amount': '99999999999999.123456',
          'open_base_amount': '123.456789',
        },
      ],
      'next_offset': offset == 0 ? 50 : null,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  late JentraLocalDatabase db;
  late QuotationDraftStore drafts;
  late GovernanceGateway gateway;
  late PeriodFxController controller;
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = GovernanceGateway();
    controller = PeriodFxController(
      scope: scope,
      gateway: gateway,
      drafts: drafts,
      online: true,
      capabilities: {
        'finance.view',
        'finance.period.close',
        'finance.period.reopen',
        'finance.fx.post',
      },
    );
  });
  tearDown(() async {
    controller.dispose();
    await db.close();
  });
  Future<void> ready() async {
    await controller.initialize();
    await controller.selectPeriod('period');
    controller.field(
      'reason',
      'Governed correction with immutable original source',
    );
    controller.field('as_of', '2026-09-21');
    controller.field('currency_code', 'USD');
    controller.field('exchange_rate_id', 'rate');
  }

  for (final action in [
    'hard_lock',
    'request_reopen',
    'approve_reopen',
    'reverse',
  ]) {
    test(
      '$action seals current version and immutable source before dispatch',
      () async {
        await ready();
        await controller.execute(
          action,
          sourceId: action == 'approve_reopen' ? 'request' : 'original-run',
        );
        final command = gateway.delegate.commands.single;
        expect(command.payload['action'], action);
        expect(command.expectedEntityVersion, 1);
        if (action == 'approve_reopen') {
          expect(command.payload['request_id'], 'request');
        }
        if (action == 'reverse') {
          expect(command.payload['run_id'], 'original-run');
          expect(command.payload['as_of'], '2026-09-21');
          expect(command.payload.containsKey('exchange_rate_id'), false);
        }
        expect(controller.pending, false);
        expect(
          (await drafts.load(scope, PeriodFxController.slot))?.pending,
          isNull,
        );
      },
    );
  }
  for (final action in ['approve_reopen', 'reverse']) {
    test('$action rejects absent original source before preparation', () async {
      await ready();
      await controller.execute(action);
      expect(controller.error, contains('Choose'));
      expect(gateway.delegate.commands, isEmpty);
      expect(controller.pending, false);
    });
  }
  for (final date in ['2026-02-30', '9999-01-01', '2026-08-31', '2026-09-22']) {
    test('FX date $date cannot create a sealed command', () async {
      await ready();
      controller.field('as_of', date);
      await controller.execute('post');
      expect(controller.error, isNotNull);
      expect(gateway.delegate.commands, isEmpty);
      expect(
        (await drafts.load(scope, PeriodFxController.slot))?.pending,
        isNull,
      );
    });
  }
  test(
    'changing currency clears old rate and rejects mismatched rate',
    () async {
      await ready();
      controller.field('currency_code', 'EUR');
      expect(controller.form['exchange_rate_id'], isNull);
      controller.field('exchange_rate_id', 'rate');
      await controller.execute('post');
      expect(controller.error, contains('valid closing rate'));
      expect(gateway.delegate.commands, isEmpty);
    },
  );
  test(
    'blocked close acknowledgement clears request and retains blocked guidance',
    () async {
      await ready();
      gateway.blocked = true;
      await controller.execute('hard_lock');
      expect(controller.message, contains('Close blocked'));
      expect(controller.pending, false);
      expect(
        (await drafts.load(scope, PeriodFxController.slot))?.pending,
        isNull,
      );
    },
  );
  test('definite version conflict refreshes evidence without replaying old command', () async {
    await ready();
    gateway.delegate.failure = 'VERSION_CONFLICT';
    await controller.execute('hard_lock');
    expect(controller.pending, false);
    expect(controller.local?.errorCode, 'VERSION_CONFLICT');
    gateway.delegate.version = 7;
    gateway.delegate.failure = null;
    await controller.resolveConflict();
    expect(gateway.delegate.commands.length, 1);
    expect(controller.local?.errorCode, isNull);
    await controller.execute('hard_lock');
    expect(gateway.delegate.commands.last.expectedEntityVersion, 7);
    expect(
      gateway.delegate.commands.last.commandId,
      isNot(gateway.delegate.commands.first.commandId),
    );
  });
  test(
    'FX source drilldown appends bounded offsets without losing exact values',
    () async {
      await ready();
      await controller.openDetail('run');
      expect(controller.detailNext, 50);
      await controller.moreDetail();
      expect(gateway.offsets, [0, 50]);
      expect(controller.detail.map((x) => x['id']), ['source-0', 'source-50']);
      expect(
        controller.detail.every(
          (x) => x['open_amount'] == '99999999999999.123456',
        ),
        true,
      );
      expect(controller.detailNext, isNull);
      await controller.moreDetail();
      expect(gateway.offsets, [0, 50]);
    },
  );
  test(
    'late drilldown after disconnect cannot republish source evidence',
    () async {
      await ready();
      gateway.detailPause = Completer<void>();
      final operation = controller.openDetail('run');
      await gateway.detailEntered.future;
      controller.setOnline(false);
      controller.setOnline(true);
      gateway.detailPause!.complete();
      await operation;
      expect(controller.detail, isEmpty);
      expect(controller.detailRunId, isNull);
      expect(controller.verified, false);
      await controller.refresh();
      await controller.openDetail('run');
      expect(controller.detail, isNotEmpty);
    },
  );
  test('leave persists unsealed edits but preserves an uncertain immutable envelope', () async {
    await ready();
    controller.field('reason', 'Unsealed input requires persistence');
    expect(await controller.canLeave(), true);
    expect(
      (await drafts.load(scope, PeriodFxController.slot))?.form['reason'],
      'Unsealed input requires persistence',
    );
    gateway.delegate.failure = 'UNCERTAIN_RESULT';
    await controller.execute('post');
    final command = controller.local!.pending!.envelope;
    expect(await controller.canLeave(), true);
    expect(
      (await drafts.load(
        scope,
        PeriodFxController.slot,
      ))?.pending?.envelope.commandId,
      command.commandId,
    );
    expect(gateway.delegate.commands.length, 1);
  });
}
