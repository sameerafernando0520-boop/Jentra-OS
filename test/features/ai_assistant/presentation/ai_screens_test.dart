import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_os/features/ai_assistant/data/supabase_ai_assistant_repository.dart';
import 'package:jentra_os/features/ai_assistant/presentation/screens/ai_assistant_screen.dart';
import 'package:jentra_os/features/ai_assistant/presentation/screens/ai_chat_screen.dart';
import 'package:jentra_os/features/ai_assistant/presentation/screens/ai_insights_screen.dart';
import 'package:jentra_os/features/ai_assistant/presentation/screens/ai_settings_screen.dart';
import 'package:jentra_os/features/company/application/company_models.dart';
import 'package:jentra_os/features/company/application/company_state.dart';

import '../fake_ai_assistant_repository.dart';

void main() {
  const company1 = Company(
    id: 'comp-1',
    ownerUserId: 'user-1',
    name: 'Acme Corp',
    legalName: 'Acme Corp LLC',
    currencyCode: 'USD',
    countryCode: 'US',
    timezone: 'UTC',
    membershipRole: 'Owner',
    isOwner: true,
    isAdmin: true,
  );

  Widget buildTestWidget(Widget child, {FakeAiAssistantRepository? fakeAiRepo}) {
    final aiRepo = fakeAiRepo ?? FakeAiAssistantRepository();

    return ProviderScope(
      overrides: [
        aiAssistantRepositoryProvider.overrideWithValue(aiRepo),
        selectedCompanyProvider.overrideWith((ref) => company1),
        selectedCompanyIdProvider.overrideWith((ref) => 'comp-1'),
      ],
      child: MaterialApp(home: child),
    );
  }

  group('AI Assistant Screens UI Tests', () {
    testWidgets('AiAssistantScreen renders tabbed view with Chat, Insights, Settings', (tester) async {
      await tester.pumpWidget(buildTestWidget(const AiAssistantScreen()));
      await tester.pumpAndSettle();

      expect(find.text('i Book AI Assistant'), findsOneWidget);
      expect(find.text('AI Chat'), findsOneWidget);
      expect(find.text('Insights Inbox'), findsOneWidget);
      expect(find.text('AI Settings'), findsOneWidget);
    });

    testWidgets('AiChatScreen displays business context banner and prompt suggestions', (tester) async {
      await tester.pumpWidget(buildTestWidget(const AiChatScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('AI Context (Acme Corp)'), findsOneWidget);
      expect(find.text('Suggested Business Questions:'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('AiInsightsScreen displays business insight cards', (tester) async {
      await tester.pumpWidget(buildTestWidget(const AiInsightsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Outstanding Receivables Opportunity'), findsOneWidget);
      expect(find.textContaining('unpaid customer balances'), findsOneWidget);
      expect(find.text('View Invoices'), findsOneWidget);
    });

    testWidgets('AiSettingsScreen renders tenant boundary and privacy options', (tester) async {
      await tester.pumpWidget(buildTestWidget(const AiSettingsScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('AI Privacy & Data Boundaries (Acme Corp)'), findsOneWidget);
      expect(find.text('Strict Tenant Boundary Enforcement'), findsOneWidget);
      expect(find.text('Read-Only Data Access'), findsOneWidget);
    });
  });
}
