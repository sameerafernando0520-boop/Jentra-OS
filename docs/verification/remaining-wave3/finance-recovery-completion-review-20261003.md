# Wave 3 manual journal and period FX recovery review — 2026-10-03

Reviewed against approved specification 08, contracts 32/35 and the 2026-10-02
security recovery review. Initial coordinator refresh: clean HEAD
`7c08ea890746b1914c2f6e825523482a9146114c`; development ledger/API/helper refresh
is recorded separately by the coordinator. Initial ownership covered the two
finance controllers and the dedicated recovery regression file. The coordinator
later assigned both finance screens and an isolated dialog regression file after
independent review identified root-level dialogs outside the workspace guard.

## Interrupted-run evidence reconciled

The historical `security-review-finance-recovery-red-20261002.log` records one
pass and fifteen failures. The subsequent
`security-review-finance-recovery-green-fixture-fail-20261002.log` records 31
passes and six timeouts: the paused-key fixtures reused a cipher that had already
memoized its encryption key. The later
`security-review-finance-recovery-green-20261002.log` exists and ends with 37
passes. This last log is historical, not proof that the expanded current test
file was executed. The original controller hashes match the 2026-10-02 source
capture; the expanded test requires a fresh run.

Fresh-cipher fixtures preserve the synthetic key store and encrypted SQLite
database, then construct a new `DraftCipher`/repository/store and controller.
Pausing that cipher's first key read models genuine recovery. It neither resets
the stored key nor edits production key handling. The manual-journal fixtures
already contained this correction; this review extends the same real boundary
to period FX initialization and disposal.

## Current review and corrections

Existing controller corrections implement entry-epoch publication, chained-read
guards, reconnect/denial reauthorization, sealed-action gateway routing and fixed
`LOCAL_STORAGE_FULL` guidance after durable confirmation. Tests now cover disposal
as well as disconnect/reconnect; already-dispatched confirmations must clear the
exact sealed request durably while refusing obsolete evidence publication or
optional reads. Every allowlisted current denial after confirmation is followed
by a fresh authorized read, proving restoration without a second command.

An additional approved capability gap was found in period FX: dispatch chooses
the gateway from the sealed action but the former capability check used the later
caller action. The regression preserves an uncertain `soft_lock`, removes the
close capability, then calls `execute('post')`. That must retain the identical
envelope without dispatch, even when FX permission is present. Restoring the
close capability permits the identical retry. Contract 35 was clarified before
the minimal controller change; the capability is now derived from the stored
payload when a pending command exists.

The fresh RED also exposed a stale manual-journal form after an already-dispatched
posting was durably acknowledged during disconnect, reconnect or disposal. The
pre-confirmation approved amounts were retained in memory even though the server
had posted them. Contract 32 was clarified before correction. Disposal clears the
form/local reference; acknowledgement under an obsolete epoch clears the same
document's stale form while its encrypted, input-only confirmed recovery remains.
A fresh permitted read is still required to restore posted evidence.

## Verification status

The coordinator's serialized combined RED
[`finance-root-red-20261003.log`](../../../build/remaining-wave3/finance-root-red-20261003.log)
records **70 passes / 8 failures**. Four failures belong to this finance review:
the sealed-action capability regression and the three stale acknowledged-journal
forms. The other four belong to the coordinator's landed-value review and are
not attributed here. All fresh-cipher recovery and current-denial cases completed
without the historical paused-key timeouts.

The serialized corrected combined run
[`recovery-focused-green-20261003.log`](../../../build/remaining-wave3/recovery-focused-green-20261003.log)
records **218 passes / 3 failures**. The finance recovery regression, manual
journal workspace and period FX workspace all passed. The three remaining
failures concern procurement order reconnect/disposal and purchase-return
disposal; this combined run is not globally GREEN. Both the fresh-cipher cases
and the four finance RED regressions passed. The scoped run also generated
[`recovery-focused-green-20261003.info`](../../../build/remaining-wave3/recovery-focused-green-20261003.info).
The subsequent `recovery-focused-final-20261003.log` completed with 221 passes
and no failures. This includes corrected procurement cases as well as finance.
Analyzer verification is recorded separately by the coordinator. This document
does not count the historical 37-run as current proof. Formatted source hashes
captured before execution and rechecked unchanged after the run:

| File | SHA-256 |
| --- | --- |
| `manual_journal_controller.dart` | `283f4cb60b0ec749f4b29850fb81a9eaca2f4082bc155a68d40a7a0fb6b4a947` |
| `period_fx_controller.dart` | `ee90486e67637fa8fab8d18f5cc02bb33514d4d190f972957241d038b76b39fe` |
| `security_review_finance_recovery_test.dart` | `d290a469348c42603537cae93b7576e0b27d25fa426d59f39a6c8b00ad3b39f6` |

## Root-level dialog follow-up under verification

