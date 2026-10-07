# Protected expense evidence Spec review

2026-10-05. Independent root review of the corrections owner's separate private
expense vertical and its finance integration, against FR-401–405/426/439,
AC-401/404/411/419 and EC-402/411/415. Root implemented shared application wiring
and candidate function configuration, not this vertical's business logic.

The candidate separates private documents, tickets, retention policies and worker
leases from generic attachments and private HR. Frozen financial proofs contain
only immutable document identity/version/digest. Lifecycle versions and subsequent
retirement/purge do not overwrite that original basis. Existing proof history
remains authorized and readable after purge; a new decision requires active
verified content. Financial terminal state, the chosen retention interval, legal
holds and a valid leased physical deletion govern cleanup.

Trusted byte delivery binds user, scope, project, expense, document and operation.
Upload has a 10 MiB streamed bound, no upsert, exact size/hash and storage readback
before activation. Download/export recheck current human authority after storage
read. Worker batch size is at most 50; physical removal and absent-object readback
precede metadata completion. Errors reflect safe codes without private paths or
caller values. User and worker entrypoints use distinct authentication modes.

Review found three boundary defects and sent them to the owner. Current provider
source `990077DBED0E07E74EB593E77A51CC7BA0B62B5AB50C29700A39D4F235D67ABA`
addresses them: an issued trusted ticket rechecks current tenant/entity/branch
state; entity-wide retention policy creation/receipt requires entity-wide
authority; and native recovery separately discovers the policy's null-project
namespace instead of losing an uncertain request inside the expense namespace.
The final actual 180-assertion finance/evidence query verifies the current SQL
security/proof boundaries. Actual final 16 native tests cover policy lost response,
expiry and recreated controller discovery, closing the namespace recovery finding.

Private local recovery encrypts metadata with a fixed 24-hour expiry and seals its
minimal uncertain receipt atomically before dispatch. File bytes, filenames,
local paths and content URLs are not persisted. Retry first checks the original
actor-owned receipt; an expired unresolved receipt prevents a new policy request.
Scoped epochs guard file picking, reads, authorization and plaintext responses.
Known server confirmation precedes optional local cleanup and subsequent reads.

Final owned checks pass domain 8, platform/gateway/recovery/reader 20 and native
16, with both inspected previews and actual Deno entry checks. The 27-source
binding is `expense-evidence-source-hashes-final-20261006.json`. Native tests also
caught and repaired action-specific policy receipt parsing; finance review caught
and repaired the growing-file memory bound. Reader regressions and scoped private
image cache eviction are covered in the final current tests.

Independent Standards closure and the whole-app build remain open. Both
functions and SQL are unapplied candidates;
this review neither deploys them nor activates a worker. Actual storage probe,
authenticated byte access/export/purge, restart, contention/load and owner
acceptance remain separate required evidence.
