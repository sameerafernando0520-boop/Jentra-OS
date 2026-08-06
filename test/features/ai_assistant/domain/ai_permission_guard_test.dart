import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_os/features/ai_assistant/application/ai_failure.dart';
import 'package:jentra_os/features/ai_assistant/domain/ai_permission_guard.dart';

void main() {
  group('AiPermissionGuard', () {
    test('unauthenticated user throws AiFailure', () {
      expect(
        () => AiPermissionGuard.verifyAccess(
          currentUserId: null,
          companyId: 'comp-1',
          targetCompanyId: 'comp-1',
        ),
        throwsA(isA<AiFailure>()),
      );
    });

    test('missing selected company ID throws AiFailure', () {
      expect(
        () => AiPermissionGuard.verifyAccess(
          currentUserId: 'user-1',
          companyId: null,
          targetCompanyId: null,
        ),
        throwsA(isA<AiFailure>()),
      );
    });

    test('cross-company access attempt throws AiFailure', () {
      expect(
        () => AiPermissionGuard.verifyAccess(
          currentUserId: 'user-1',
          companyId: 'comp-1',
          targetCompanyId: 'comp-2',
        ),
        throwsA(isA<AiFailure>()),
      );
    });

    test('same company access passes successfully', () {
      expect(
        () => AiPermissionGuard.verifyAccess(
          currentUserId: 'user-1',
          companyId: 'comp-1',
          targetCompanyId: 'comp-1',
        ),
        returnsNormally,
      );
    });

    test('sanitizePrompt rejects SQL injection attempts', () {
      expect(
        () => AiPermissionGuard.sanitizePrompt('DROP TABLE companies;'),
        throwsA(isA<AiFailure>()),
      );
      expect(
        () => AiPermissionGuard.sanitizePrompt('DELETE FROM sales_documents'),
        throwsA(isA<AiFailure>()),
      );
      expect(
        AiPermissionGuard.sanitizePrompt('What is my total revenue?'),
        equals('What is my total revenue?'),
      );
    });
  });
}
