# Procurement root-dialog security review — 2026-10-03

Read current source for all eight procurement workspaces, shared reference
picker, conflict comparison and existing source/attachment navigation paths.
This review covers approved FR-348–349, FR-384, FR-395, AC-322–323 and NFR-313
under public contracts 33 and 56. It is distinct from the earlier controller
operation/sealing review and does not establish installed/native acceptance.

## Confirmed source findings before correction

1. `sourcing_screen.dart` calls the shared `sourcingReason` using a plain root
   `showDialog`, with a title containing the private selected supplier name. The
   modal does not listen to its originating controller or epoch, so disconnect,
   reconnect, denial or disposal leaves that supplier evidence and Confirm action
   visible. The same helper handles bill, order and supplier-payment decisions;
   requisition and receipt reversals use their own unbound dialogs.
2. The AP allocation-history reversal callback captures an original allocation
   map, awaits that unbound reason dialog, then calls `reverseAllocation`.
   Its controller accepts the supplied allocation into an encrypted correction
   draft after reconnect because it checks live connectivity/flags but neither
   the original read epoch nor current denial. The root dialog's result must be
   rejected if the originating epoch changed, even during route-pop completion.
3. `pickSourcingReference` checks the epoch when displaying rows and when a row
   is tapped, but returns the root `showDialog` future directly. A connection or
   denial change synchronously during Navigator pop can occur before the caller's
   awaited continuation; the old row is then accepted into an unchanged local
   editor or source-derived draft in the new connection epoch. Its result needs
   an original-epoch check after awaiting route completion.

The conflict-comparison reload already checks the originating epoch after
comparison and before/after encrypted discard; it is not the same defect. Shared
picker reads already check controller/request epochs for loading, paging and
typed denial. Local-only discard dialogs contain local recovery inputs rather
than server authority; their established offline behavior must be preserved.
Purchase-return sources are inline and checked by its controller, with disposal
already corrected and verified separately.

## Reproduction and verification preparation

`procurement_dialog_access_20261003_test.dart` adds ten synthetic cases:
four actual sourcing-workspace supplier-reason dialogs across offline/reconnect/
denial/disposal; three actual reference results with an observer changing access
between pop and awaited continuation; and two AP allocation-confirmation results
with reconnect/denial at pop. The latter checks no new in-memory or encrypted draft
and no gateway command. A separate direct controller check denies access after
capturing an allocation and requires correction preparation to retain no draft.
Existing approved goldens are preserved.

The [serialized combined RED](../../../build/remaining-wave3/dialogs-chain-red-20261003.log)
compiled and recorded eight passes and 43 failures across finance, inventory read
chains and procurement. All **ten procurement cases failed for their intended
security assertions**: four retained private supplier titles, three obsolete
reference results, two stale AP drafts after confirmation and one denied AP draft
preparation. These counts belong to one combined run and must not be added as
independent suite totals. The
[pre-RED source manifest](procurement-dialog-pre-red-sources-20261003.json)
binds the reviewed eight screens, picker, AP controller, test and contract.
Contract 56 was clarified before
correction to include server-derived confirmation dialogs and post-pop results.
No draft is to be discarded by a stale result; exact saved inputs and original
sealed command identities must remain recoverable.

The correction uses the existing scoped operational dialog for the shared
supplier/reason helper and the separate requisition/receipt dialogs. Supplier
selection, bill decisions, purchase-order revisions and supplier-payment decisions
pass their actual controller. Every result checks the originating epoch after
awaiting the root route. The custom reference picker similarly checks its original
epoch and mounting after route completion. AP reversal preparation rejects current
denial and an optional supplied read epoch; its screen passes the captured epoch.
The other seven controllers, local-only offline discard dialogs and durable sealed
retry inputs retain their existing behavior. Direct Dart formatting and owned
`git diff --check` pass. The
[pre-GREEN manifest](procurement-dialog-pre-green-sources-20261003.json)
records formatted source before the root's serialized verification.

