import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:jentra_desktop/src/features/manual_journal/manual_journal_controller.dart';
import 'package:jentra_desktop/src/features/period_fx/period_fx_controller.dart';

import 'manual_journal_workspace_test.dart' show JournalGateway, journal;
import 'period_fx_workspace_test.dart' show PeriodFxFake;
import 'security_review_sealing_test.dart' show PausedKeys;

const scope = TenantContext(
  tenantId: 't',
  actorId: 'a',
  legalEntityId: 'e',
  branchId: 'b',
);

class JournalReads extends JournalGateway {
  final resources = <String>[];
  Future<void> Function()? afterCommand;
  final entered = Completer<void>(), release = Completer<void>();
  bool pauseReport = false;
  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? after,
    String search = '',
    String? documentDate,
  }) async {
    resources.add(resource);
    if (pauseReport && resource == 'reports' && !entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    return super.options(
      scope,
      resource,
      after: after,
      search: search,
      documentDate: documentDate,
    );
  }

  @override
  Future<Map<String, Object?>> execute(
    String verb,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    final result = await super.execute(verb, command);
    await afterCommand?.call();
    return result;
  }
}

class FxReads implements PeriodFxGateway {
  final source = PeriodFxFake();
  final resources = <String>[];
  final entered = Completer<void>(), release = Completer<void>();
  String? pausedResource;
  Future<void> Function()? afterCommand;
  Future<void> pause(String resource) async {
    resources.add(resource);
    if (resource == pausedResource && !entered.isCompleted) {
      entered.complete();
      await release.future;
    }
  }

  @override
  Future<Map<String, Object?>> periodOptions(
    TenantContext scope,
    String resource, {
    String? periodId,
    String? after,
  }) async {
    await pause(resource);
    return source.periodOptions(
      scope,
      resource,
      periodId: periodId,
      after: after,
    );
  }

  @override
  Future<Map<String, Object?>> fxOptions(
    TenantContext scope,
    String resource, {
    String? after,
  }) async {
    await pause(resource);
    return source.fxOptions(scope, resource, after: after);
  }

  @override
  Future<Map<String, Object?>> fxDetail(
    TenantContext scope,
    String runId, {
    int offset = 0,
  }) => source.fxDetail(scope, runId, offset: offset);
  @override
  Future<Map<String, Object?>> govern(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    final result = await source.govern(command);
    await afterCommand?.call();
    return result;
  }

