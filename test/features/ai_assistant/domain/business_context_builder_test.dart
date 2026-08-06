import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_os/features/ai_assistant/application/ai_models.dart';
import 'package:jentra_os/features/ai_assistant/domain/business_context_builder.dart';

void main() {
  group('BusinessContextBuilder', () {
    const summary = BusinessSummaryContext(
      companyId: 'comp-1',
      customersCount: 5,
      productsCount: 12,
      invoicesCount: 8,
      totalRevenue: 2500.00,
      outstandingReceivables: 450.00,
      cashBalance: 1800.00,
    );

    test('revenue query returns revenue and receivables metrics', () {
      final res = BusinessContextBuilder.buildContextualResponse(
        userPrompt: 'What is my total sales and revenue?',
        summary: summary,
      );

      expect(res, contains('\$2500.00'));
      expect(res, contains('\$450.00'));
    });

    test('cash query returns bank and cash liquidity', () {
      final res = BusinessContextBuilder.buildContextualResponse(
        userPrompt: 'How much cash balance do I have?',
        summary: summary,
      );

      expect(res, contains('\$1800.00'));
    });

    test('customer query returns active CRM count', () {
      final res = BusinessContextBuilder.buildContextualResponse(
        userPrompt: 'How many customers do I have?',
        summary: summary,
      );

      expect(res, contains('5 active customer(s)'));
    });

    test('overview query returns structured business health snapshot', () {
      final res = BusinessContextBuilder.buildContextualResponse(
        userPrompt: 'Give me a summary overview of business health',
        summary: summary,
      );

      expect(res, contains('i Book AI Business Summary'));
      expect(res, contains('\$2500.00'));
      expect(res, contains('\$1800.00'));
    });
  });
}
