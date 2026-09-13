import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/tenant/stock_opening_access.dart';
import 'package:jentra_platform/jentra_platform.dart';

class _Access implements StockOpeningAccessGateway {
  BusinessScopeState scope = _scope;
  final invites = <Map<String, String>>[];
  final accepts = <String>[];
  bool fail = false;
  StockOpeningAccessFailure? rejection;
  Completer<void>? hold;
  @override
  Future<List<Map<String, Object?>>> pending() async => [
    {
      'id': 'invite',
      'tenant_name': 'Jentra Acceptance Lab',
      'legal_entity_name': 'Jentra Acceptance Trading',
      'branch_name': 'Head Office',
    },
  ];
  @override
  Future<Map<String, Object?>> invite({
    required String tenantId,
    required String legalEntityId,
    required String branchId,
    required String email,
    required String idempotencyKey,
  }) async {
    invites.add({
      'tenant': tenantId,
      'entity': legalEntityId,
      'branch': branchId,
      'email': email,
      'key': idempotencyKey,
    });
    await hold?.future;
    if (rejection != null) throw rejection!;
    if (fail) throw StateError('timeout');
    return {
      'request_id': 'receipt',
      'entity': {'id': 'invite', 'role_id': 'role-uuid'},
    };
  }

  @override
  Future<Map<String, Object?>> accept({
    required String invitationId,
    required String idempotencyKey,
  }) async {
    accepts.add('$invitationId:$idempotencyKey');
    if (fail) throw StateError('timeout');
    return {
      'request_id': 'receipt',
      'entity': {'id': 'member'},
    };
  }
}

const _scope = BusinessScopeState(
  tenants: [
    TenantSummary(
      id: 'tenant',
      name: 'Jentra Acceptance Lab',
      slug: 'lab',
      status: 'active',
      membershipStatus: 'active',
    ),
  ],
  legalEntities: [
    LegalEntitySummary(
      id: 'entity',
      tenantId: 'tenant',
      name: 'Jentra Acceptance Trading',
      code: 'JAT',
      currencyCode: 'LKR',
      timezone: 'Asia/Colombo',
      status: 'active',
    ),
  ],
  branches: [
    BranchSummary(
      id: 'branch',
      tenantId: 'tenant',
      legalEntityId: 'entity',
      name: 'Head Office',
      code: 'HQ',
      timezone: 'Asia/Colombo',
      status: 'active',
    ),
  ],
  tenantId: 'tenant',
  legalEntityId: 'entity',
  branchId: 'branch',
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _Access access, {
  Widget child = const StockOpeningInviteButton(),
  bool allowed = true,
  double scale = 1,
}) async {
  await tester.binding.setSurfaceSize(const Size(1024, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        stockOpeningAccessGatewayProvider.overrideWithValue(access),
        authenticatedActorProvider.overrideWith((ref) => Stream.value('owner')),
        businessScopeProvider.overrideWithBuild(
          (ref, notifier) async => access.scope,
        ),
        businessCapabilitiesProvider.overrideWith(
          (ref) async => allowed
              ? {'core.roles.manage', 'core.members.invite'}
              : <String>{},
        ),
      ],
      child: MaterialApp(
        theme: JentraTheme.light(),
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
}

void main() {
  setUpAll(() async {
    const fonts = 'packages/jentra_design_system/assets/fonts/';
    await (FontLoader(JentraTypography.sansFamily)
          ..addFont(rootBundle.load('${fonts}Manrope-Regular.ttf'))
          ..addFont(rootBundle.load('${fonts}Manrope-Medium.ttf'))
          ..addFont(rootBundle.load('${fonts}Manrope-SemiBold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets(
    'invitation preserves scope, locks retry fields and returns matrix role',
    (tester) async {
      final access = _Access()..fail = true;
      await _pump(tester, access);
      await tester.tap(find.byTooltip('Invite stock opening approver'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'test@lh.com');
      await tester.tap(find.text('Create invitation'));
      await tester.pumpAndSettle();
      expect(access.invites.single['branch'], 'branch');
      expect(access.invites.single['email'], 'test@lh.com');
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
        isNot(false),
      );
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      access.fail = false;
      await tester.tap(find.text('Retry invitation'));
      await tester.pumpAndSettle();
      expect(access.invites[0], access.invites[1]);
      expect(find.text('role-uuid'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('server rejection is visible and retry keeps its identity', (
    tester,
  ) async {
    final access = _Access()
      ..rejection = const StockOpeningAccessFailure(
        'Complete MFA for your owner session, then retry this request.',
      );
    await _pump(tester, access);
    await tester.tap(find.byTooltip('Invite stock opening approver'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'test@lh.com');
    await tester.tap(find.text('Create invitation'));
    await tester.pumpAndSettle();
    expect(find.text(access.rejection!.message), findsOneWidget);
    access.rejection = null;
    await tester.tap(find.text('Retry invitation'));
    await tester.pumpAndSettle();
    expect(access.invites[0], access.invites[1]);
    expect(find.text('role-uuid'), findsOneWidget);
  });
  testWidgets('missing role-management authority hides invitation action', (
    tester,
  ) async {
    await _pump(tester, _Access(), allowed: false);
    expect(find.byTooltip('Invite stock opening approver'), findsNothing);
  });
  testWidgets('scope changes stop the open form from submitting', (
    tester,
  ) async {
    final access = _Access();
    final c = await _pump(tester, access);
    await tester.tap(find.byTooltip('Invite stock opening approver'));
    await tester.pumpAndSettle();
    access.scope = BusinessScopeState(
      tenants: _scope.tenants,
      legalEntities: _scope.legalEntities,
      branches: _scope.branches,
      tenantId: 'tenant',
      legalEntityId: 'entity',
      branchId: null,
    );
    c.invalidate(businessScopeProvider);
    await tester.pumpAndSettle();
    expect(find.text('Create invitation'), findsNothing);
    expect(access.invites, isEmpty);
  });
  testWidgets('duplicate clicks send only one invitation', (tester) async {
    final access = _Access()..hold = Completer<void>();
    await _pump(tester, access);
    await tester.tap(find.byTooltip('Invite stock opening approver'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'test@lh.com');
    await tester.tap(find.text('Create invitation'));
    await tester.pump();
    expect(access.invites, hasLength(1));
    expect(
      tester
          .widget<JentraPrimaryButton>(find.byType(JentraPrimaryButton))
          .onPressed,
      isNull,
    );
    access.hold!.complete();
    await tester.pumpAndSettle();
  });
  testWidgets('recipient inbox retries identical acceptance without a tenant', (
    tester,
  ) async {
    final access = _Access()..fail = true;
    await _pump(tester, access, child: const StockOpeningInvitationInbox());
    await tester.tap(find.text('Accept stock opening invitation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept stock opening invitation'));
    await tester.pumpAndSettle();
    expect(access.accepts, hasLength(2));
    expect(access.accepts[0], access.accepts[1]);
  });
  testWidgets('invitation is readable at 200 percent text scale', (
    tester,
  ) async {
    await _pump(tester, _Access(), scale: 2);
    await tester.tap(find.byTooltip('Invite stock opening approver'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/stock_opening_invite_text200.png'),
    );
    expect(tester.takeException(), isNull);
  });
}
