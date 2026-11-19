import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/operations/operational_dashboard.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';

void main() {
  final snapshot = {
    'generated_at': '2026-11-06T08:30:00Z',
    'metrics': [
      {
        'kind': 'pipeline',
        'as_of': '2026-11-06',
        'generated_at': '2026-11-06T08:30:00Z',
        'destination': '/crm',
        'data': {
          'currency_totals': [
            for (final currency in ['LKR', 'USD', 'AUD', 'EUR', 'SGD'])
              {
                'currency_code': currency,
                'expected_value': '1234.123456',
                'weighted_value': '876.000001',
              },
          ],
        },
      },
      {
        'kind': 'cash_bank',
        'as_of': '2026-11-06',
        'generated_at': '2026-11-06T08:30:00Z',
        'destination': '/finance/bank',
        'data': [],
      },
      {
        'kind': 'periods',
        'as_of': '2026-11-06',
        'generated_at': '2026-11-06T08:30:00Z',
        'destination': '/finance/periods',
        'data': [],
      },
    ],
    'cards': [
      {'kind': 'sales_order', 'count': 3},
    ],
  };

  for (final (width, textScale) in [
    (1232.0, 1.0),
    (740.0, 1.0),
    (390.0, 2.0),
  ]) {
    testWidgets(
      'Command centre adapts at width $width and text scale $textScale',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              activeTenantContextProvider.overrideWithValue(
                const TenantContext(
                  tenantId: 't',
                  actorId: 'u',
                  legalEntityId: 'c',
                  branchId: 'b',
                ),
              ),
              connectivityStateProvider.overrideWithValue(
                const AsyncData(ConnectivityState.online),
              ),
              operationalDashboardProvider.overrideWith(
                (ref) async => snapshot,
              ),
            ],
            child: MaterialApp(
              theme: textScale == 2 ? JentraTheme.dark() : JentraTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
              home: const Scaffold(body: OperationalDashboard()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Pipeline and forecast'),
          200,
        );
        await tester.pumpAndSettle();
        final pipeline = tester.getTopLeft(find.text('Pipeline and forecast'));
        final bank = tester.getTopLeft(
          find.text('Cash and bank reconciliation'),
        );
        final periods = tester.getTopLeft(find.text('Period status'));
        if (width >= 1008) {
          expect(bank.dx, greaterThan(pipeline.dx));
          expect(periods.dx, greaterThan(bank.dx));
          expect(periods.dy, closeTo(pipeline.dy, 1));
        } else if (width >= 650) {
          expect(bank.dx, greaterThan(pipeline.dx));
          expect(periods.dy, greaterThan(bank.dy));
        } else {
          expect(bank.dx, closeTo(pipeline.dx, 1));
          expect(bank.dy, greaterThan(pipeline.dy));
        }
        expect(find.textContaining('SGD · Expected'), findsNothing);
        final more = find.text('Show more details (1)');
        await tester.scrollUntilVisible(more.hitTestable(), 250);
        await tester.tap(more.hitTestable());
        await tester.pumpAndSettle();
        expect(
          find.textContaining('SGD · Expected 1234.123456'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
