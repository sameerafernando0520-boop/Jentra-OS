import 'package:jentra_os/features/ai_assistant/application/ai_assistant_repository.dart';
import 'package:jentra_os/features/ai_assistant/application/ai_models.dart';
import 'package:jentra_os/features/ai_assistant/domain/business_context_builder.dart';

final class FakeAiAssistantRepository implements AiAssistantRepository {
  FakeAiAssistantRepository({
    List<AiConversation>? conversations,
    List<AiMessage>? messages,
    List<AiInsight>? insights,
  })  : conversations = conversations ?? <AiConversation>[],
        messages = messages ?? <AiMessage>[],
        insights = insights ??
            [
              AiInsight(
                id: 'ins-1',
                companyId: 'comp-1',
                title: 'Outstanding Receivables Opportunity',
                summary: 'You have \$450.00 in unpaid customer balances.',
                category: 'cash_flow',
                severity: 'warning',
                actionLabel: 'View Invoices',
                actionTarget: '/sales/invoices',
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            ];

  final List<AiConversation> conversations;
  final List<AiMessage> messages;
  final List<AiInsight> insights;
  final List<String> listCompanyIds = <String>[];

  @override
  Future<BusinessSummaryContext> getCompanyBusinessSummary({
    required String companyId,
  }) async {
    return BusinessSummaryContext(
      companyId: companyId,
      customersCount: 5,
      productsCount: 10,
      invoicesCount: 4,
      totalRevenue: 2000.00,
      outstandingReceivables: 450.00,
      cashBalance: 1500.00,
    );
  }

  @override
  Future<List<AiConversation>> listConversations({
    required String companyId,
  }) async {
    listCompanyIds.add(companyId);
    return conversations.where((c) => c.companyId == companyId).toList();
  }

  @override
  Future<AiConversation> createConversation({
    required String companyId,
    required String title,
  }) async {
    final now = DateTime.now();
    final conv = AiConversation(
      id: 'conv-${conversations.length + 1}',
      companyId: companyId,
      title: title,
      createdAt: now,
      updatedAt: now,
    );
    conversations.add(conv);
    return conv;
  }

  @override
  Future<List<AiMessage>> listMessages({
    required String companyId,
    required String conversationId,
  }) async {
    return messages
        .where((m) => m.companyId == companyId && m.conversationId == conversationId)
        .toList();
  }

  @override
  Future<AiMessage> saveMessage({
    required String companyId,
    required String conversationId,
    required String senderRole,
    required String content,
    Map<String, dynamic> metadata = const {},
  }) async {
    final msg = AiMessage(
      id: 'msg-${messages.length + 1}',
      companyId: companyId,
      conversationId: conversationId,
      senderRole: senderRole,
      content: content,
      metadata: metadata,
      createdAt: DateTime.now(),
    );
    messages.add(msg);
    return msg;
  }

  @override
  Future<List<AiInsight>> listInsights({
    required String companyId,
  }) async {
    return insights.where((i) => i.companyId == companyId && !i.isDismissed).toList();
  }

  @override
  Future<void> dismissInsight({
    required String companyId,
    required String insightId,
  }) async {
    final idx = insights.indexWhere((i) => i.id == insightId && i.companyId == companyId);
    if (idx != -1) {
      final old = insights[idx];
      insights[idx] = AiInsight(
        id: old.id,
        companyId: old.companyId,
        title: old.title,
        summary: old.summary,
        category: old.category,
        severity: old.severity,
        actionLabel: old.actionLabel,
        actionTarget: old.actionTarget,
        isDismissed: true,
        createdAt: old.createdAt,
        updatedAt: DateTime.now(),
      );
    }
  }

  @override
  Future<String> generateAssistantResponse({
    required String companyId,
    required String userPrompt,
  }) async {
    final summary = await getCompanyBusinessSummary(companyId: companyId);
    return BusinessContextBuilder.buildContextualResponse(
      userPrompt: userPrompt,
      summary: summary,
    );
  }
}
