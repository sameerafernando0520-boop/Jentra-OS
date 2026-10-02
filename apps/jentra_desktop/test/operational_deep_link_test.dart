import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/operations/operational_link.dart';
import 'package:jentra_desktop/src/features/operations/operational_screen.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_domain/jentra_domain.dart';

const _initialScope = BusinessScopeState(
  tenants: [
    TenantSummary(
      id: 'first',
      name: 'First',
      slug: 'first',
      status: 'active',
      membershipStatus: 'active',
    ),
    TenantSummary(
      id: 'second',
      name: 'Second',
      slug: 'second',
      status: 'active',
      membershipStatus: 'active',
    ),
  ],
  legalEntities: [
    LegalEntitySummary(
      id: 'preview-entity',
      tenantId: 'first',
      name: 'First Entity',
      code: 'FE',
      currencyCode: 'LKR',
      timezone: 'Asia/Colombo',
      status: 'active',
    ),
  ],
  branches: [
    BranchSummary(
      id: 'preview-branch',
      tenantId: 'first',
      legalEntityId: 'preview-entity',
      name: 'First Branch',
      code: 'FB',
      timezone: 'Asia/Colombo',
      status: 'active',
    ),
  ],
  tenantId: 'first',
  legalEntityId: 'preview-entity',
  branchId: 'preview-branch',
);

Future<ProviderContainer> _open(
  WidgetTester tester, {
  required String tenantId,
  required String entityId,
  required String branchId,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        businessScopeProvider.overrideWithBuild(
          (ref, notifier) async => _initialScope,
        ),
      ],
      child: MaterialApp(
        home: OperationalScreen(
          target: (
            tenantId: tenantId,
            entityId: entityId,
            branchId: branchId,
            kind: 'supplier_bill',
            id: 'known-document',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(OperationalScreen)),
  );
}

void main() {
  test('command palette accepts only a complete relative document link', () {
    const link =
        '/operations/documents?tenant=00000000-0000-4000-8000-000000000001&entity=00000000-0000-4000-8000-000000000002&branch=00000000-0000-4000-8000-000000000003&kind=supplier_bill&id=00000000-0000-4000-8000-000000000004';
    expect(parseOperationalDocumentLocation(link), link);
    expect(
      parseOperationalDocumentLocation('https://other.example$link'),
      isNull,
    );
    expect(parseOperationalDocumentLocation('$link&kind=lead'), isNull);
    expect(
      parseOperationalDocumentLocation(
        link.replaceAll('supplier_bill', 'secret'),
      ),
      isNull,
    );
    expect(
      parseOperationalDocumentLocation(link.replaceAll('000000000004', 'bad')),
      isNull,
    );
  });

  testWidgets('permitted deep link restores the complete context once', (
    tester,
  ) async {
    final container = await _open(
      tester,
      tenantId: 'second',
      entityId: 'preview-entity',
      branchId: 'preview-branch-colombo',
    );
    final selected = container.read(businessScopeProvider).requireValue;
    expect(selected.tenantId, 'second');
    expect(selected.legalEntityId, 'preview-entity');
    expect(selected.branchId, 'preview-branch-colombo');
    expect(
      find.text(
        'This document destination is unavailable in the selected business scope.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('unknown deep link preserves the previous selection', (
    tester,
  ) async {
    final container = await _open(
      tester,
      tenantId: 'foreign',
      entityId: 'preview-entity',
      branchId: 'preview-branch',
    );
    final selected = container.read(businessScopeProvider).requireValue;
    expect(selected.tenantId, 'first');
    expect(selected.branchId, 'preview-branch');
    expect(
      find.text(
        'This document destination is unavailable in the selected business scope.',
      ),
      findsOneWidget,
    );
  });

  test(
    'notification route requires a complete allowlisted source identity',
    () {
      SetupRecord notice(Map<String, Object?> fields) =>
          SetupRecord.fromJson(BusinessSetupResource.notifications, {
            'id': 'notice',
            'tenant_id': '00000000-0000-4000-8000-000000000001',
            'legal_entity_id': '00000000-0000-4000-8000-000000000002',
            'branch_id': '00000000-0000-4000-8000-000000000003',
            'aggregate_type': 'supplier_bill',
            'aggregate_id': '00000000-0000-4000-8000-000000000004',
            ...fields,
          });
      expect(
        operationalNotificationLocation(notice({})),
        contains('kind=supplier_bill'),
      );
      expect(
        operationalNotificationLocation(notice({'branch_id': null})),
        isNull,
      );
      expect(
        operationalNotificationLocation(
          notice({'aggregate_type': 'private_hr'}),
        ),
        isNull,
      );
      expect(
        operationalNotificationLocation(notice({'aggregate_id': 'malformed'})),
        isNull,
      );
    },
  );

  test(
    'cancelled context restoration leaves the current selection intact',
    () async {
      final container = ProviderContainer(
        overrides: [
          businessScopeProvider.overrideWithBuild(
            (ref, notifier) async => _initialScope,
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(businessScopeProvider.future);
      expect(
        await container
            .read(businessScopeProvider.notifier)
            .selectPermittedContext(
              tenantId: 'second',
              legalEntityId: 'preview-entity',
              branchId: 'preview-branch-colombo',
              isCurrent: () => false,
            ),
        isFalse,
      );
      expect(
        container.read(businessScopeProvider).requireValue,
        same(_initialScope),
      );
    },
  );
}
