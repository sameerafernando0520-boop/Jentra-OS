import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/analytics_platform.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/features/analytics/pipeline_forecast_screen.dart';
import 'package:jentra_desktop/src/features/analytics/wave5_control_screen.dart';
import 'package:jentra_desktop/src/features/analytics/process_metric_controller.dart';
import 'package:jentra_desktop/src/features/analytics/process_metric_screen.dart';

Map<String, Object?> wire(String name) => (jsonDecode(
  File(
    '../../packages/jentra_platform/test/analytics/${name}_sql_snapshot.json',
  ).readAsStringSync(),
) as Map).cast();
final pipeline = wire('pipeline'),
    proposalWire = wire('proposal'),
    process = wire('process');
final scope = ProcessMetricScope(
  tenantId: (pipeline['evidence'] as Map)['tenantId'],
  legalEntityId: (pipeline['evidence'] as Map)['legalEntityId'],
  branchId: (pipeline['evidence'] as Map)['branchId'],
);
const actor = '10000000-0000-0000-0000-000000000001';

final class Keys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String k) async => values[k];
  @override
  Future<void> write(String k, String v) async {
    values[k] = v;
  }
}

final class PipelineRepo implements PipelineForecastRepository {
  int calls = 0;
  bool unknown = false, denied = false;
  Completer<FrozenPipelineForecast>? delayed;
  Map<String, Object?>? dispatched;
  @override
  Future<void> authorize(ProcessMetricScope s) async {
    if (denied) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Source access revoked.',
      );
    }
  }

  @override
  Future<void> authorizeRecovery(ProcessMetricScope s, String a) =>
      authorize(s);
  @override
  Future<FrozenPipelineForecast> get(ProcessMetricScope s, String id) async =>
      delayed?.future ??
      FrozenPipelineForecast.verify(
        pipeline,
        s,
        id,
        ProcessMetricSha256Hasher(),
      );
  @override
  Future<String> freeze(
    ProcessMetricScope s, {
    required String commandId,
    required String idempotencyKey,
    required String clientTimestamp,
    required String horizonStart,
    required String horizonEnd,
  }) async {
    calls++;
    dispatched = {
      'commandId': commandId,
      'idempotencyKey': idempotencyKey,
      'horizonStart': horizonStart,
      'horizonEnd': horizonEnd,
    };
    if (unknown) {
      throw const DomainError(
        code: 'OUTCOME_UNKNOWN',
        message: 'Review the original request.',
        retryable: true,
      );
    }
    return pipeline['id'] as String;
  }
}

final class ControlRepo implements Wave5ControlRepository {
  bool denied = false, unknown = false;
  int calls = 0;
  int billingCalls = 0;
  Map<String, Object?>? billingEnvelope;
  Completer<VerifiedHumanProposal>? delayed;
  late VerifiedHumanProposal value;
  Future<void> authority() async {
    if (denied) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Control access revoked.',
      );
    }
  }

  @override
  Future<void> authorizeProposalRecovery(ProcessMetricScope s, String a) =>
      authority();
  @override
  Future<void> authorizeSubscriptionRecovery(ProcessMetricScope s, String a) =>
      authority();
  @override
  Future<VerifiedHumanProposal> proposal(
    ProcessMetricScope s,
    String id,
  ) async {
    await authority();
    return delayed?.future ?? value;
  }

  @override
  Future<String> command(ProcessMetricScope s, Map<String, Object?> e) async {
    await authority();
    calls++;
    if (unknown) {
      throw const DomainError(
        code: 'OUTCOME_UNKNOWN',
        message: 'Original control request retained.',
        retryable: true,
      );
    }
    return value.revision.id;
  }

  @override
  Future<Map<String, Object?>> usage(String t, String m, String p) async {
    await authority();
    return {'state': 'unavailable'};
  }

  @override
  Future<Map<String, Object?>> health({String? tenant, String? grant}) async {
    await authority();
    return {
      'generatedAt': '2026-10-06T00:00:00Z',
      'probes': [
        for (final code in [
          'worker_lag_seconds',
          'retry_count',
          'dead_letter_count',
          'quota_remaining',
        ])
          {
            'code': code,
            'state': 'unknown',
            'exactValue': null,
            'observedAt': null,
          },
      ],
    };
  }

  @override
  Future<Map<String, Object?>> subscription(String t) async {
    await authority();
    return {
      'plan': 'starter',
      'status': 'active',
      'seats': 2,
      'version': '1',
      'syntheticTarget': true,
    };
  }

  @override
  Future<String> scheduleSubscription(
    ProcessMetricScope s,
    Map<String, Object?> e,
  ) async {
    await authority();
    billingCalls++;
    billingEnvelope = e;
    if (unknown) {
      throw const DomainError(
        code: 'OUTCOME_UNKNOWN',
        message: 'Original trial request retained.',
        retryable: true,
      );
    }
    return '20000000-0000-0000-0000-000000000001';
  }
}