Independent source review found that journal selector rows and amount-bearing
posting confirmations use ordinary root `showDialog`; the containing workspace
access guard does not rebuild those routes. Selector return and confirmation
dispatch also lacked their original access epoch. Period FX confirmation could
similarly survive reconnect and fresh verification. Twelve new widget regressions
in `finance_dialog_access_20261003_test.dart` exercise actual selector/confirmation
dialogs after disconnect, reconnect plus reauthorization, definite denial plus
reauthorization and disposal. Both contracts were clarified before correction.
The actual
[`dialogs-chain-red-20261003.log`](../../../build/remaining-wave3/dialogs-chain-red-20261003.log)
records eight passes and 43 failures across finance/inventory/scoped-dialog
regressions; all twelve finance widget cases failed on retained old dialog
content. None failed compilation. Both screens now use the existing scoped
dialog helper, and callers recheck the original epoch after the returned result.
Period FX implements `OperationalReadAccess` and notifies listeners before
disposal so surviving root overlays hide their contents.
`dialogs-chain-green-20261003.log` actually completed with 64 passes and four
reservation golden failures: all twelve finance widget cases passed. This is
scoped finance GREEN evidence, not a globally passing combined run. The manual
picker selected-result braces lint was subsequently corrected without behavior
changes; final analyzer evidence remains separately recorded. Earlier recovery
passing evidence does not establish these later dialog regressions.

The same independent review subsequently assigned bank confirmation to this
review. Contract 34 was clarified before correction; four actual widget cases in
`bank_dialog_access_20261003_test.dart` failed in the actual separate
`bank-dialog-red-20261003.log` (zero passes / four failures). The corrected
`bank-dialog-green-20261003.log` completed with four passes and no failures.
The existing scoped helper now owns the root confirmation display epoch, and
the caller rechecks the originating controller/epoch before command dispatch.
No bank
accounting, command envelope, selected exact amounts or native store is changed.

## Evidence boundary

All fixtures use encrypted in-memory SQLite and synthetic keys/gateways. No
persistent migration, authentication setting, acceptance executable, acceptance
record, sequence or Credential Manager store is changed. Exact money arithmetic,
immutable correction basis, original command envelope and the authoritative
server accounting engine remain unchanged. Installation, authenticated native
restart, multi-session contention/load, visual acceptance and owner signoff remain
separate gates.

## Governed dimension selector follow-up

Seven actual root-selector widget cases failed in
`sales-dimension-dialog-red-20261003.log`: loaded row access restoration,
post-pop provider changes and origin disposal. The combined run had two passes
and ten failures across dimensions and sales. Contract 46 was clarified before
correction. A display access token retains the selector origin across provider
changes, disposal and returned results; reconnect requires a fresh selector.
The compatibility fixture that previously revived an old selector now closes
and opens a fresh one before choosing. Approved goldens and comparators are
untouched. Five additional regressions for retained loading/error values after
opening and delayed obsolete denial actually passed the partially corrected
source in `dimension-ar-expanded-red-20261003.log` (all twelve dimension tests
passed). These additional cases are passing protection, not newly reproduced
failures. The four additional initial-entry loading/error tests genuinely failed in
`dimension-entry-red-ar-green-20261003.log` (combined 16 passes / four failures;
all four failures were dimensions). The correction rejects retained allowed
values during loading/error at entry and validates each late read/denial against
its original display epoch. The button remains an ordinary StatefulWidget so
existing static journal/budget render fixtures do not require a ProviderScope
until the user opens a governed selector. Final dimension GREEN is recorded below.

The [current owned-source snapshot](finance-owned-source-capture-20261003.json)
records the later screen/interface/test source hashes; the recovery-only hash
table above remains explicitly historical. A snapshot does not establish that
the corresponding source was executed.

## Retained connectivity provider corrections

The first two serialized provider attempts did not establish product RED:
one had fixture compilation errors, and the next attempted a common dynamic
provider subscription that failed inside Riverpod before assertions. The fixture
was corrected to listen/read each actual typed provider, preserve constant
capability and gateway identities across complete override updates, and assert
that connectivity changes retain the same controller. In
`agent-providers-quote-red-root-green-20261003.log`, all twelve finance cases
compiled and genuinely failed `controller.online` (expected false, actual true)
for initial and active loading/error states with an explicitly retained previous
online value. Contracts 32/34/35 were clarified before the minimal correction.
The three providers now reject loading/error in both initial connectivity and
its listener. Existing controller disconnection behavior invalidates read epochs
while preserving encrypted inputs and original sealed requests. The completed matching-source finance GREEN is recorded below.

Sixteen additional test-only FX governance cases exercise immutable reversal
sources, reopen approval sources, date/rate validation before preparation,
blocked acknowledgements, version-conflict refresh without command replay,
exact bounded source pagination, stale reconnect drilldown and leave persistence.
Their completed execution is recorded below.

