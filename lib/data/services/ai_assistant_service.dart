/// Server-mediated AI contract.
///
/// The eventual implementation must call a Supabase Edge Function so provider
/// API keys never enter Flutter or the browser. Every request explicitly carries
/// a company scope to preserve tenant isolation.
abstract interface class AiAssistantService {
  Future<String> ask({
    required String companyId,
    required String prompt,
    String? conversationId,
  });
}
