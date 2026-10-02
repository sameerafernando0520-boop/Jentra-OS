import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/features/operations/operational_metric_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    const base = 'packages/jentra_design_system/assets/fonts/';
    await (FontLoader(JentraTypography.sansFamily)
          ..addFont(rootBundle.load('${base}Manrope-Regular.ttf'))
          ..addFont(rootBundle.load('${base}Manrope-SemiBold.ttf')))
        .load();
  });
  final metrics = [
    {
      'kind': 'ap_aging',
      'as_of': '2026-09-29',
      'generated_at': '2026-09-29T12:00:00Z',
      'destination': '/procurement/payments',
      'data': {
        'buckets': [
          {
            'currency_code': 'LKR',
            'bucket': 'current',
            'amount': '90071992547409.123456',
            'item_count': '42',
          },
          {
            'currency_code': 'USD',
            'bucket': '31–60 days',
            'amount': '1000.000001',
            'item_count': '3',
          },
        ],
      },
    },
    {
      'kind': 'cash_bank',
      'as_of': '2026-09-29',
      'generated_at': '2026-09-29T12:00:00Z',
      'destination': '/finance/bank',
      'data': [
        {
          'name': 'Colombo operating bank account',
          'currency_code': 'LKR',
          'gl_value': '12345678901234.123456',
          'status': 'review_required',
          'unmatched_book': '25000.000001',
          'unmatched_bank': '20000.000000',
          'difference': '5000.000001',
        },
      ],
    },
    {
      'kind': 'close_review',
      'as_of': '2026-09-28',
      'generated_at': '2026-09-29T08:00:00Z',
      'destination': '/finance/close-review',
      'data': {
        'period_name': 'September 2026',
        'status': 'blocked',
        'as_of': '2026-09-28',
        'generated_at': '2026-09-29T08:00:00Z',
        'control_count': '12',
        'difference_count': '2',
        'blocker_count': '1',
      },
    },
  ];
  for (final (width, height) in [
    (1024.0, 720.0),
    (1440.0, 900.0),
    (1920.0, 1080.0),
    (3840.0, 2160.0),
  ]) {
    for (final dark in [false, true]) {
      for (final compact in [false, true]) {
        final mode =
            '${dark ? 'dark' : 'light'}_${compact ? 'compact' : 'comfortable'}';
        testWidgets('operational metrics ${width.toInt()} $mode 200%', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, height);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final theme = dark ? JentraTheme.dark() : JentraTheme.light();
          await tester.pumpWidget(
            MaterialApp(
              theme: theme.copyWith(
                visualDensity: compact
                    ? VisualDensity.compact
                    : VisualDensity.standard,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: RepaintBoundary(
                key: const Key('metrics-golden'),
                child: Scaffold(
                  body: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const Text('Command centre · Scoped business state'),
                      const Text(
                        'Current operational queues and dated metrics retain their own verification time and cutoff.',
                      ),
                      for (final metric in metrics)
                        OperationalMetricCard(metric: metric),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.textContaining('90071992547409.123456'), findsOneWidget);
          await expectLater(
            find.byKey(const Key('metrics-golden')),
            matchesGoldenFile(
              'goldens/operational_metrics_${width.toInt()}_${mode}_200.png',
            ),
          );
          if (width <= 1440) {
            await tester.drag(find.byType(ListView), const Offset(0, -1000));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.text('Saved close review'), findsOneWidget);
            await expectLater(
              find.byKey(const Key('metrics-golden')),
              matchesGoldenFile(
                'goldens/operational_metrics_${width.toInt()}_${mode}_200_lower.png',
              ),
            );
          }
        });
      }
    }
  }
}
