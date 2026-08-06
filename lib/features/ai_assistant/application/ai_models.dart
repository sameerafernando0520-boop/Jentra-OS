final class BusinessSummaryContext {
  const BusinessSummaryContext({
    required this.companyId,
    required this.customersCount,
    required this.productsCount,
    required this.invoicesCount,
    required this.totalRevenue,
    required this.outstandingReceivables,
    required this.cashBalance,
  });

  final String companyId;
  final int customersCount;
  final int productsCount;
  final int invoicesCount;
  final double totalRevenue;
  final double outstandingReceivables;
  final double cashBalance;

  String toFormattedPromptContext() {
    return '''
Business Context Overview:
- Total Customers: $customersCount
- Active Products: $productsCount
- Total Issued Invoices: $invoicesCount
- Total Revenue: \$${totalRevenue.toStringAsFixed(2)}
- Outstanding Receivables: \$${outstandingReceivables.toStringAsFixed(2)}
- Cash/Bank Balance: \$${cashBalance.toStringAsFixed(2)}
''';
  }
}

final class AiConversation {
  const AiConversation({
    required this.id,
    required this.companyId,
    required this.title,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String companyId;
  final String title;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
}

final class AiMessage {
  const AiMessage({
    required this.id,
    required this.companyId,
    required this.conversationId,
    required this.senderRole, // 'user', 'assistant', 'system'
    required this.content,
    this.metadata = const {},
    required this.createdAt,
  });

  final String id;
  final String companyId;
  final String conversationId;
  final String senderRole;
  final String content;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  bool get isUser => senderRole == 'user';
  bool get isAssistant => senderRole == 'assistant';
}

final class AiInsight {
  const AiInsight({
    required this.id,
    required this.companyId,
    required this.title,
    required this.summary,
    this.category = 'general', // 'sales', 'cash_flow', 'inventory', 'customers', 'general'
    this.severity = 'info', // 'info', 'warning', 'action_required'
    this.actionLabel,
    this.actionTarget,
    this.isDismissed = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String companyId;
  final String title;
  final String summary;
  final String category;
  final String severity;
  final String? actionLabel;
  final String? actionTarget;
  final bool isDismissed;
  final DateTime createdAt;
  final DateTime updatedAt;
}

final class AiMessageInput {
  const AiMessageInput({
    required this.conversationId,
    required this.content,
  });

  final String conversationId;
  final String content;
}