The [serialized combined GREEN](../../../build/remaining-wave3/dialogs-chain-green-20261003.log)
completed with **64 passes and four failures**, all four failures being existing
reservation golden comparisons. **All ten procurement regressions passed**; the
combined run also contains finance and inventory checks, so its total is not an
additional procurement suite. A post-run comparison found zero mismatches across
the procurement pre-GREEN source manifest. Approved golden baselines were not
changed.

The root's whole-desktop analyzer reported one owned informational lint: the
test observer list used a conditional element instead of the Dart null-aware
element. Only that fixture expression was changed to `[?observer]` and formatted;
the separate [lint-corrected source manifest](procurement-dialog-lint-corrected-sources-20261003.json)
retains this later revision. Product source remains identical to the GREEN
capture. A final full execution/analyzer must establish evidence for the latest
combined fixture and product revision; the earlier GREEN is not relabelled.

The additional `supplier_payment_lifecycle_20261003_test.dart` is prepared for
root-serialized execution. Its actual workspace actions cover submit and
independent approval, payment-reference cancellation, uncertain posting followed
by fresh encrypted recovery and byte-identical retry, three reasoned decisions,
and disabled own-prepared approval. Its synthetic receipt ledger proves the
client retries the original command; it does not prove installed posting or
database idempotency. Its [pre-run source capture](procurement-payment-lifecycle-pre-run-20261003.json)
records the exact sources before execution. The
[serialized five-case lifecycle run](../../../build/remaining-wave3/payment-lifecycle-20261003.log)
passes **5/5**, including the fresh cipher/repository/controller recovery path.
The later sixth case adds an actual existing-proposal editor workflow: invalid
precision sends no command, changing the bank clears old selections and due-item
evidence, removing/replacing a payable item retains exact decimal input, and an
encrypted restart preserves expected version 5 before save. Its
[separate six-case capture](procurement-payment-lifecycle-six-case-pre-run-20261003.json)
preserves the earlier execution pairing rather than overwriting it. Verification
of this expanded fixture belongs to the forthcoming final run. The completed
[finance/procurement combined run](../../../build/remaining-wave3/finance-procurement-root-completed-green-20261003.log)
passes the original five lifecycle cases and all 32 provider cases, with its one
failure confined to the sixth editor fixture: `edit()` durably saves its local
draft without reloading `c.local`, so a non-null assertion on that field was
invalid. The fixture now loads the actual encrypted draft and requires it to be
present, unsealed and version 5 after rejected precision. The
[corrected six-case capture](procurement-payment-lifecycle-six-case-fixture-corrected-pre-run-20261003.json)
is kept separately; product source is unchanged.

The corrected six-case fixture then passed **6/6** in
[resumed-inventory-payment-green-20261003.log](../../../build/remaining-wave3/resumed-inventory-payment-green-20261003.log).
That completed run has **33 passes**: sixteen inventory, six AP lifecycle and
eleven sales cases. This is one combined result; historical counts are not summed.
The AP editor executes all its assertions, including rejected precision leaving
the durable draft unsealed, replacement-item recovery through a fresh encrypted
repository/controller, exact `0.000001` payload and original expected version 5.
The other five cases verify independent approval, reasoned decisions and exact
sealed retry after a lost posting reply. A post-run comparison against the six
owned files in the corrected lifecycle capture finds **zero mismatches**. The
root also captured the complete source set before execution in
[client-sources-resumed-inventory-payment-green-20261003.json](client-sources-resumed-inventory-payment-green-20261003.json).
Current full-suite and coverage evidence remain separately pending.

No Git staging/commit/push, database write/installation, authentication change,
acceptance record, sequence, executable or Credential Manager operation occurred.
Read-only source review and synthetic widget cases remain distinct from installed
RLS, native authentication, real sessions/load and owner signoff.
