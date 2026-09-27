# Dimension compatibility and rollback review — candidate only

No schema installation is authorized. Future coordinated installation requires
review of the ordered 34-candidate stack, current development ledger, current
client and the explicit permissions needed by configured roles.

The dimension candidate adds private forced-RLS masters/events, nullable journal
identity columns, foreign keys/indexes and a source-capture trigger. It wraps the
already versioned manual normalizer and replaces the budget command/variance
builder while preserving existing shared posting, allocation, residual and
open-period helpers. Existing rows receive no invented dimension identity.
Account-only drafts and reports retain their earlier meaning. The new API is
authenticated; management permission is privileged and is not auto-granted.

Journal/budget editing must be coordinated with the new client: an older editor
cannot make an informed decision about governed dimension attribution. Preserve
read access to historical evidence and gate affected edits until the matching
client is present. Branch masters require a matching branch; entity-wide budgets
only accept entity masters. Master changes between save, submission, approval and
posting require a refreshed source basis and independent approval where applicable.

Command failures roll back masters, immutable events, receipts, audit and outbox
together. SQL tests inject a late outbox failure and prove no master/event remains.
Posting, linked reversal and old journal/stock/AP/AR rollback suites run with the
new source guard enabled. Client tests inject a failed encrypted acknowledgement:
the original sealed request remains available for identical retry. A late response
after disposal/offline transition still persists its confirmed identity atomically.

Before any future installation, retain previous function definitions and immutable
candidate hashes as review artifacts. If installed behavior must be withdrawn,
first stop new dimension writes and affected edits through the configured feature
and permission controls. Preserve master/events and nullable ledger attribution
for historical reads and reversals. Do not drop referenced masters, rewrite posted
rows, clear events or remove dimension columns after attributed postings exist.
Choose a reviewed forward repair or compatible client rollback; a destructive
down migration is not a safe rollback of financial history.

The current rollback tests cover synthetic transactional failure and encrypted
client recovery. They do not constitute a live database down-migration rehearsal,
real multi-session contention, native Credential Manager recovery or owner signoff.
