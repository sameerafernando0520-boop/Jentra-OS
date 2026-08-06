import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/ai_assistant_repository.dart';
import '../application/ai_models.dart';
import 'ai_assistant_service.dart';

final aiAssistantRepositoryProvider = Provider<AiAssistantRepository>((ref) {
  return SupabaseAiAssistantRepository(ref.watch(aiAssistantServiceProvider));
});

final class SupabaseAiAssistantRepository implements AiAssistantRepository {
  const SupabaseAiAssistantRepository(this._service);

  final AiAssistantService _service;

  @override
  Future<BusinessSummaryContext> getCompanyBusinessSummary({
    required String companyId,
  }) {
    return _service.fetchCompanyBusinessSummary(companyId: companyId);
  }

  @override
  Future<List<AiConversation>> listConversations({
    required String companyId,
  }) async {
    final rows = await _service.fetchConversations(companyId: companyId);
    return rows.map((r) => _mapConversation(r)).toList();
  }

  @override
  Future<AiConversation> createConversation({
    required String companyId,
    required String title,
  }) async {
    final row = await _service.createConversation(
      companyId: companyId,
      title: title,
    );
    return _mapConversation(row);
  }

  @override
  Future<List<AiMessage>> listMessages({
    required String companyId,
    required String conversationId,
  }) async {
    final rows = await _service.fetchMessages(
      companyId: companyId,
      conversationId: conversationId,
    );
    return rows.map((r) => _mapMessage(r)).toList();
  }

  @override
  Future<AiMessage> saveMessage({
    required String companyId,
    required String conversationId,
    required String senderRole,
    required String content,
    Map<String, dynamic> metadata = const {},
  }) async {
    final row = await _service.saveMessage(
      companyId: companyId,
      conversationId: conversationId,
      senderRole: senderRole,
      content: content,
      metadata: metadata,
    );
    return _mapMessage(row);
  }

  @override
  Future<List<AiInsight>> listInsights({
    required String companyId,
  }) async {
    final rows = await _service.fetchInsights(companyId: companyId);
    return rows.map((r) => _mapInsight(r)).toList();
  }

  @override
  Future<void> dismissInsight({
    required String companyId,
    required String insightId,
  }) {
    return _service.dismissInsight(
      companyId: companyId,
      insightId: insightId,
    );
  }

  @override
  Future<String> generateAssistantResponse({
    required String companyId,
    required String userPrompt,
  }) {
    return _service.generateAssistantResponse(
      companyId: companyId,
      userPrompt: userPrompt,
    );
  }

  AiConversation _mapConversation(Map<String, dynamic> row) {
    return AiConversation(
      id: row['id'] as String,
      companyId: row['company_id'] as String,
      title: row['title'] as String? ?? 'New Conversation',
      createdBy: row['created_by'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  AiMessage _mapMessage(Map<String, dynamic> row) {
    return AiMessage(
      id: row['id'] as String,
      companyId: row['company_id'] as String,
      conversationId: row['conversation_id'] as String,
      senderRole: row['sender_role'] as String? ?? 'user',
      content: row['content'] as String? ?? '',
      metadata: row['metadata'] is Map ? Map<String, dynamic>.from(row['metadata'] as Map) : const {},
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  AiInsight _mapInsight(Map<String, dynamic> row) {
    return AiInsight(
      id: row['id'] as String,
      companyId: row['company_id'] as String,
      title: row['title'] as String,
      summary: row['summary'] as String,
      category: row['category'] as String? ?? 'general',
      severity: row['severity'] as String? ?? 'info',
      actionLabel: row['action_label'] as String?,
      actionTarget: row['action_target'] as String?,
      isDismissed: row['is_dismissed'] as bool? ?? false,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
