import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

void main() {
  testWidgets('status communicates meaning with icon and semantics — NFR-7', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: JentraTheme.light(),
          home: const Scaffold(
            body: JentraStatusBadge(
              label: 'Approved',
              tone: JentraStatusTone.success,
            ),
          ),
        ),
      );

      expect(find.text('Approved'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.bySemanticsLabel('Status: Approved'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  test('density tokens match approved row heights — FR-7', () {
    expect(JentraDensity.compact.rowHeight, 32);
    expect(JentraDensity.comfortable.rowHeight, 40);
  });

  test('brand colors are the approved greenfield identity', () {
    expect(JentraColors.navy900, const Color(0xFF0B1F3A));
    expect(JentraColors.green600, const Color(0xFF0B7A4B));
  });
}
