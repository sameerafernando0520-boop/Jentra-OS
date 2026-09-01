enum DocumentStatus {
  draft,
  submitted,
  approved,
  rejected,
  posted,
  settled,
  fulfilled,
  closed,
  cancelled,
}

/// Canonical transition rules. Posted documents require corrective documents.
abstract final class DocumentLifecycle {
  static const Map<DocumentStatus, Set<DocumentStatus>> _transitions = {
    DocumentStatus.draft: {DocumentStatus.submitted, DocumentStatus.cancelled},
    DocumentStatus.submitted: {
      DocumentStatus.approved,
      DocumentStatus.rejected,
      DocumentStatus.cancelled,
    },
    DocumentStatus.rejected: {DocumentStatus.draft, DocumentStatus.cancelled},
    DocumentStatus.approved: {DocumentStatus.posted, DocumentStatus.cancelled},
    DocumentStatus.posted: {
      DocumentStatus.settled,
      DocumentStatus.fulfilled,
      DocumentStatus.closed,
    },
    DocumentStatus.settled: {DocumentStatus.closed},
    DocumentStatus.fulfilled: {DocumentStatus.closed},
    DocumentStatus.closed: {},
    DocumentStatus.cancelled: {},
  };

  static bool canTransition(DocumentStatus from, DocumentStatus to) =>
      _transitions[from]!.contains(to);

  static bool canEdit(DocumentStatus status) =>
      status == DocumentStatus.draft || status == DocumentStatus.rejected;

  static bool canDelete(DocumentStatus status) => false;

  static bool requiresOnlineConfirmation(DocumentStatus target) =>
      target == DocumentStatus.submitted ||
      target == DocumentStatus.approved ||
      target == DocumentStatus.posted ||
      target == DocumentStatus.settled ||
      target == DocumentStatus.fulfilled ||
      target == DocumentStatus.closed;
}