  @override
  Future<Map<String, Object?>> revalue(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    final result = await source.revalue(command);
    await afterCommand?.call();
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late JentraLocalDatabase db;
  late QuotationDraftStore drafts;
  late PausedKeys keys;
  late JournalReads journals;
  late FxReads fx;
  late ManualJournalController manual;
  late PeriodFxController period;
  ManualJournalController makeJournal(QuotationDraftStore store) =>
      ManualJournalController(
        scope: scope,
        gateway: journals,
        drafts: store,
        online: true,
        permissions: {
          'finance.view',
          'finance.journals.post',
          'finance.reversals.post',
          'core.files.view',
        },
      );
  void reopenJournalCipher() {
    manual.dispose();
    // The shared cipher deliberately memoizes its resolved key. Reopening the
    // encrypted fixture models a fresh process without mutating production keys.
    drafts = QuotationDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: keys)),
    );
    manual = makeJournal(drafts);
  }

  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    keys = PausedKeys();
    drafts = QuotationDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: keys)),
    );
    journals = JournalReads();
    fx = FxReads();
    manual = makeJournal(drafts);
    period = PeriodFxController(
      scope: scope,
      gateway: fx,
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
    if (!keys.release.isCompleted) keys.release.complete();
    if (!journals.release.isCompleted) journals.release.complete();
    if (!fx.release.isCompleted) fx.release.complete();
    manual.dispose();
    period.dispose();
    await db.close();
  });
  Future<void> readyFx() async {
    await period.initialize();
    await period.selectPeriod('period');
    period.field('reason', 'Original governed close');
    await period.save();
  }

  void change(dynamic controller, String kind) {
    controller.setOnline(false);
    if (kind == 'reconnect') controller.setOnline(true);
    if (kind == 'denial' && controller is ManualJournalController) {
      controller.denyReadAccess();
    }
  }

  test(
    'period reconnect refresh restores access and identical uncertain retry',
    () async {
      await readyFx();
      fx.source.failure = 'UNCERTAIN_RESULT';
      await period.execute('soft_lock');
      final original = fx.source.commands.single.toJson((x) => x);
      period.setOnline(false);
      period.setOnline(true);
      await period.refresh();
      expect(period.verified, true);
      fx.source.failure = null;
      await period.retry();
      expect(fx.source.commands, hasLength(2));
      expect(fx.source.commands.last.toJson((x) => x), original);
      expect(period.pending, false);
    },
  );

  test(
    'period fresh authorization restores encrypted inputs after read denial',
    () async {
      await readyFx();
      fx.source.failure = 'UNCERTAIN_RESULT';
      await period.execute('soft_lock');
      final original = fx.source.commands.single.toJson((x) => x);
      fx.source.readFailure = 'PERMISSION_DENIED';
      await period.refresh();
      expect(period.denied, true);
      expect(period.form, isEmpty);
      fx.source.readFailure = null;
      fx.source.failure = null;
      await period.refresh();
      expect(period.denied, false);
      expect(period.verified, true);
      expect(period.form['reason'], 'Original governed close');
      await period.retry();
      expect(fx.source.commands.last.toJson((x) => x), original);
      expect(period.pending, false);
    },
  );

  test('period pending request retains its original command family', () async {
    await readyFx();
    fx.source.failure = 'UNCERTAIN_RESULT';
    await period.execute('soft_lock');
    final original = fx.source.commands.single.toJson((x) => x);
    fx.source.failure = null;
    await period.execute('post');
    expect(fx.source.commands.last.toJson((x) => x), original);
    expect(fx.source.state, 'soft_locked');
    expect(period.period?['state'], 'soft_locked');
    expect(period.pending, false);
  });

  for (final kind in ['disconnect', 'reconnect', 'denial']) {
    test(
      'journal obsolete encrypted initialization cannot publish after $kind',
      () async {
        await drafts.save(
          scope,
          ManualJournalController.slot,
          ManualJournalController.recoveryForm(journal()),
          expectedVersion: 1,
        );
        reopenJournalCipher();
        keys.armed = true;
        final work = manual.initialize();
        await keys.entered.future.timeout(const Duration(seconds: 5));
        change(manual, kind);
        keys.release.complete();
        await work;
        expect(manual.form, isNull);
        expect(manual.local, isNull);
        expect(journals.resources, isEmpty);
        expect(
          await drafts.load(scope, ManualJournalController.slot),
          isNotNull,
        );
      },
    );
    test(
      'journal obsolete reversal cannot republish original values after $kind',
      () async {
        await manual.initialize();
        manual.form = journal(status: 'posted', version: 4);
        await manual.saveLocal();
        reopenJournalCipher();
        manual.form = journal(status: 'posted', version: 4);
        keys.armed = true;
        final work = manual.reverse();
        await keys.entered.future.timeout(const Duration(seconds: 5));
        change(manual, kind);
        keys.release.complete();
        await work;
        expect(manual.form, isNull);
        expect(journals.commands, isEmpty);
        expect(await drafts.load(scope, ManualJournalController.slot), isNull);
      },
    );
  }

  for (final kind in ['disconnect', 'reconnect']) {
    test(
      'period obsolete initialize stops chained reads after $kind',
      () async {
        fx.pausedResource = 'rates';
        final work = period.initialize();
        await fx.entered.future.timeout(const Duration(seconds: 5));
        change(period, kind);
        fx.release.complete();
        await work;
        expect(fx.resources, ['periods', 'rates']);
        expect(period.pages, isEmpty);
        expect(period.verified, false);
      },
    );
    test(
      'period obsolete conflict review preserves stored conflict after $kind',
      () async {
        await readyFx();
        fx.source.failure = 'VERSION_CONFLICT';
        await period.execute('soft_lock');
        expect(period.local?.errorCode, 'VERSION_CONFLICT');
        fx.pausedResource = 'periods';
        final work = period.resolveConflict();
        await fx.entered.future.timeout(const Duration(seconds: 5));
        change(period, kind);
        fx.release.complete();
        await work;
        final retained = await drafts.load(scope, PeriodFxController.slot);
        expect(retained?.errorCode, 'VERSION_CONFLICT');
        expect(retained?.expectedVersion, 1);
        expect(period.message, isNull);
      },
    );
  }

  test(
    'journal stale report cannot start a follow-up attachment read',
    () async {
      await manual.initialize();
      manual.form = {
        ...journal(),
        'attachment_ids': ['attachment'],
      };
      await manual.saveLocal();
      manual.denyReadAccess();
      journals.resources.clear();
      journals.pauseReport = true;
      final work = manual.refresh();
      await journals.entered.future.timeout(const Duration(seconds: 5));
      manual.setOnline(false);
      manual.setOnline(true);
      journals.release.complete();
      await work;
      expect(journals.resources, ['reports']);
      expect(manual.accessDenied, true);
      expect(manual.items, isEmpty);
    },
  );

  test('journal known confirmation retains secure-storage guidance on optional save failure', () async {
    await manual.initialize();
    manual.form = journal(status: 'approved', version: 3);
    journals.afterCommand = () async {
      await db.customStatement('CREATE TEMP TABLE writes (n INTEGER NOT NULL)');
      await db.customStatement('INSERT INTO writes VALUES (0)');
      await db.customStatement(
        '''CREATE TEMP TRIGGER fail_optional_update
        BEFORE UPDATE ON encrypted_drafts WHEN (SELECT n FROM writes) >= 1
        BEGIN SELECT RAISE(ABORT, 'synthetic optional local write failure'); END''',
      );
      await db.customStatement('''CREATE TEMP TRIGGER count_confirmation
        AFTER UPDATE ON encrypted_drafts
        BEGIN UPDATE writes SET n = n + 1; END''');
    };
    await manual.act('post');
    expect(journals.commands, hasLength(1));
    expect(manual.message, contains('confirmed'));
    expect(manual.error, contains('LOCAL_STORAGE_FULL'));
    expect(manual.error, contains('Keep this editor open'));
    final stored = await drafts.load(scope, ManualJournalController.slot);
    expect(stored?.pending, isNull);
    expect(stored?.form['status'], 'posted');
    expect(stored?.form['version'], 4);
  });

  test('period known confirmation retains secure-storage guidance on optional save failure', () async {
    await readyFx();
    fx.afterCommand = () => db.customStatement(
      '''CREATE TEMP TRIGGER fail_optional_insert
      BEFORE INSERT ON encrypted_drafts
      BEGIN SELECT RAISE(ABORT, 'synthetic optional local write failure'); END''',
    );
    await period.execute('soft_lock');
    expect(fx.source.commands, hasLength(1));
    expect(period.message, contains('confirmed'));
    expect(period.error, contains('LOCAL_STORAGE_FULL'));
    expect(period.error, contains('Keep this editor open'));
    expect(await drafts.load(scope, PeriodFxController.slot), isNull);
    expect(period.pending, false);
  });
}
