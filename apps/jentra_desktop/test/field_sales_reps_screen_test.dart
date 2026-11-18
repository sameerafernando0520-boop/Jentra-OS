import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/sales/field_company_review.dart';
import 'package:jentra_desktop/src/features/sales/field_sales_reps_screen.dart';
import 'package:jentra_desktop/src/features/sales/field_sales_visits_screen.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_field_sales_platform.dart';

import 'field_confirmation_company_controller_test.dart' show CompanyKeys;

const _scope = TenantContext(
  tenantId: 'tenant',
  legalEntityId: 'company',
  branchId: 'branch',
  actorId: 'manager',
);
const _linkedRep = 'a1b2c3d4-0000-4000-8000-00000000aaaa';
const _unlinkedRep = 'a1b2c3d4-0000-4000-8000-000000009f3a';

FieldSalesJson _row(String userId, String label, {bool linked = true}) => {
  'user_id': userId,
  'label': label,
  'linked': linked,
  'active_customer_count': '3',
  'submitted_count': '4',
  'pending_count': '1',
  'approved_count': '2',
  'rejected_count': '1',
  'approved_total': linked ? '100.350000' : '0.000000',
};

final class _Gateway implements FieldSalesCompanyGateway {
  @override
  String? actorId = _scope.actorId;
  final repCalls = <(String, String)>[];
  bool failReps = false;
  List<FieldSalesJson> subjectRows = [];

  @override
  Future<FieldSalesRepList> reps(
    FieldSalesScope scope, {
    required DateTime from,
    required DateTime to,
  }) async {
    expect(scope.key, 'tenant.company.branch');
    repCalls.add((fieldSalesDate(from), fieldSalesDate(to)));
    if (failReps) {
      throw const FieldSalesFailure('SERVER_REJECTED', 'Rep names failed.');
    }
    return FieldSalesRepList.fromJson({
      'items': [
        _row(_linkedRep, 'Asha Perera'),
        _row(_unlinkedRep, 'Unlinked member ····9f3a', linked: false),
      ],
      'currency_code': 'LKR',
      'from': fieldSalesDate(from),
      'to': fieldSalesDate(to),
    });
  }

  final visitCalls = <(String, String)>[];

  @override
  Future<List<FieldSalesJson>> companyVisits(
    FieldSalesScope scope, {
    required DateTime from,
    required DateTime to,
  }) async {
    expect(scope.key, 'tenant.company.branch');
    visitCalls.add((fieldSalesDate(from), fieldSalesDate(to)));
    return [
      {
        'id': 'visit-one',
        'rep_id': _linkedRep,
        'rep_label': 'Asha Perera',
        'customer_name': 'Lanka Traders',
        'state': 'completed',
        'purpose': 'Quarterly review',
        'planned_for': '2026-11-17',
        'checked_in_at': '2026-11-17T04:00:00Z',
        'check_in_location': {'latitude': '6.927079', 'longitude': '79.861244'},
        'completed_at': '2026-11-17T05:00:00Z',
        'complete_location': null,
        'outcome': 'Met the buyer',
        'next_action': 'Send prices',
        'next_action_due': '2026-11-20',
      },
      {
        'id': 'visit-two',
        'rep_id': _unlinkedRep,
        'rep_label': 'Unlinked member ····9f3a',
        'customer_name': 'Colombo Stores',
        'state': 'cancelled',
        'purpose': 'Collect feedback',
        'cancel_reason': 'Shop closed',
      },
    ];
  }

  @override
  Future<List<FieldSalesJson>> subjects(FieldSalesScope scope) async =>
      subjectRows;

  @override
  Future<FieldSalesJson> receipt(FieldSalesScope scope, String key) async => {
    'state': 'not_found',
  };

  @override
  Future<FieldSalesJson> decide(FieldSalesJson params) =>
      throw StateError('Not used.');
}

FieldSalesJson _request(String id, String rep) => {
  'id': id,
  'version': '1',
  'rep_id': rep,
  'company_state': 'approved',
  'customer_state': 'email_link_pending',
  'input': {
    'discount_percent': '0',
    'discount_reason': '',
    'requested_date': '2026-11-20',
  },
  'preview': {
    'currency_code': 'LKR',
    'pricing': {'grand_total': '10.000000', 'lines': []},
  },
};

class _Harness {
  _Harness({Set<String>? caps})
    : caps = caps ?? {'sales.field.discounts.decide', 'sales.orders.manage'};
  final Set<String> caps;
  final gateway = _Gateway();
  final db = JentraLocalDatabase(NativeDatabase.memory());
  late final container = ProviderContainer(
    overrides: [
      activeTenantContextProvider.overrideWith((_) => _scope),
      authenticatedActorProvider.overrideWith(
        (_) => Stream.value(_scope.actorId),
      ),
      authSessionRevisionProvider.overrideWith((_) => Stream.value(1)),
      businessCapabilitiesProvider.overrideWith((_) async => caps),
      fieldSalesCompanyGatewayProvider.overrideWithValue(gateway),
      fieldSalesRepClockProvider.overrideWithValue(
        () => DateTime(2026, 11, 17, 15, 30),
      ),
      encryptedDraftRepositoryProvider.overrideWithValue(
        EncryptedDraftRepository(db, DraftCipher(keyStore: CompanyKeys())),
      ),
    ],
  );

