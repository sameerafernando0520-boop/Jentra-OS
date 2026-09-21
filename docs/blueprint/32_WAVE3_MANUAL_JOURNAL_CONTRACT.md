# Manual journals — FR-362–366 / AC-316

Candidate development contract, 2026-09-21. Manual journals reuse
`finance.flow_post_journal`, open-period locking, document sequences, workflow
approval snapshots, command receipts, audit and outbox. No alternate ledger engine.

## Document and commands

`finance.manual_journals` is a scoped draft/approval aggregate with immutable posted
history. It contains a description, reason, posting date, currency/rate context,
2–200 exact lines, dimensions, attachment references, approval snapshot and the
resulting journal ID. Lines have stable IDs, active posting-account references,
description, optional cost-center/project labels and one positive debit or credit.
Labels are descriptive dimensions, not new master-data entities. Scope is inherited
from the document; clients cannot inject tenant/entity/branch dimensions.

Save, submit, recall, cancel, approve/reject and post are authenticated versioned
commands. Save recomputes every total and conversion. Submission requires a configured
approval workflow with at least one matching step. Creator, latest preparer and
submitter cannot approve; the configured role and MFA requirement are checked at
each decision. Poster must differ from preparer and submitter. No configuration or
sequence is installed automatically and no acceptance-owned setup is changed.

Draft input amounts are decimal strings with at most six places. Both transaction
and base totals must balance exactly. FX uses an active entity rate, frozen at save;
separate cumulative rounding of debit and credit sides to six places preserves the
balanced converted total. A line rounding to zero fails explicitly. Changed rate,
account, attachment or base currency context invalidates posting and requires recall,
save and fresh approval. Open period is checked again at posting.

Manual postings cannot use accounts configured as AR/AP control or accounts already
represented by open items, because an arbitrary journal cannot create/reopen the
corresponding subledger items. Corrections to those accounts use governed source
commands. Other control-account journals remain visible as reconciliation differences.

Attachments are selected from existing completed private legal-entity or current-branch
files. Selection requires file-view permission and matching tenant/scope; checks repeat
at submit and post. Frozen references include checksum and name. Uploading a new file
continues through the existing shared attachment workflow. This slice adds no storage
policy or shared attachment helper changes.

## Reversal and source evidence

A posted manual journal is reversed by a new linked draft, independently submitted,
approved and posted. Its accounts, dimensions, currencies and amounts negate the exact
original snapshot; date and reason are new. One posted reversal per original is
enforced under an original-document lock. Competing reversal drafts may exist, but
only one can post. Reversals of reversals are rejected; a new corrected journal may
be prepared separately. Original posted history is never edited. Posting and its
receipt/audit/outbox either all succeed or all roll back.

Scoped paged register/detail APIs expose original/reversal links, frozen source-line
IDs and actual posted ledger lines. Native `/finance/journals` supplies a complete
editor, named account/rate/file selectors, approval actions, source evidence and
linked reversal preparation. Encrypted `manual-journal-editor` drafts retain byte-
identical uncertain retries, block edits while pending and hide data after explicit
permission rejection. Registers/options page 50 rows; detail is capped at 200 lines
and 20 attachments. Installation, native acceptance, real contention/load and owner
signoff remain separate gates.
