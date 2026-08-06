import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_providers.dart';
import '../application/ai_failure.dart';
import '../application/ai_models.dart';
import '../domain/ai_permission_guard.dart';
import '../domain/business_context_builder.dart';

final aiAssistantServiceProvider = Provider<AiAssistantService>((ref) {
  return AiAssistantService(ref.watch(supabaseServiceProvider).client);
});

final class AiAssistantService {
  const AiAssistantService(this._client);

  final SupabaseClient _client;

  void requireSession(String companyId) {
    final user = _client.auth.currentUser;
    AiPermissionGuard.verifyAccess(
      currentUserId: user?.id,
      companyId: companyId,
      targetCompanyId: companyId,
    );
  }

  Future<BusinessSummaryContext> fetchCompanyBusinessSummary({
    required String companyId,
  }) async {
    requireSession(companyId);
    final response = await _client.rpc(
      'get_company_business_summary',
      params: {'p_company_id': companyId},
    );

    if (response is! Map) {
      throw const AiFailure('Failed to load company AI summary.');
    }
    final res = Map<String, dynamic>.from(response);

    return BusinessSummaryContext(
      companyId: res['company_id'] as String? ?? companyId,
      customersCount: (res['customers_count'] as num?)?.toInt() ?? 0,
      productsCount: (res['products_count'] as num?)?.toInt() ?? 0,
      invoicesCount: (res['invoices_count'] as num?)?.toInt() ?? 0,
      totalRevenue: (res['total_revenue'] as num?)?.toDouble() ?? 0.0,
      outstandingReceivables: (res['outstanding_receivables'] as num?)?.toDouble() ?? 0.0,
      cashBalance: (res['cash_balance'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Future<List<Map<String, dynamic>>> fetchConversations({
    required String companyId,
  }) async {
    requireSession(companyId);
    final rows = await _client
        .from('ai_conversations')
        .select('*')
        .eq('company_id', companyId)
        .order('updated_at', ascending: false);

    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> createConversation({
    required String companyId,
    required String title,
  }) async {
    requireSession(companyId);
    final row = await _client
        .from('ai_conversations')
        .insert({
          'company_id': companyId,
          'title': title,
        })
        .select()
        .single();

    return Map<String, dynamic>.from(row);
  }

  Future<List<Map<String, dynamic>>> fetchMessages({
    required String companyId,
    required String conversationId,
  }) async {
    requireSession(companyId);
    final rows = await _client
        .from('ai_messages')
        .select('*')
        .eq('company_id', companyId)
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true);

    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> saveMessage({
    required String companyId,
    required String conversationId,
    required String senderRole,
    required String content,
    Map<String, dynamic> metadata = const {},
  }) async {
    requireSession(companyId);
    final row = await _client
        .from('ai_messages')
        .insert({
          'company_id': companyId,
          'conversation_id': conversationId,
          'sender_role': senderRole,
          'content': content,
          'metadata': metadata,
        })
        .select()
        .single();

    // Touch conversation updated_at
    await _client
        .from('ai_conversations')
        .update({'updated_at': DateTime.now().toIso8601String()})
        .eq('company_id', companyId)
        .eq('id', conversationId);

    return Map<String, dynamic>.from(row);
  }

  Future<List<Map<String, dynamic>>> fetchInsights({
    required String companyId,
  }) async {
    requireSession(companyId);
    final rows = await _client
        .from('ai_insights')
        .select('*')
        .eq('company_id', companyId)
        .eq('is_dismissed', false)
        .order('created_at', ascending: false);

    if (rows.isEmpty) {
      // Seed initial insights if empty
      await _seedInitialInsights(companyId);
      final seeded = await _client
          .from('ai_insights')
          .select('*')
          .eq('company_id', companyId)
          .eq('is_dismissed', false)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(seeded);
    }

    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> dismissInsight({
    required String companyId,
    required String insightId,
  }) async {
    requireSession(companyId);
    await _client
        .from('ai_insights')
        .update({'is_dismissed': true})
        .eq('company_id', companyId)
        .eq('id', insightId);
  }

  Future<String> generateAssistantResponse({
    required String companyId,
    required String userPrompt,
  }) async {
    final sanitizedPrompt = AiPermissionGuard.sanitizePrompt(userPrompt);
    final summary = await fetchCompanyBusinessSummary(companyId: companyId);
    return BusinessContextBuilder.buildContextualResponse(
      userPrompt: sanitizedPrompt,
      summary: summary,
    );
  }

  Future<void> _seedInitialInsights(String companyId) async {
    final summary = await fetchCompanyBusinessSummary(companyId: companyId);
    final now = DateTime.now().toIso8601String();

    await _client.from('ai_insights').insert([
      {
        'company_id': companyId,
        'title': 'Outstanding Receivables Opportunity',
        'summary':
            'You have \$${summary.outstandingReceivables.toStringAsFixed(2)} in unpaid customer balances.',
        'category': 'cash_flow',
        'severity': summary.outstandingReceivables > 0 ? 'warning' : 'info',
        'action_label': 'View Invoices',
        'action_target': '/sales/invoices',
        'created_at': now,
        'updated_at': now,
      },
      {
        'company_id': companyId,
        'title': 'Cash & Liquidity Health',
        'summary':
            'Current total cash and bank balance is \$${summary.cashBalance.toStringAsFixed(2)}.',
        'category': 'cash_flow',
        'severity': 'info',
        'action_label': 'Open Finance',
        'action_target': '/finance',
        'created_at': now,
        'updated_at': now,
      },
      {
        'company_id': companyId,
        'title': 'Product Catalog Optimization',
        'summary':
            '${summary.productsCount} active products registered in inventory.',
        'category': 'inventory',
        'severity': 'info',
        'action_label': 'View Products',
        'action_target': '/inventory/products',
        'created_at': now,
        'updated_at': now,
      },
    ]);
  }
}