void main() {
  setUpAll(() async {
    const base = 'packages/jentra_design_system/assets/fonts/';
    await (FontLoader(JentraTypography.sansFamily)
          ..addFont(rootBundle.load('${base}Manrope-Regular.ttf'))
          ..addFont(rootBundle.load('${base}Manrope-SemiBold.ttf')))
        .load();
    await (FontLoader(
      JentraTypography.monoFamily,
    )..addFont(rootBundle.load('${base}IBMPlexMono-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  test('subscription restart preserves original trial version and dates before retry', () async {
    final db = JentraLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = ControlRepo()..unknown = true,
        drafts = EncryptedDraftRepository(db, DraftCipher(keyStore: Keys()));
    Wave5CommandStore store() => Wave5CommandStore(
      drafts,
      repo.authorizeSubscriptionRecovery,
      namespace: 'subscription',
    );
    final payload = <String, Object?>{
      'expectedVersion': '9007199254740993',
      'plan': 'starter',
      'seats': '2',
      'trialStart': '2026-10-06T00:00:00Z',
      'trialEnd': '2026-10-07T00:00:00Z',
    };
    final first = Wave5ControlController(
      repository: repo,
      actor: actor,
      scope: scope,
      billingStore: store(),
    );
    await first.scheduleTrial(payload);
    final original = first.billingPending!;
    first.dispose();
    final second = Wave5ControlController(
      repository: repo,
      actor: actor,
      scope: scope,
      billingStore: store(),
    );
    await second.scheduleTrial({...payload, 'seats': '3'});
    expect(repo.billingCalls, 1);
    expect(second.billingPending, original);
    repo.unknown = false;
    await second.retryBilling();
    expect(repo.billingCalls, 2);
    expect(repo.billingEnvelope, original);
    expect(second.billingPending, isNull);
    expect(second.scheduledRevision, isNotNull);
    second.setOnline(false);
    expect(second.scheduledRevision, isNull);
    second.dispose();
  });
  test('restarted forecast controller keeps and retries the original uncertain envelope', () async {
    final db = JentraLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = PipelineRepo()..unknown = true,
        drafts = EncryptedDraftRepository(db, DraftCipher(keyStore: Keys()));
    Wave5CommandStore store() => Wave5CommandStore(
      drafts,
      repo.authorizeRecovery,
      namespace: 'pipeline',
    );
    final first = PipelineForecastController(
      scope: scope,
      actor: actor,
      repository: repo,
      store: store(),
    );
    await first.freeze('2026-10-01', '2026-11-01');
    final original = first.pending!;
    first.dispose();
    final second = PipelineForecastController(
      scope: scope,
      actor: actor,
      repository: repo,
      store: store(),
    );
    await second.freeze('2026-11-01', '2026-12-01');
    expect(repo.calls, 1);
    expect(second.pending, original);
    repo.unknown = false;
    await second.freeze('2026-11-01', '2026-12-01', retry: true);
    expect(repo.calls, 2);
    expect(repo.dispatched!['commandId'], original['commandId']);
    expect(repo.dispatched!['horizonStart'], '2026-10-01');
    expect(second.pending, isNull);
    expect(second.forecast, isNotNull);
    second.setOnline(false);
    expect(second.forecast, isNull);
    second.dispose();
  });
  test('late forecast read and source revocation clear evidence', () async {
    final repo = PipelineRepo(),
        c = PipelineForecastController(
          scope: scope,
          actor: actor,
          repository: repo,
        );
    repo.delayed = Completer();
    final work = c.open(pipeline['id'] as String);
    await Future<void>.delayed(Duration.zero);
    c.clear();
    repo.delayed!.complete(
      await FrozenPipelineForecast.verify(
        pipeline,
        scope,
        pipeline['id'] as String,
        ProcessMetricSha256Hasher(),
      ),
    );
    await work;
    expect(c.forecast, isNull);
    repo.delayed = null;
    await c.open(pipeline['id'] as String);
    expect(c.forecast, isNotNull);
    repo.denied = true;
    await c.open(pipeline['id'] as String);
    expect(c.forecast, isNull);
    c.dispose();
  });
  test(
    'restarted proposal controller cannot overwrite its saved original request',
    () async {
      final db = JentraLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = ControlRepo()..unknown = true;
      repo.value = await VerifiedHumanProposal.verify(proposalWire, scope);
      final drafts = EncryptedDraftRepository(
        db,
        DraftCipher(keyStore: Keys()),
      );
      Wave5CommandStore store() => Wave5CommandStore(
        drafts,
        repo.authorizeProposalRecovery,
        namespace: 'proposal',
      );
      final first = Wave5ControlController(
        repository: repo,
        actor: actor,
        scope: scope,
        store: store(),
      );
      final payload = <String, Object?>{'proposalId': repo.value.revision.id};
      await first.submit('execute', payload);
      final original = first.pending!;
      first.dispose();
      final second = Wave5ControlController(
        repository: repo,
        actor: actor,
        scope: scope,
        store: store(),
      );
      await second.submit('execute', payload);
      expect(repo.calls, 1);
      expect(second.pending, original);
      repo.unknown = false;
      await second.retryOriginal();
      expect(repo.calls, 2);
      expect(second.pending, isNull);
      expect(second.proposal, isNotNull);
      repo.denied = true;
      await second.openProposal(repo.value.revision.id);
      expect(second.proposal, isNull);
      second.dispose();
    },
  );
  test(
    'offline and disposed control readers reject late protected results',
    () async {
      final repo = ControlRepo();
      repo.value = await VerifiedHumanProposal.verify(proposalWire, scope);
      repo.delayed = Completer();
      final c = Wave5ControlController(
        repository: repo,
        actor: actor,
        scope: scope,
      );
      final work = c.openProposal(repo.value.revision.id);
      await Future<void>.delayed(Duration.zero);
      c.setOnline(false);
      repo.delayed!.complete(repo.value);
      await work;
      expect(c.proposal, isNull);
      expect(c.pending, isNull);
      c.dispose();
    },
  );
  for (final size in [
    const Size(1024, 720),
    const Size(1440, 900),
    const Size(1920, 1080),
  ]) {
    for (final dark in [false, true]) {
      for (final density in JentraDensity.values) {
        for (final workspace in ['pipeline', 'control', 'process']) {
          testWidgets(
            '$workspace ${size.width.toInt()} ${dark ? 'dark' : 'light'} ${density.name} at 200%',
            (tester) async {
              tester.view.physicalSize = size;
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              final repo = ControlRepo();
              repo.value = await VerifiedHumanProposal.verify(
                proposalWire,
                scope,
              );
              final p = PipelineForecastController(
                scope: scope,
                actor: actor,
                repository: PipelineRepo(),
              );
              await p.open(pipeline['id'] as String);
              final c = Wave5ControlController(
                repository: repo,
                actor: actor,
                scope: scope,
              )..proposal = repo.value;
              final processRepo = SupabaseProcessMetricGateway.injected(
                (name, params) async =>
                    name == 'analytics_process_authorize' ? actor : process,
              );
              final pc = ProcessMetricController(
                scope: scope,
                actorId: actor,
                repository: processRepo,
              );
              await pc.read(
                ProcessMetricFilter.fromJson({
                  for (final k in [
                    'windowStart',
                    'windowEnd',
                    'asOf',
                    'recordedThrough',
                  ])
                    k: (process['source'] as Map)[k],
                }),
              );
              final key = GlobalKey();
              final widget = workspace == 'pipeline'
                  ? PipelineForecastWorkspace(controller: p)
                  : workspace == 'control'
                  ? Wave5ControlWorkspace(
                      controller: c,
                      capabilities: {
                        'billing.read',
                        'billing.synthetic.manage',
                        'ai.proposals.view',
                        'ai.proposals.manage',
                        'ai.proposals.approve',
                        'ai.proposals.execute',
                      },
                    )
                  : ProcessMetricWorkspace(controller: pc);
              await tester.pumpWidget(
                MaterialApp(
                  theme: dark
                      ? JentraTheme.dark(density: density)
                      : JentraTheme.light(density: density),
                  home: MediaQuery(
                    data: MediaQueryData(
                      size: size,
                      textScaler: const TextScaler.linear(2),
                    ),
                    child: RepaintBoundary(
                      key: key,
                      child: Scaffold(body: widget),
                    ),
                  ),
                ),
              );
              await tester.pump();
              expect(tester.takeException(), isNull);
              final frames = Platform.environment['W5_FRAME_DIR'];
              Future<void> capture(String location) async {
                if (frames == null ||
                    size.width != 1440 ||
                    density != JentraDensity.comfortable) {
                  return;
                }
                final boundary =
                    key.currentContext!.findRenderObject()
                        as RenderRepaintBoundary;
                await tester.runAsync(() async {
                  final im = await boundary.toImage();
                  final bytes = await im.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  im.dispose();
                  await Directory(frames).create(recursive: true);
                  await File(
                    '$frames/$workspace-${dark ? 'dark' : 'light'}-$location.png',
                  ).writeAsBytes(bytes!.buffer.asUint8List());
                });
              }

              await capture('top');
              final target = workspace == 'pipeline'
                  ? find.textContaining('Complete current population')
                  : workspace == 'control'
                  ? find.text('Integrations')
                  : find.textContaining('P50:');
              await tester.scrollUntilVisible(
                target,
                300,
                scrollable: find
                    .descendant(
                      of: find.byType(ListView),
                      matching: find.byType(Scrollable),
                    )
                    .first,
              );
              expect(target, findsOneWidget);
              expect(tester.takeException(), isNull);
              await tester.pump();
              await capture('lower');
              await tester.pumpWidget(const SizedBox());
              p.dispose();
              c.dispose();
              pc.dispose();
            },
          );
        }
      }
    }
  }
}
