import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../company/application/company_state.dart';
import '../../../company/presentation/widgets/company_context_gate.dart';
import '../../application/ai_failure.dart';
import '../../application/ai_models.dart';
import '../../application/ai_assistant_state.dart';

final class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

final class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  String? _activeConversationId;
  bool _sending = false;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String text) async {
    final prompt = text.trim();
    if (prompt.isEmpty || _sending) return;

    _messageController.clear();
    setState(() => _sending = true);

    try {
      var convId = _activeConversationId;
      if (convId == null) {
        final newConv = await ref
            .read(aiChatControllerProvider.notifier)
            .startNewConversation(title: prompt.length > 25 ? '${prompt.substring(0, 25)}...' : prompt);
        convId = newConv.id;
        setState(() => _activeConversationId = convId);
      }

      await ref
          .read(aiChatControllerProvider.notifier)
          .sendMessage(conversationId: convId, text: prompt);

      if (mounted) {
        setState(() => _sending = false);
        _scrollToBottom();
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _sending = false);
        final message = error is AiFailure ? error.message : error.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final company = ref.watch(selectedCompanyProvider);
    if (company == null) {
      return const CompanyRouteRedirect(location: '/company/select');
    }

    final conversationsAsync = ref.watch(aiConversationListProvider);
    final summaryAsync = ref.watch(aiBusinessSummaryProvider);

    // Auto-select latest conversation if available
    final conversations = conversationsAsync.value ?? const <AiConversation>[];
    if (_activeConversationId == null && conversations.isNotEmpty) {
      _activeConversationId = conversations.first.id;
    }

    final messagesAsync = _activeConversationId != null
        ? ref.watch(aiMessagesProvider(_activeConversationId!))
        : const AsyncData(<AiMessage>[]);

    final messages = messagesAsync.value ?? const <AiMessage>[];

    return Scaffold(
      body: Column(
        children: [
          // Business Context Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: summaryAsync.when(
                    loading: () => const Text('Loading company context...', style: TextStyle(fontSize: 12)),
                    error: (_, _) => Text('Company: ${company.name} (Context Ready)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    data: (summary) => Text(
                      'AI Context (${company.name}): Rev \$${summary.totalRevenue.toStringAsFixed(0)} • Cash \$${summary.cashBalance.toStringAsFixed(0)} • Due \$${summary.outstandingReceivables.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.chat_bubble_outline, size: 20),
                  tooltip: 'Switch Thread',
                  onSelected: (val) {
                    if (val == 'new') {
                      setState(() => _activeConversationId = null);
                    } else {
                      setState(() => _activeConversationId = val);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'new',
                      child: Text('+ Start New Conversation'),
                    ),
                    ...conversations.map(
                      (c) => PopupMenuItem(
                        value: c.id,
                        child: Text(c.title),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Messages View
          Expanded(
            child: messages.isEmpty
                ? _EmptyChatView(
                    companyName: company.name,
                    onPromptSelected: _sendMessage,
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length + (_sending ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= messages.length) {
                        return const _ThinkingBubble();
                      }
                      final msg = messages[index];
                      return _MessageBubble(message: msg);
                    },
                  ),
          ),

          // Message Input Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Ask AI about sales, cash flow, customers...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: _sendMessage,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send),
                  onPressed: _sending ? null : () => _sendMessage(_messageController.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final AiMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final theme = Theme.of(context);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primary
              : theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isUser ? Icons.person : Icons.smart_toy,
                  size: 14,
                  color: isUser ? Colors.white70 : theme.colorScheme.onSecondaryContainer.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 4),
                Text(
                  isUser ? 'You' : 'Jentra OS AI',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isUser ? Colors.white70 : theme.colorScheme.onSecondaryContainer.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              message.content,
              style: TextStyle(
                color: isUser ? Colors.white : theme.colorScheme.onSecondaryContainer,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Analyzing company context...', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

final class _EmptyChatView extends StatelessWidget {
  const _EmptyChatView({
    required this.companyName,
    required this.onPromptSelected,
  });

  final String companyName;
  final ValueChanged<String> onPromptSelected;

  @override
  Widget build(BuildContext context) {
    final suggestions = [
      'What is my total revenue and outstanding receivables?',
      'How much cash balance do I have in bank accounts?',
      'Show me a summary of my active customers and inventory.',
      'Give me an overview of company health.',
    ];

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircleAvatar(
              radius: 36,
              child: Icon(Icons.auto_awesome, size: 40),
            ),
            const SizedBox(height: 16),
            Text(
              'Jentra OS AI Assistant',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask anything about $companyName\'s sales, cash flow, CRM, or inventory.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            Text(
              'Suggested Business Questions:',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            ...suggestions.map(
              (prompt) => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                  onPressed: () => onPromptSelected(prompt),
                  child: Text(prompt, textAlign: TextAlign.center),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
