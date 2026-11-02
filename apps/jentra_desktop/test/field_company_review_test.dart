import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/sales/field_company_review.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_platform/jentra_field_sales_platform.dart';

const _scope = TenantContext(
  tenantId: 'synthetic-tenant',
  legalEntityId: 'synthetic-company',
  branchId: 'synthetic-branch',
  actorId: 'company-approver',
);
const _capabilities = {'sales.field.discounts.decide', 'sales.orders.manage'};
final _request = <String, dynamic>{
  'id': 'synthetic-request',
  'version': '1',
  'source_digest': 'a' * 64,
  'input': {'discount_percent': '5.00'},
  'preview': {
    'currency_code': 'LKR',
    'pricing': {'grand_total': '1250.000000'},
  },
};

final class _CompanyGateway implements FieldSalesCompanyGateway {
  @override
  String? actorId = _scope.actorId;
  final decisions = <FieldSalesJson>[];

  @override
  Future<List<FieldSalesJson>> subjects(FieldSalesScope scope) async => [];

  @override
  Future<FieldSalesJson> receipt(FieldSalesScope scope, String key) async => {
    'state': 'not_found',
  };

  @override
  Future<FieldSalesJson> decide(FieldSalesJson params) async {
    decisions.add(params);
    throw StateError('The reason dialog must not dispatch a decision.');
  }
}

final class _Harness {
  TenantContext currentScope = _scope;
  String? actor = _scope.actorId;
  int revision = 1;
  Future<Set<String>> capabilityResult = Future.value(_capabilities);
  final gateway = _CompanyGateway();
  late final ProviderContainer container = ProviderContainer(
    overrides: [
      activeTenantContextProvider.overrideWith((_) => currentScope),
      authenticatedActorProvider.overrideWith((_) => Stream.value(actor)),
      authSessionRevisionProvider.overrideWith((_) => Stream.value(revision)),
      businessCapabilitiesProvider.overrideWith((_) => capabilityResult),
      fieldSalesCompanyGatewayProvider.overrideWithValue(gateway),
    ],
  );
  String? result;

  Future<void> pump(WidgetTester tester, {double scale = 1}) async {
    container.listen(authenticatedActorProvider, (_, _) {});
    container.listen(authSessionRevisionProvider, (_, _) {});
    container.listen(businessCapabilitiesProvider, (_, _) {});
    container.read(authenticatedActorProvider);
    container.read(authSessionRevisionProvider);
    container.read(businessCapabilitiesProvider);
    await tester.pump();
    await tester.pump();
    expect(container.read(authenticatedActorProvider).value, actor);
    expect(container.read(authSessionRevisionProvider).value, revision);
    expect(container.read(businessCapabilitiesProvider).value, _capabilities);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  result = await showDialog<String>(
                    context: context,
                    builder: (_) => FieldCompanyDecisionDialog(
                      scope: _scope,
                      actor: _scope.actorId,
                      sessionRevision: 1,
                      capabilities: _capabilities,
                      gateway: gateway,
                      row: _request,
                      decision: 'approve',
                    ),
                  );
                },
                child: const Text('Open company decision'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open company decision'));
    await tester.pumpAndSettle();
  }

  void invalidateScope() {
    container.invalidate(activeTenantContextProvider);
    container.read(activeTenantContextProvider);
  }

  void invalidateActor() {
    container.invalidate(authenticatedActorProvider);
    container.read(authenticatedActorProvider);
  }

  void invalidateRevision() {
    container.invalidate(authSessionRevisionProvider);
    container.read(authSessionRevisionProvider);
  }

  void invalidateCapabilities() {
    container.invalidate(businessCapabilitiesProvider);
    container.read(businessCapabilitiesProvider);
  }
}

void main() {
  testWidgets(
    'company reason requires an explicit reason and never dispatches',
    (tester) async {
      final h = _Harness();
      addTearDown(h.container.dispose);
      await h.pump(tester);
      expect(find.text('Requested total: LKR 1250.000000'), findsOneWidget);
      expect(h.gateway.decisions, isEmpty);
      await tester.tap(find.text('Confirm company decision'));
      await tester.pumpAndSettle();
      expect(
        find.text('Add a company decision reason of up to 500 characters.'),
        findsOneWidget,
      );
      expect(h.result, isNull);
      await tester.enterText(
        find.byType(TextFormField),
        '  Exact company reason  ',
      );
      await tester.tap(find.text('Confirm company decision'));
      await tester.pumpAndSettle();
      expect(h.result, 'Exact company reason');
      expect(h.gateway.decisions, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final change in ['scope', 'actor', 'session', 'capabilities']) {
    testWidgets('nested company route hides private terms after $change loss', (
      tester,
    ) async {
      final h = _Harness();
      addTearDown(h.container.dispose);
      await h.pump(tester);
      await tester.enterText(
        find.byType(TextFormField),
        'Private company reason',
      );
      switch (change) {
        case 'scope':
          h.currentScope = _scope.copyWith(branchId: 'other-branch');
          h.invalidateScope();
          h.currentScope = _scope;
          h.invalidateScope();
        case 'actor':
          h.actor = 'other-actor';
          h.gateway.actorId = h.actor;
          h.invalidateActor();
          await tester.pump();
          h.actor = _scope.actorId;
          h.gateway.actorId = h.actor;
          h.invalidateActor();
        case 'session':
          h.revision = 2;
          h.invalidateRevision();
          await tester.pump();
          h.revision = 1;
          h.invalidateRevision();
        case 'capabilities':
          h.capabilityResult = Future.value({'sales.orders.manage'});
          h.invalidateCapabilities();
          await tester.pump();
          h.capabilityResult = Future.value(_capabilities);
          h.invalidateCapabilities();
      }
      await tester.pumpAndSettle();
      expect(find.text('Company access changed'), findsOneWidget);
      expect(find.text('Requested total: LKR 1250.000000'), findsNothing);
      expect(find.text('Private company reason'), findsNothing);
      expect(find.text('Confirm company decision'), findsNothing);
      expect(h.gateway.decisions, isEmpty);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(h.result, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'pending capabilities hide terms and restoration cannot revive them',
    (tester) async {
      final h = _Harness();
      addTearDown(h.container.dispose);
      await h.pump(tester);
      final pending = Completer<Set<String>>();
      h.capabilityResult = pending.future;
      h.invalidateCapabilities();
      await tester.pump();
      expect(find.text('Requested total: LKR 1250.000000'), findsNothing);
      pending.complete(_capabilities);
      await tester.pumpAndSettle();
      expect(find.text('Company access changed'), findsOneWidget);
      expect(find.text('Confirm company decision'), findsNothing);
      expect(h.gateway.decisions, isEmpty);
    },
  );

  for (final width in [360.0, 768.0, 1280.0]) {
    testWidgets('company terms are usable at $width with 200 percent text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = _Harness();
      addTearDown(h.container.dispose);
      await h.pump(tester, scale: 2);
      expect(find.text('Requested total: LKR 1250.000000'), findsOneWidget);
      await tester.ensureVisible(find.byType(TextFormField));
      await tester.enterText(
        find.byType(TextFormField),
        'Reviewed exact terms',
      );
      await tester.ensureVisible(find.text('Confirm company decision'));
      await tester.tap(find.text('Confirm company decision'));
      await tester.pumpAndSettle();
      expect(h.result, 'Reviewed exact terms');
      expect(h.gateway.decisions, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
