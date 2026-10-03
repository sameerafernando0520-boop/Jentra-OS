# Procurement independent recovery review — 2026-10-03

Reviewed current source against the approved Wave 3 specification, AC-309–312,
AC-322–323, FR-348–349, FR-384, FR-395, NFR-313 and public contracts 33 and 56.
The root refresh reports HEAD `7c08ea890746b1914c2f6e825523482a9146114c`;
source hashes and execution logs separately identify the code actually verified.
Concurrent Wave 4/5 and stock-opening acceptance ownership are preserved.

## Independent observations

All eight controllers bind the outer operation catch to the epoch captured
before asynchronous work. Obsolete/disposed errors do not assign current public
guidance or revoke replacement access. Current typed access denials clear their
register and selected evidence. Requisition clears unit/base-currency references;
sourcing clears base currency; purchase return clears its eligible-source rows,
cursor and source kind; supplier payment clears statement, eligibility, item and
allocation evidence. The encrypted original request remains governed by the
existing durable failure classification, independently of presentation.

The optional register reads follow durable command acknowledgement. Their
original-epoch guards preserve each of `PERMISSION_DENIED`, `ACCESS_DENIED`,
`MFA_REQUIRED` and `AUTHENTICATION_REQUIRED` as actionable denial guidance;
non-access failures use fixed confirmation/refresh guidance. They cannot recreate
a known confirmed command. No arithmetic, posting mappings, immutable open items,
allocation reversal basis or receipt semantics were changed in this review.

Purchase-return disposal was the one remaining confirmed source defect: at review
start it set `_disposed` without advancing its epoch, clearing server evidence or
notifying an already-visible workspace. The existing two-test regression checks
both encrypted uncertain-input retention and immediate removal of rendered
private register/source rows. The
[fixture-corrected behavioral RED](../../../build/remaining-wave3/purchase-return-disposal-red-fixture-corrected-20261003.log)
records zero passes and two failures: one genuine visible-workspace disposal
failure, plus one pre-command fixture failure caused by an omitted supplier
reference. Only the former is a behavioral RED. Contract 56 was clarified before the product
change. Disposal now advances the epoch, clears server evidence and notifies the
visible workspace before releasing listeners, matching the seven other modules.
The encrypted input and sealed request are not discarded. The corrected combined
run now passes both disposal cases; the links below bind that claim to executed
source rather than the earlier historical checkpoint.

## Verification improvements

The sourcing sealing helper now calls the actual workspace `saveServer()` entry
point, which captures the operation epoch and serializes work through `run`.
Calling its inner `send()` directly skipped that boundary and weakened the
historical synthetic evidence. The prepared regression keeps all eight modules
and disconnect/reconnect/dispose paths using the real entry points.

`procurement_inflight_recovery_20261003_test.dart` adds 16 adversarial cases. Each
holds an already transmitted command, changes the access connection or disposes
its controller, then releases an uncertain transport failure. It verifies obsolete
presentation is suppressed while the encrypted failure and exact sealed envelope
survive. A genuinely new repository/cipher/controller then reads the preserved
input, retries the identical command and durably clears its acknowledgement.
These complement the earlier encryption-before-dispatch cases; the scenarios are
not interchangeable.

The existing optional-read regression additionally checks eight non-access
failures: private diagnostics cannot become presentation, current access remains
available, durable pending state is clear and another Retry action sends no new
command. All approved goldens are preserved.

## Execution and release boundary

The root serialized desktop Flutter execution and captured sources before each
run. The [corrected combined focused run](../../../build/remaining-wave3/recovery-focused-final-20261003.log)
passes **221/221** in 57 seconds, including the **114 procurement cases**: 64
failure/optional-read, 24 sealing-before-dispatch, 16 transmitted-uncertainty,
eight access/recovery and two disposal checks. Its other cases belong to finance,
AR, landed-value and reservation recovery; these are one combined run rather than
additional independent totals. Both disposal checks and all eight genuine fresh
encrypted retry paths pass. A post-run SHA-256 comparison finds **zero mismatches
across the 12 owned executable source/test files**. Wider functional workspace
checks, full coverage and whole analysis are root-owned verification and remain
separate until their execution evidence is available.

The later [root-dialog review](procurement-dialog-review-20261003.md) adds a
minimal AP allocation preparation denial/original-epoch guard and scoped screen
confirmations. Accordingly, the 114-case source snapshot above is execution
evidence for its captured controller revision; verification against the later
combined source belongs to the root's final compatibility/full-suite run. Earlier
source hashes are preserved rather than relabelled as the later revision.

The subsequent [retained-connectivity provider review](procurement-connectivity-provider-review-20261003.md)
corrects initial/listener interpretation of loading/error async values retaining
previous online data in all eight providers. It changes only the verified-online
predicate, with command, encrypted input and retry implementation intact. The
earlier 114-case controller snapshot remains accurately paired with its original
execution; compatibility against this later provider revision requires the root's
current full verification.

The first RED attempt stopped at fixture compilation: two existing return
gateway method signatures incorrectly placed a comma after their named-parameter
brace. This was a fixture defect, not a behavioral RED. Both signatures were
corrected; direct Dart formatting with `--suppress-analytics` passed before the
product-unchanged behavioral rerun. The
[pre-RED owned manifest](procurement-owned-pre-red-sources-20261003.json) captures
all eight controllers and four focused test files at that stage.

All five edited Dart files passed the direct formatter with
`--suppress-analytics` after correction. The
[pre-GREEN owned manifest](procurement-owned-pre-green-sources-20261003.json)
records the exact corrected eight-controller/four-test source set before the
serialized focused run. Documentation-only changes after this capture do not
change the executable source fingerprints.

The first combined focused run recorded 218 passes and three fixture failures
([log](../../../build/remaining-wave3/recovery-focused-green-20261003.log)). The
rendered disposal test passed. The retained-input return fixture omitted the
required supplier reference and therefore never sent its intended uncertain
command. The new order transport fake inherited a private response implementation
that bypassed the holding method, so its two dispatch waits timed out. These
preconditions were corrected without a further product change. Both order command
methods now enter the deliberately held transport. The
[corrected pre-GREEN manifest](procurement-owned-pre-green-fixture-corrected-sources-20261003.json)
retains a separate source capture for the rerun; earlier logs/manifests are preserved.

No staging, commit, push, persistent database installation, production write,
authentication change, acceptance executable, acceptance record, sequence or
Credential Manager operation was performed by this owner. Synthetic encrypted
SQLite/transport cases cannot establish installed RLS, independent real sessions,
native process restart, actual populated load/p95, owner visual acceptance or
signoff. Negative-stock valuation remains the explicit owner-policy decision.
