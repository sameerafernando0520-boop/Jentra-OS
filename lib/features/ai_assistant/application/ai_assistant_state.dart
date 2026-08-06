import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../company/application/company_state.dart';
import '../data/supabase_ai_assistant_repository.dart';
import 'ai_failure.dart';
import 'ai_models.dart';

final aiConversationListProvider = FutureProvider.autoDispose<List<AiConversation>>((
  ref,
) async {
  final companyId = ref.watch(selectedCompanyIdProvider);
  if (companyId == null || companyId.trim().isEmpty) return const [];

  return ref
      .watch(aiAssistantRepositoryProvider)
      .listConversations(companyId: companyId);
}, retry: (_, _) => null);

final aiMessagesProvider = FutureProvider.autoDispose
    .family<List<AiMessage>, String>((ref, conversationId) async {
      final companyId = ref.watch(selectedCompanyIdProvider);
      if (companyId == null || companyId.trim().isEmpty) return const [];

      return ref.watch(aiAssistantRepositoryProvider).listMessages(
            companyId: companyId,
            conversationId: conversationId,
          );
    }, retry: (_, _) => null);

final aiInsightsProvider = FutureProvider.autoDispose<List<AiInsight>>((
  ref,
) async {
  final companyId = ref.watch(selectedCompanyIdProvider);
  if (companyId == null || companyId.trim().isEmpty) return const [];

  return ref
      .watch(aiAssistantRepositoryProvider)
      .listInsights(companyId: companyId);
}, retry: (_, _) => null);

final aiBusinessSummaryProvider = FutureProvider.autoDispose<BusinessSummaryContext>((
  ref,
) async {
  final companyId = ref.watch(selectedCompanyIdProvider);
  if (companyId == null || companyId.trim().isEmpty) {
    throw const AiFailure('Select a company before fetching AI context.');
  }

  return ref
      .watch(aiAssistantRepositoryProvider)
      .getCompanyBusinessSummary(companyId: companyId);
}, retry: (_, _) => null);

final aiChatControllerProvider =
    AsyncNotifierProvider<AiChatController, void>(
      AiChatController.new,
      retry: (_, _) => null,
    );

final class AiChatController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<AiConversation> startNewConversation({String? title}) async {
    final companyId = _requireCompanyId();
    state = const AsyncLoading();
    try {
      final conv = await ref
          .read(aiAssistantRepositoryProvider)
          .createConversation(
            companyId: companyId,
            title: title ?? 'New Conversation',
          );

      state = const AsyncData(null);
      ref.invalidate(aiConversationListProvider);
      return conv;
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> sendMessage({
    required String conversationId,
    required String text,
  }) async {
    final companyId = _requireCompanyId();
    final prompt = text.trim();
    if (prompt.isEmpty) return;

    state = const AsyncLoading();
    try {
      final repo = ref.read(aiAssistantRepositoryProvider);

      // 1. Save user message
      await repo.saveMessage(
        companyId: companyId,
        conversationId: conversationId,
        senderRole: 'user',
        content: prompt,
      );
      ref.invalidate(aiMessagesProvider(conversationId));

      // 2. Generate assistant response context-aware
      final responseText = await repo.generateAssistantResponse(
        companyId: companyId,
        userPrompt: prompt,
      );

      // 3. Save assistant message
      await repo.saveMessage(
        companyId: companyId,
        conversationId: conversationId,
        senderRole: 'assistant',
        content: responseText,
      );

      state = const AsyncData(null);
      ref.invalidate(aiMessagesProvider(conversationId));
      ref.invalidate(aiConversationListProvider);
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> dismissInsight(String insightId) async {
    final companyId = _requireCompanyId();
    state = const AsyncLoading();
    try {
      await ref
          .read(aiAssistantRepositoryProvider)
          .dismissInsight(companyId: companyId, insightId: insightId);

      state = const AsyncData(null);
      ref.invalidate(aiInsightsProvider);
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  String _requireCompanyId() {
    final companyId = ref.read(selectedCompanyIdProvider);
    if (companyId == null || companyId.trim().isEmpty) {
      throw const AiFailure('Select a company before using AI Assistant.');
    }
    return companyId;
  }
}
