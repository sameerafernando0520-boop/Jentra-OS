import 'package:cryptography/cryptography.dart';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/jentra_domain.dart' show DomainError;

/// Uses the same cryptography package as encrypted drafts and governed exports.
final class ProcessMetricSha256Hasher implements ProcessMetricHasher {
  @override
  Future<String> sha256(List<int> bytes) async {
    if (bytes.length > ProcessMetricDefinition.maxSerializedBytes) {
      throw const DomainError(
        code: 'LIMIT_EXCEEDED',
        message: 'The process source manifest exceeds an allowed bound.',
      );
    }
    if (bytes.any((value) => value < 0 || value > 255)) {
      throw const DomainError(
        code: 'VALIDATION_ERROR',
        message: 'The process source manifest contains invalid bytes.',
      );
    }
    final hash = await Sha256().hash(List<int>.unmodifiable(bytes));
    return hash.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
