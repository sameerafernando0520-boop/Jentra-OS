import 'validation.dart';

final class AttachmentFilePolicy {
  const AttachmentFilePolicy._();

  static const int maximumBytes = 25 * 1024 * 1024;
  static const Duration signedReadLifetime = Duration(minutes: 15);
  static const Set<String> allowedMimeTypes = {
    'application/pdf',
    'image/png',
    'image/jpeg',
    'text/csv',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  };

  static ValidationResult validate({
    required String fileName,
    required String mimeType,
    required int byteSize,
  }) {
    final issues = <ValidationIssue>[];
    final trimmed = fileName.trim();
    if (trimmed.isEmpty ||
        trimmed.contains('..') ||
        trimmed.contains('/') ||
        trimmed.contains(r'\') ||
        trimmed.runes.any((rune) => rune < 32 || rune == 127)) {
      issues.add(
        const ValidationIssue(
          field: 'file_name',
          message: 'Choose a safe file name without path characters.',
        ),
      );
    }
    if (!allowedMimeTypes.contains(mimeType)) {
      issues.add(
        const ValidationIssue(
          field: 'mime_type',
          message: 'This file type is not allowed.',
        ),
      );
    }
    if (byteSize < 1 || byteSize > maximumBytes) {
      issues.add(
        const ValidationIssue(
          field: 'byte_size',
          message: 'File size must be from 1 byte to 25 MiB.',
        ),
      );
    }
    return ValidationResult(issues);
  }
}
