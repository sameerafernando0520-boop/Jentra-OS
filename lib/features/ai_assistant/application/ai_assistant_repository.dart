import '../application/ai_models.dart';

abstract class AiAssistantRepository {
  Future<BusinessSummaryContext> getCompanyBusinessSummary({
    required String companyId,
  });

  Future<List<AiConversation>> listConversations({
    required String companyId,
  });

  Future<AiConversation> createConversation({
    required String companyId,
    required String title,
  });

  Future<List<AiMessage>> listMessages({
    required String companyId,
    required String conversationId,
  });

  Future<AiMessage> saveMessage({
    required String companyId,
    required String conversationId,
    required String senderRole,
    required String content,
    Map<String, dynamic> metadata = const {},
  });

  Future<List<AiInsight>> listInsights({
    required String companyId,
  });

  Future<void> dismissInsight({
    required String companyId,
    required String insightId,
  });

  Future<String> generateAssistantResponse({
    required String companyId,
    required String userPrompt,
  });
}
