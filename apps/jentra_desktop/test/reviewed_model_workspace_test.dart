import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/jentra_domain.dart' show DomainError;
import 'package:jentra_platform/analytics_platform.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_desktop/src/features/analytics/reviewed_model_section.dart';
import 'package:jentra_desktop/src/features/analytics/wave5_control_screen.dart';

const actor = '10000000-0000-0000-0000-000000000001';
const source = '10000000-0000-0000-0000-000000000004';
final scope = ProcessMetricScope(
  tenantId: '10000000-0000-0000-0000-000000000002',
  legalEntityId: '10000000-0000-0000-0000-000000000003',
);
final parameters = <String, Object?>{
  'sourceId': source,
  'maxTokens': '2000',
  'periodStart': '2026-10-01T00:00:00Z',
  'periodEnd': '2026-11-01T00:00:00Z',
};
final output = VerifiedModelSuggestion.verify(
  {
    'commandCode': 'analytics.freeze_pipeline.v1',
    'sourceId': source,
    'sourceHash': 'a' * 64,
    'horizonStart': '2026-10-09',
    'horizonEnd': '2026-10-31',
  },
  {
    'sourceId': source,
    'sourceHash': 'a' * 64,
    'horizonStart': '2026-10-09',
    'horizonEnd': '2026-10-31',
  },
);

final class Keys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

final class Repo implements ReviewedModelRepository {
  bool denied = false, unknown = true;
  int calls = 0;
  final originals = <Map<String, Object?>>[];
  Completer<VerifiedModelSuggestion>? delayed;
  @override
  Future<void> authorizeRecovery(ProcessMetricScope s, String a) async {
    if (denied) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Source access revoked.',
      );
    }
  }

  @override
  Future<VerifiedModelSuggestion> suggestion(
    ProcessMetricScope s,
    String a,
    Map<String, Object?> e,
  ) async {
    await authorizeRecovery(s, a);
    calls++;
    originals.add(e);
    if (delayed != null) return delayed!.future;
    if (unknown) {
      throw const DomainError(
        code: 'MODEL_OUTCOME_REQUIRES_REVIEW',
        message: 'Unknown outcome retained.',
      );
    }
    return output;
  }
}

