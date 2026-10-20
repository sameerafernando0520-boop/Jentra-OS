import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/features/assurance/assurance_format.dart';

void main() {
  test('dates read the same on every assurance screen', () {
    expect(auditDate('2026-10-08'), '8 Oct 2026');
    expect(auditDate(DateTime.utc(2026, 7, 23)), '23 Jul 2026');
    expect(auditDate(null), 'no date');
    expect(auditDateTime('2026-10-01T09:00:00Z'), '1 Oct 2026 09:00 UTC');
  });

  test('codes become sentence-case labels', () {
    expect(auditLabel('fieldwork'), 'Fieldwork');
    expect(auditLabel('risk_accepted'), 'Risk accepted');
    expect(auditLabel('create_engagement'), 'Create engagement');
  });

  testWidgets('a digest is short on screen and complete on demand', (t) async {
    await t.pumpWidget(
      MaterialApp(home: Scaffold(body: DigestText('ab' * 32))),
    );
    expect(find.text('SHA-256 abababababab…'), findsOneWidget);
    expect(find.byTooltip('ab' * 32), findsOneWidget);
    expect(find.bySemanticsLabel('SHA-256 starting abababab'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('ab' * 20)), findsNothing);
  });
}