The first `finance-root-completion-green-20261003.log` attempt completed all
new finance-provider twelve, FX governance sixteen and dimension sixteen cases
successfully (along with twelve coordinator cases and four AR cases: sixty new
passing cases). It subsequently reached 73 passes / one legacy picker fixture
failure and was cancelled during fixture stream teardown. It is an interrupted
combined run, not global GREEN or a completed coverage input. The initial legacy
selector fixture assumed lazy asynchronous providers were ready before its first
open; the strict entry guard correctly refused unverified initial connectivity.
Both interactive dimension fixtures now await their actual container capability
and connectivity futures before the first tap. The reconnect fixture explicitly
unmounts before stream closure, uses broadcast events, retains paused-read and
fresh-selector assertions, and the clear-selection fixture retains its true/null
callback checks. Static approved goldens and product guards were not weakened.
This interrupted attempt was superseded by the completed run below; analyzer
evidence remains separate.

## Completed current finance verification

The isolated `dimension-interactive-fixture-green-20261003.log` completed two
passes with no failure, verifying the repaired async readiness and stream
teardown. The completed `finance-procurement-root-completed-green-20261003.log`
then recorded 118 passes / one failure. All twelve actual finance provider
regressions, sixteen additional FX governance cases, sixteen dimension dialog
cases and twenty-one existing financial-dimension workspace cases passed.
The latter include six preserved catalog/budget/journal goldens and both actual
interactive selectors. The sole combined failure concerns the coordinator's
supplier-payment precision/replacement fixture; it is outside the owned finance
scope. This completed run is scoped finance GREEN, not a globally passing
combined run. Its completed coverage file is eligible for source checking;
coverage from the two interrupted attempts is excluded.

Every owned product file matches the coordinator's execution fingerprint
`client-sources-finance-procurement-root-final-green-20261003.json`; current
owned test and contract hashes are in `finance-owned-source-capture-20261003.json`.
The final interactive fixture hash is
`1ef862288917f38e82d4148948ff3ffe2cb54f9328ebb391bf2392eaf9cbff9e`.
Current scoped analyzer and full-suite results are recorded separately when
completed; this document does not infer them from test passing.

## Scoped analyzer follow-up

The actual direct analyzer log `finance-direct-final-analyze-20261003.log`
reported nineteen issues: one unused dimension test import, eight missing
statement braces, and ten intentional internal-member uses of Riverpod's
`copyWithPrevious` in retained-state fixtures. The import and braces were fixed;
the only product edit encloses an existing early-return condition in braces.
Each deliberate retained-state construction now has a narrow line annotation
and comment explaining that the fixture models Riverpod cached data retained
while loading or failing refresh. These annotations acknowledge the internal
API dependence solely in tests. No global analyzer configuration or production
ignore was introduced. The actual tests assert that previous allowed/online
values remain present while loading/error flags are set, preserving the
reproduced failure boundary. The final source snapshot supersedes earlier
formatting-only hashes; clean analyzer/full-suite evidence requires its own run.

The subsequent actual whole-desktop `desktop-final-analyze-20261003.log`
completed with `No issues found!`, after the nineteen owned finance findings
were corrected. Current owned source hashes rechecked unchanged against the
final snapshot. This analyzer result establishes static diagnostics only;
release, visual acceptance and native/installed evidence remain separate.

## Completed frozen full desktop suite and legacy heading correction

`desktop-final-20261003.log` actually completed with 1,567 passes and 89 failures.
The independent `desktop-final-failure-classification-20261003.json` separates
85 golden failures, three protected Wave 4 non-pixel failures and one Wave 3
legacy quotation fixture mismatch. Compared with the earlier 90-failure run,
both reservation expectation failures resolved; the same 85 golden cases and
three protected payroll/service failures remain. The new quotation fixture
expected the former `Business scope or access changed` heading, while the reused
current helper displays `Reference access changed`. Its preceding assertion
that the private decision disappeared had passed; its subsequent no-command
assertion was not reached. Existing new confirmation cases separately verify
no obsolete dispatch. After the completed full-run marker, only that heading
expectation was corrected, retaining both privacy and no-command assertions.
Before/after file hashes are recorded in
`quotation-legacy-heading-fixture-20261003.json`; actual exact-case rerun remains
pending. The completed full run still has 89 recorded failures and is not
retroactively called GREEN. The newly prepared later-microtask continuation
fixture has not yet executed and is not included in full-suite evidence.

The preserved 85 golden failures include 81 Wave 3 control-family cases and
four Wave 4 payroll/service cases. The controlled SDK primitive probe diagnoses
rounded-border raster differences; known shell permission/navigation source
changes remain a distinct cause. No approved golden or comparator changed.
This evidence does not establish Wave 3 release completion, visual acceptance,
production installation, authenticated native recovery, load or owner signoff.
