# Governed reversal of unused opening batches

The next engineering item follows the opening import at `265ea921`. Finance
needs to reverse an unused posted import through independent review and an
explicit compensating posting. The original batch, lines, journals and
open items retain their immutable content and original source keys.

## Workflow and authority

From a posted opening batch, a preparer requests reversal with a reason and
posting date. The date is on or after the opening cutoff, no later than today,
and within an open posting period. A foreign-currency reversal must use the
original fiscal period so the historical FX close remains possible. An independent reviewer approves or rejects
the frozen request. The requester and every original preparer are excluded
from approval. A designated poster then explicitly posts the reversal.
Pending and approved requests may be cancelled before posting. Rejected and
cancelled requests remain terminal records. A new request can be prepared after
one of those terminal outcomes.

Use the existing scoped opening prepare and approve permissions with MFA.
Posting requires the privileged `finance.openings.reverse`
permission. Existing installations retain their opening-import behavior.
The additive backend advertises reversal availability in batch detail, and
the client exposes actions only when that availability and current authority
are established.

## Immutable accounting

Each original line receives an exact opposite control/clearing journal and
counter-open-item on the reversal date. A linked, zero-FX allocation closes the
original and counter-item together. Original amounts, ageing and earlier
as-of results stay intact. The reversal records line-to-line provenance,
counter-item, journal and allocation IDs. Original source identities remain
reserved, including after reversal.

Reject any original allocation history, including a reversed allocation, any
FX-run participation and any active supplier payment claim. Freeze current
period and account revisions at preparation and revalidate them before
approval and posting. Reauthorize after shared locks and before finalization.
Duplicate requests and concurrent posting must preserve one active request
and at most one posted reversal.

Protect generated allocations against the ordinary allocation-reversal APIs.
Protect against a later backdated FX run consuming a corrected original or
counter-item. The ordinary journal engine, original manual-journal control
restriction, residual engine and reporting interfaces continue to govern
accounting effects.

## Public contract

- `prepare_finance_opening_reversal` accepts the ordinary scoped command
  envelope with `{id, document_id, posting_date, reason}` and expected version
  zero. `document_id` identifies the posted original batch.
- `transition_finance_opening_reversal` accepts
  `{document_id, batch_id, action, reason?}` and the reversal request version.
  Actions are approve, reject and cancel.
- `post_finance_opening_reversal` accepts `{document_id, batch_id}` and the
  approved reversal version.
- Command receipts identify the reversal request in `entity.id` and retain
  its original `batch_id`, business scope, status and version.
- Scoped reads expose current reversal state and bounded request history.
  Source detail resolves original and reversal sources with their provenance.

The client stores explicit finance-only reversal verbs in encrypted recovery.
Unknown outcomes retain the original envelope. A denial before replay can
retain an earlier uncertain command, and a confirmed replay refreshes current
batch state before the user can act again.

## Verification

Exercise the public request, approval and posting seams, normal desktop entry
points and encrypted retries. Cover positive and negative AR/AP, exact carrying
amounts, original and reversal-date reporting, source drill-down and credit
exposure. Prove refusal of self-approval, wrong scope, revoked replay, duplicate
or changed replay, stale references, closed dates, prior allocation or FX
history, payment claims, and generic reversal of protected allocations.
A later-row failure must roll back every counter-item, journal, allocation and
receipt. Preserve the existing import regression suite.

Use disposable synthetic records. Hosted rollout, genuine sessions and company
signoff retain the release and operating requirements in the cutover runbook.