  Future<void> pump(WidgetTester tester, Widget child) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await db.close();
    });
    container.listen(authenticatedActorProvider, (_, _) {});
    container.listen(authSessionRevisionProvider, (_, _) {});
    container.listen(businessCapabilitiesProvider, (_, _) {});
    container.read(authenticatedActorProvider);
    container.read(authSessionRevisionProvider);
    container.read(businessCapabilitiesProvider);
    await tester.pump();
    await tester.pump();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('rep list shows HR labels, exact counts and totals, never ids', (
    tester,
  ) async {
    final h = _Harness();
    await h.pump(tester, const FieldSalesReps(_scope));
    expect(h.gateway.repCalls, [('2026-11-01', '2026-11-17')]);
    expect(find.text('Asha Perera'), findsOneWidget);
    expect(find.text('Unlinked member ····9f3a'), findsOneWidget);
    expect(find.text('Approved LKR 100.350000'), findsOneWidget);
    expect(find.text('Approved LKR 0.000000'), findsOneWidget);
    expect(
      find.textContaining('Submitted 4 · Awaiting 1 · Approved 2 · Rejected 1'),
      findsNWidgets(2),
    );
    expect(
      find.textContaining('Not linked to an HR employee · 3 current customers'),
      findsOneWidget,
    );
    expect(find.textContaining(_linkedRep), findsNothing);
    expect(find.textContaining(_unlinkedRep), findsNothing);
  });

  testWidgets('choosing a period reloads the rep list for that range', (
    tester,
  ) async {
    final h = _Harness();
    await h.pump(tester, const FieldSalesReps(_scope));
    await tester.tap(find.text('Last 30 days'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last 90 days'));
    await tester.pumpAndSettle();
    expect(h.gateway.repCalls, [
      ('2026-11-01', '2026-11-17'),
      ('2026-10-19', '2026-11-17'),
      ('2026-08-20', '2026-11-17'),
    ]);
  });

  testWidgets('a portfolio manager may open the list; others are refused', (
    tester,
  ) async {
    final manager = _Harness(caps: {'sales.field.portfolios.manage'});
    await manager.pump(tester, const FieldSalesReps(_scope));
    expect(find.text('Asha Perera'), findsOneWidget);
  });

  testWidgets('without a company Field Sales permission nothing is read', (
    tester,
  ) async {
    final h = _Harness(caps: {'sales.orders.manage'});
    await h.pump(tester, const FieldSalesReps(_scope));
    expect(
      find.text('Current company authority is required to list reps.'),
      findsOneWidget,
    );
    expect(h.gateway.repCalls, isEmpty);
  });

  testWidgets('company review labels each request by its rep, not its id', (
    tester,
  ) async {
    final h = _Harness();
    h.gateway.subjectRows = [
      _request('request-one', _linkedRep),
      _request('request-two', 'b0000000-0000-4000-8000-00000000dead'),
    ];
    await h.pump(tester, const FieldCompanyReview(_scope));
    expect(find.text('Representative: Asha Perera'), findsOneWidget);
    expect(find.text('Representative: not listed'), findsOneWidget);
    expect(find.textContaining(_linkedRep), findsNothing);
    expect(find.textContaining('dead'), findsNothing);
  });

  testWidgets('company review still works when rep names cannot be read', (
    tester,
  ) async {
    final h = _Harness();
    h.gateway
      ..failReps = true
      ..subjectRows = [_request('request-one', _linkedRep)];
    await h.pump(tester, const FieldCompanyReview(_scope));
    expect(find.text('Representative: name unavailable'), findsOneWidget);
    expect(find.text('Request request-one · revision 1'), findsOneWidget);
    expect(find.textContaining(_linkedRep), findsNothing);
  });

  testWidgets(
    'visit list shows reps by label, outcomes and recorded locations',
    (tester) async {
      final h = _Harness();
      await h.pump(tester, const FieldSalesVisits(_scope));
      expect(h.gateway.visitCalls, [('2026-11-01', '2026-11-17')]);
      expect(find.text('Lanka Traders · Completed'), findsOneWidget);
      expect(find.text('Representative: Asha Perera'), findsOneWidget);
      expect(
        find.text('Representative: Unlinked member ····9f3a'),
        findsOneWidget,
      );
      expect(
        find.text('Checked in 2026-11-17T04:00:00Z at 6.927079, 79.861244'),
        findsOneWidget,
      );
      expect(find.text('Completed 2026-11-17T05:00:00Z'), findsOneWidget);
      expect(
        find.text('Next action: Send prices by 2026-11-20'),
        findsOneWidget,
      );
      expect(find.text('Cancelled: Shop closed'), findsOneWidget);
      expect(find.textContaining(_linkedRep), findsNothing);
      await tester.tap(find.text('Last 90 days'));
      await tester.pumpAndSettle();
      expect(h.gateway.visitCalls.last, ('2026-08-20', '2026-11-17'));
    },
  );

  testWidgets('visit list needs a company Field Sales permission', (
    tester,
  ) async {
    final h = _Harness(caps: {'sales.orders.manage'});
    await h.pump(tester, const FieldSalesVisits(_scope));
    expect(
      find.text('Current company authority is required to list visits.'),
      findsOneWidget,
    );
    expect(h.gateway.visitCalls, isEmpty);
  });
}
