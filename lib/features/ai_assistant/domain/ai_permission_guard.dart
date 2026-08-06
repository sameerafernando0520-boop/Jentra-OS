import '../application/ai_failure.dart';

abstract final class AiPermissionGuard {
  /// Verifies that the active session user and target company ID are non-null and valid.
  static void verifyAccess({
    required String? currentUserId,
    required String? companyId,
    required String? targetCompanyId,
  }) {
    if (currentUserId == null || currentUserId.trim().isEmpty) {
      throw const AiFailure('User must be authenticated to use AI Assistant.');
    }

    if (companyId == null || companyId.trim().isEmpty) {
      throw const AiFailure('Select a company before launching AI Assistant.');
    }

    if (targetCompanyId != null && targetCompanyId != companyId) {
      throw const AiFailure(
        'Access denied: AI Assistant cannot access cross-company data.',
      );
    }
  }

  /// Verifies user input query safety (rejects raw SQL injections or malicious instructions).
  static String sanitizePrompt(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const AiFailure('Prompt cannot be empty.');
    }

    final lower = trimmed.toLowerCase();
    if (lower.contains('drop table') ||
        lower.contains('delete from') ||
        lower.contains('select * from pg_') ||
        lower.contains('information_schema')) {
      throw const AiFailure('Direct SQL execution or schema inspection is restricted.');
    }

    return trimmed;
  }
}