void main() {
  setUpAll(() async {
    const fonts = 'packages/jentra_design_system/assets/fonts/';
    await (FontLoader(JentraTypography.sansFamily)
          ..addFont(rootBundle.load('${fonts}Manrope-Regular.ttf'))
          ..addFont(rootBundle.load('${fonts}Manrope-SemiBold.ttf')))
        .load();
    await (FontLoader(
      JentraTypography.monoFamily,
    )..addFont(rootBundle.load('${fonts}IBMPlexMono-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  late JentraLocalDatabase db;
  late Repo repo;
  late EncryptedDraftRepository drafts;
  Wave5CommandStore store() =>
      Wave5CommandStore(drafts, repo.authorizeRecovery, namespace: 'model');
  ReviewedModelController controller({
    String a = actor,
    ProcessMetricScope? s,
  }) => ReviewedModelController(
    repository: repo,
    actor: a,
    scope: s ?? scope,
    store: store(),
  );
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    repo = Repo();
    drafts = EncryptedDraftRepository(db, DraftCipher(keyStore: Keys()));
  });
  tearDown(() async {
    await db.close();
  });

  test('unknown outcome survives controller restart and prevents a replacement invocation', () async {
    final first = controller();
    await first.request(parameters);
    final original = first.pending!;
    first.dispose();
    final second = controller();
    await second.request({...parameters, 'maxTokens': '1'});
    expect(repo.calls, 1);
    expect(second.pending, original);
    repo.unknown = false;
    await second.reopenOriginal();
    expect(repo.originals, [original, original]);
    expect(second.suggestion, output);
    expect(second.pending, original);
    await second.finishReview();
    expect(second.pending, isNull);
    expect(await store().restore(scope, actor), isNull);
    second.dispose();
  });
  test('unknown requests cannot be discarded through finish review', () async {
    final c = controller();
    await c.request(parameters);
    final original = c.pending;
    await c.finishReview();
    expect(c.pending, original);
    expect(await store().restore(scope, actor), original);
    expect(repo.calls, 1);
    c.dispose();
  });
  test('ciphertext excludes plaintext source fields and keeps only bounded request data', () async {
    final c = controller();
    await c.request(parameters);
    final rows = await db.select(db.encryptedDrafts).get();
    expect(rows, hasLength(1));
    final bytes = String.fromCharCodes(rows.single.encryptedPayload);
    expect(bytes.contains(source), false);
    expect(bytes.contains('periodStart'), false);
    expect(rows.single.entityType, 'wave5_model_command');
    expect((await store().restore(scope, actor))!['payload'], parameters);
    c.dispose();
  });
  test(
    'foreign actor and branch cannot recover the original saved invocation',
    () async {
      final c = controller();
      await c.request(parameters);
      final other = controller(a: source);
      await other.restore();
      expect(other.pending, isNull);
      final branch = controller(
        s: ProcessMetricScope(
          tenantId: scope.tenantId,
          legalEntityId: scope.legalEntityId,
          branchId: source,
        ),
      );
      await branch.restore();
      expect(branch.pending, isNull);
      expect(repo.calls, 1);
      c.dispose();
      other.dispose();
      branch.dispose();
    },
  );
  test(
    'revocation blocks restore/reopen and clears protected evidence',
    () async {
      repo.unknown = false;
      final c = controller();
      await c.request(parameters);
      expect(c.suggestion, output);
      repo.denied = true;
      await c.restore();
      expect(c.pending, isNull);
      expect(c.suggestion, isNull);
      expect(c.error, 'Source access revoked.');
      await c.reopenOriginal();
      expect(repo.calls, 1);
      expect(await db.select(db.encryptedDrafts).get(), hasLength(1));
      c.dispose();
    },
  );
  test('offline transition discards late output and preserves encrypted original without resending', () async {
    repo.delayed = Completer<VerifiedModelSuggestion>();
    final c = controller();
    final future = c.request(parameters);
    while (repo.calls == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    c.setOnline(false);
    repo.delayed!.complete(output);
    await future;
    expect(c.pending, isNull);
    expect(c.suggestion, isNull);
    c.setOnline(true);
    await c.restore();
    expect(c.pending, isNotNull);
    expect(repo.calls, 1);
    c.dispose();
  });
  test('invalid token reservation is rejected before encryption or worker mutation', () async {
    final c = controller();
    await c.request({...parameters, 'maxTokens': '2001'});
    expect(repo.calls, 0);
    expect(c.pending, isNull);
    expect(await db.select(db.encryptedDrafts).get(), isEmpty);
    c.dispose();
  });

  testWidgets(
    'Control source transfer is explicit and performs no human proposal command',
    (tester) async {
      repo.unknown = false;
      final c = controller();
      await tester.runAsync(() => c.request(parameters));
      addTearDown(c.dispose);
      var commands = 0;
      final human = Wave5ControlController(
        repository: SupabaseWave5ControlGateway.injected((_, _) async {
          commands++;
          return actor;
        }),
        actor: actor,
        scope: scope,
      );
      addTearDown(human.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Wave5ControlWorkspace(
              controller: human,
              modelController: c,
              capabilities: const {'ai.proposals.view', 'ai.proposals.manage'},
            ),
          ),
        ),
      );
      final choose = find.text('Use source for a human proposal');
      await tester.pumpAndSettle();
      await tester.ensureVisible(choose);
      await tester.pumpAndSettle();
      await tester.tap(choose);
      await tester.pump();
      final input = find.widgetWithText(TextField, 'Frozen source forecast ID');
      await tester.ensureVisible(input);
      await tester.pump();
      expect(tester.widget<TextField>(input).controller!.text, source);
      expect(commands, 0);
      expect(repo.calls, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final size in [
    const Size(1024, 720),
    const Size(1440, 900),
    const Size(1920, 1080),
  ]) {
    for (final brightness in Brightness.values) {
      for (final density in JentraDensity.values) {
        final tag =
            '${size.width.toInt()}-${size.height.toInt()}-${brightness.name}-${density.name}';
        testWidgets(
          'model fresh render $tag at 200% text, reviewed source selection does not dispatch',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            repo.unknown = false;
            final c = controller();
            await tester.runAsync(() => c.request(parameters));
            addTearDown(c.dispose);
            String? chosen;
            final key = GlobalKey();
            await tester.pumpWidget(
              MaterialApp(
                theme: brightness == Brightness.dark
                    ? JentraTheme.dark(density: density)
                    : JentraTheme.light(density: density),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: size,
                    textScaler: const TextScaler.linear(2),
                  ),
                  child: RepaintBoundary(
                    key: key,
                    child: Scaffold(
                      body: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: ReviewedModelWorkspace(
                            controller: c,
                            capabilities: const {
                              'ai.proposals.view',
                              'ai.proposals.manage',
                            },
                            onHumanSource: (value) => chosen = value,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(
              tester
                  .widget<TextField>(
                    find.widgetWithText(TextField, 'Model source forecast ID'),
                  )
                  .controller!
                  .text,
              source,
            );
            expect(
              tester
                  .widget<TextField>(
                    find.widgetWithText(
                      TextField,
                      'Model quota period start UTC',
                    ),
                  )
                  .controller!
                  .text,
              parameters['periodStart'],
            );
            Future<void> capture(String position) async {
              final dir = Platform.environment['W5_MODEL_FRAME_DIR'];
              if (dir == null) return;
              await tester.runAsync(() async {
                final image =
                    await (key.currentContext!.findRenderObject()!
                            as RenderRepaintBoundary)
                        .toImage();
                final png = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await Directory(dir).create(recursive: true);
                await File('$dir/model-$tag-$position.png')
                    .writeAsBytes(png!.buffer.asUint8List());
                image.dispose();
              });
            }

            await capture('top');
            final choose = find.text('Use source for a human proposal');
            await tester.ensureVisible(choose);
            await tester.pumpAndSettle();
            await capture('review');
            await tester.tap(choose);
            await tester.pump();
            expect(chosen, source);
            expect(repo.calls, 1);
            expect(c.pending, isNotNull);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
}
