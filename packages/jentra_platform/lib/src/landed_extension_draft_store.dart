import 'package:jentra_domain/landed_extension.dart';
import 'draft_repository.dart';
import 'scoped_command_draft_store.dart';

/// Reuses the established encrypted store and its immutable uncertain envelope.
final class LandedExtensionDraftStore {
  LandedExtensionDraftStore(EncryptedDraftRepository repository)
    : store = ScopedCommandDraftStore(
        repository,
        entityType: 'inventory.landed_extension',
        fields: (_) => const {
          'id',
          'correction_of',
          'document_date',
          'reference',
          'reason',
          'total_amount',
          'basis_mode',
          'offset_account_id',
          'variance_account_id',
          'receipts',
          'basis_hash',
        },
        validate: (_, payload) =>
            LandedExtensionProtocol.validateInput(payload, sealed: true),
        definiteFailures: const {
          'VERSION_CONFLICT',
          'VALIDATION_ERROR',
          'PERMISSION_DENIED',
          'AUTHENTICATION_REQUIRED',
        },
      );
  final ScopedCommandDraftStore store;
}
