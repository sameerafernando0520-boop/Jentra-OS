import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_os/features/ai_assistant/application/ai_assistant_state.dart';
import 'package:jentra_os/features/ai_assistant/application/ai_failure.dart';
import 'package:jentra_os/features/ai_assistant/data/supabase_ai_assistant_repository.dart';
import 'package:jentra_os/features/company/application/company_state.dart';

import '../fake_ai_assistant_repository.dart';

void main() {
  group('AiAssistantState & Controller', () {
    test('missing company ID returns empty conversations and throws AiFailure on context query', () async {
      final fakeRepo = FakeAiAssistantRepository();
      final container = ProviderContainer(
        overrides: [
          aiAssistantRepositoryProvider.overrideWithValue(fakeRepo),
          selectedCompanyIdProvider.overrideWith((ref) => null),
        ],
      );
      addTearDown(container.dispose);

      final conversations = await container.read(aiConversationListProvider.future);
      expect(conversations, isEmpty);

      expect(
        container.read(aiBusinessSummaryProvider.future),
        throwsA(isA<AiFailure>()),
      );
    });

    test('sendMessage creates conversation, saves user message and assistant placeholder response', () async {
      final fakeRepo = FakeAiAssistantRepository();
      final container = ProviderContainer(
        overrides: [
          aiAssistantRepositoryProvider.overrideWithValue(fakeRepo),
          selectedCompanyIdProvider.overrideWith((ref) => 'comp-1'),
        ],
      );
      addTearDown(container.dispose);

      final newConv = await container
          .read(aiChatControllerProvider.notifier)
          .startNewConversation(title: 'Revenue Query');

      expect(newConv.title, equals('Revenue Query'));

      await container
          .read(aiChatControllerProvider.notifier)
          .sendMessage(
            conversationId: newConv.id,
            text: 'What is my total sales revenue?',
          );

      final msgs = await container.read(aiMessagesProvider(newConv.id).future);
      expect(msgs, hasLength(2));
      expect(msgs.first.isUser, isTrue);
      expect(msgs.first.content, equals('What is my total sales revenue?'));
      expect(msgs.last.isAssistant, isTrue);
      expect(msgs.last.content, contains('Revenue'));
    });
  });
}
