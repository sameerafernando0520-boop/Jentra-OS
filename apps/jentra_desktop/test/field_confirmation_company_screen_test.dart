import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/sales/field_confirmation_company_screen.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

import 'field_confirmation_company_controller_test.dart'
    show FakeConfirmationCompanyGateway, CompanyKeys, postedDelivery;

const staffScope = TenantContext(
  tenantId: 'tenant',
  legalEntityId: 'company',
  branchId: 'branch',
  actorId: 'manager',
);
const staffCaps = {'sales.field.confirmations.manage'};

class _Harness {
  _Harness({this.delivery = false});
  final bool delivery;
  TenantContext scope = staffScope;
  String? actor = 'manager';
  int revision = 1;
  Future<Set<String>> caps = Future.value(staffCaps);
  final gateway = FakeConfirmationCompanyGateway();
  final db = JentraLocalDatabase(NativeDatabase.memory());
  bool ended = false;
  late final repo = EncryptedDraftRepository(
    db,
    DraftCipher(keyStore: CompanyKeys()),
  );
  late final container = ProviderContainer(
    overrides: [
      activeTenantContextProvider.overrideWith((_) => scope),
      authenticatedActorProvider.overrideWith((_) => Stream.value(actor)),
      authSessionRevisionProvider.overrideWith((_) => Stream.value(revision)),
      businessCapabilitiesProvider.overrideWith((_) => caps),
      encryptedDraftRepositoryProvider.overrideWithValue(repo),
      fieldConfirmationCompanyGatewayProvider.overrideWithValue(gateway),
      fieldDeliveryCompanyGatewayProvider.overrideWithValue(gateway),
    ],
  );
  Future<void> pump(WidgetTester tester, {double scale = 1}) async {
    addTearDown(() => end(tester));
    container.listen(authenticatedActorProvider, (_, _) {});
    container.listen(authSessionRevisionProvider, (_, _) {});
    container.listen(businessCapabilitiesProvider, (_, _) {});
    container.read(authenticatedActorProvider);
    container.read(authSessionRevisionProvider);
    container.read(businessCapabilitiesProvider);
    await tester.pump();
    await tester.pump();
    expect(container.read(businessCapabilitiesProvider).value, staffCaps);
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
                onPressed: () => openFieldCompanyConfirmations(
                  context,
                  staffScope,
                  delivery: delivery,
                ),
                child: const Text('Open confirmations'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open confirmations'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Authorized Customer'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Authorized Customer'));
    await tester.pumpAndSettle();
  }

  Future<void> end(WidgetTester tester) async {
    if (ended) return;
    ended = true;
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await db.close();
  }

  void refresh(String kind) {
    switch (kind) {
      case 'scope':
        container.invalidate(activeTenantContextProvider);
        container.read(activeTenantContextProvider);
      case 'actor':
        container.invalidate(authenticatedActorProvider);
        container.read(authenticatedActorProvider);
      case 'session':
        container.invalidate(authSessionRevisionProvider);
        container.read(authSessionRevisionProvider);
      case 'capabilities':
        container.invalidate(businessCapabilitiesProvider);
        container.read(businessCapabilitiesProvider);
    }
  }
}

Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    220,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [360.0, 1280.0]) {
    testWidgets(
      'company delivery request at $width reviews posted quantities and a separate purpose',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final h = _Harness(delivery: true);
        h.gateway.provider = 'configured';
        h.gateway.subject = postedDelivery;
        await h.pump(tester, scale: 2);
        await scrollTo(tester, find.text('Use this contact'));
        await tester.tap(find.text('Use this contact'));
        await tester.pumpAndSettle();
        await scrollTo(tester, find.byType(Checkbox));
        await tester.tap(find.byType(Checkbox));
        await tester.pumpAndSettle();
        await scrollTo(tester, find.text('Queue delivery response request'));
        expect(h.gateway.commands, isEmpty);
        await tester.tap(find.text('Queue delivery response request'));
        await tester.pumpAndSettle();
        expect(h.gateway.commands, hasLength(1));
        expect(h.gateway.commands.single['p_action'], 'issue_delivery');
        expect(
          h.gateway.commands.single['p_payload']['delivery_version'],
          '9007199254740993',
        );
        expect(
          find.textContaining('goods receipt are not established'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await h.end(tester);
      },
    );
  }
  testWidgets('delivery recipient details clear when company scope changes', (
    tester,
  ) async {
    final h = _Harness(delivery: true);
    h.gateway.subject = postedDelivery;
    await h.pump(tester);
    await scrollTo(tester, find.text('Use this contact'));
    expect(find.textContaining('buyer@example.invalid'), findsWidgets);
    h.scope = staffScope.copyWith(branchId: 'other');
    h.refresh('scope');
    await tester.pumpAndSettle();
    expect(find.textContaining('buyer@example.invalid'), findsNothing);
    expect(h.gateway.commands, isEmpty);
    await h.end(tester);
  });
  testWidgets(
    'disabled provider cannot issue and contact edits require an explicit save',
    (tester) async {
      final h = _Harness();
      await h.pump(tester);
      expect(find.textContaining('Email service unavailable'), findsOneWidget);
      await scrollTo(tester, find.text('Use this contact'));
      await tester.tap(find.text('Use this contact'));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.text('Queue verified email request'));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Queue verified email request'),
            )
            .onPressed,
        isNull,
      );
      expect(h.gateway.commands, isEmpty);
      await scrollTo(tester, find.text('Authorize a new contact'));
      await tester.tap(find.text('Authorize a new contact'));
      await tester.pumpAndSettle();
      final name = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Contact name',
      );
      await scrollTo(tester, name);
      await tester.enterText(name, 'Unsaved buyer');
      await tester.pump();
      await tester.tap(find.text('Close').first);
      await tester.pumpAndSettle();
      expect(find.text('Discard contact changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(h.gateway.commands, isEmpty);
      await tester.tap(find.text('Close').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      await h.end(tester);
    },
  );
  for (final kind in ['scope', 'actor', 'session', 'capabilities']) {
    testWidgets(
      'contact form loses private data after $kind loss and cannot revive after restoration',
      (tester) async {
        final h = _Harness();
        await h.pump(tester);
        await scrollTo(tester, find.text('Edit contact'));
        await tester.tap(find.text('Edit contact'));
        await tester.pumpAndSettle();
        final email = find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.labelText == 'Authorized email address',
        );
        await scrollTo(tester, email);
        expect(find.text('buyer@example.invalid'), findsWidgets);
        switch (kind) {
          case 'scope':
            h.scope = staffScope.copyWith(branchId: 'other');
          case 'actor':
            h.actor = 'other';
            h.gateway.actorId = 'other';
          case 'session':
            h.revision = 2;
          case 'capabilities':
            h.caps = Future.value({});
        }
        h.refresh(kind);
        await tester.pump();
        await tester.pump();
        h.scope = staffScope;
        h.actor = 'manager';
        h.gateway.actorId = 'manager';
        h.revision = 1;
        h.caps = Future.value(staffCaps);
        h.refresh(kind);
        await tester.pumpAndSettle();
        expect(find.text('buyer@example.invalid'), findsNothing);
        expect(find.text('Save authorized contact'), findsNothing);
        expect(h.gateway.commands, isEmpty);
        await h.end(tester);
      },
    );
  }
  for (final width in [360.0, 768.0, 1280.0]) {
    testWidgets(
      'staff request review at $width supports 200 percent text and explicit queueing',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final h = _Harness();
        h.gateway.provider = 'configured';
        await h.pump(tester, scale: 2);
        await scrollTo(tester, find.text('Use this contact'));
        await tester.tap(find.text('Use this contact'));
        await tester.pumpAndSettle();
        await scrollTo(tester, find.byType(Checkbox));
        await tester.tap(find.byType(Checkbox));
        await tester.pumpAndSettle();
        await scrollTo(tester, find.text('Queue verified email request'));
        expect(tester.takeException(), isNull);
        expect(h.gateway.commands, isEmpty);
        await tester.tap(find.text('Queue verified email request'));
        await tester.pumpAndSettle();
        expect(h.gateway.commands, hasLength(1));
        expect(h.gateway.commands.single['p_action'], 'issue_order');
        expect(h.gateway.commands.single['p_payload']['contact_version'], '9');
        expect(
          find.textContaining('Email delivery is not established'),
          findsOneWidget,
        );
        expect(
          tester
              .getRect(find.textContaining('Email delivery is not established'))
              .overlaps(Rect.fromLTWH(0, 0, width, 1100)),
          isTrue,
        );
        await h.end(tester);
      },
    );
  }
  testWidgets('backgrounding the staff workspace hides contact details', (
    tester,
  ) async {
    final h = _Harness();
    await h.pump(tester);
    await scrollTo(tester, find.text('Use this contact'));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(find.text('Use this contact'), findsNothing);
    expect(h.gateway.commands, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await h.end(tester);
  });
}
