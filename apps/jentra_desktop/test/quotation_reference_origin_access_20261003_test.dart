import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/sales/quotation_editor.dart';
import 'package:jentra_desktop/src/features/sales/quotation_reference_picker.dart';
import 'package:jentra_domain/jentra_domain.dart';

import 'quotation_controller_test.dart' as q;
import 'quotation_reference_access_20261003_test.dart' show References;

class DeniedReferences extends References {
  bool deny = false;
  @override
  Future<CursorPage<QuotationReference>> pageReferences({
    required TenantContext context,
    required QuotationReferenceKind kind,
    required QuotationReferenceQuery query,
  }) {
    if (deny) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Reference authorization has been withdrawn.',
      );
    }
    return super.pageReferences(context: context, kind: kind, query: query);
  }
}

Future<void> pumpFixture(
  WidgetTester tester,
  Widget child,
  References references,
) async {
  await tester.binding.setSurfaceSize(const Size(1440, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = ProviderContainer(
    overrides: [
      activeTenantContextProvider.overrideWithValue(q.scope),
      businessCapabilitiesProvider.overrideWithValue(
        const AsyncData({...q.permissions, 'sales.orders.manage'}),
      ),
      connectivityStateProvider.overrideWithValue(
        const AsyncData(ConnectivityState.online),
      ),
      quotationReferenceRepositoryProvider.overrideWithValue(references),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: JentraTheme.light(),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(_fonts);
  testWidgets(
    'current quotation reference typed denial permanently ends picker access',
    (tester) async {
      final references = DeniedReferences();
      await pumpFixture(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showQuotationReferencePicker(
              context,
              title: 'Customer',
              kind: QuotationReferenceKind.customer,
            ),
            child: const Text('Choose customer'),
          ),
        ),
        references,
      );
      await tester.tap(find.text('Choose customer'));
      await tester.pumpAndSettle();
      expect(find.text('Private original customer'), findsOneWidget);
      references.deny = true;
      await tester.tap(find.byTooltip('Search references'));
      await tester.pumpAndSettle();
      expect(find.text('Private original customer'), findsNothing);
      expect(find.text('Reference access changed'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    },
  );

  testWidgets(
    'quotation editor disposal hides surviving root reference rows without route pop',
    (tester) async {
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      final changed = <Map<String, Object?>>[];
      await pumpFixture(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (_, value, _) => value
              ? SingleChildScrollView(
                  child: QuotationEditor(
                    form: q.detail().draft.toJson(),
                    onChanged: (form) async => changed.add(form),
                    enabled: true,
                    online: true,
                    baseCurrency: 'LKR',
                  ),
                )
              : const Text('Original editor removed'),
        ),
        References(),
      );
      await tester.tap(find.byKey(const Key('pick-customer_id')));
      await tester.pumpAndSettle();
      expect(find.text('Private original customer'), findsOneWidget);
      visible.value = false;
      await tester.pumpAndSettle();
      expect(find.text('Original editor removed'), findsOneWidget);
      expect(find.text('Private original customer'), findsNothing);
      expect(changed, isEmpty);
    },
  );
}

Future<void> _fonts() async {
  const root = 'packages/jentra_design_system/assets/fonts';
  await (FontLoader(JentraTypography.sansFamily)
        ..addFont(rootBundle.load('$root/Manrope-Regular.ttf'))
        ..addFont(rootBundle.load('$root/Manrope-Medium.ttf'))
        ..addFont(rootBundle.load('$root/Manrope-SemiBold.ttf')))
      .load();
  await (FontLoader(
    JentraTypography.monoFamily,
  )..addFont(rootBundle.load('$root/IBMPlexMono-Regular.ttf'))).load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}
