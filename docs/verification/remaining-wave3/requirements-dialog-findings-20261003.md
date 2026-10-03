# Independent current-source confirmation review — 2026-10-03

The controller corrections preserve durable acknowledgement, original sealed
commands and current typed denial. The independent review found additional
presentation gaps in the screens invoking those controllers. An operation epoch
captured when a controller method begins does not bind a confirmation opened
earlier. These findings implement the approved current-scope/recovery behavior;
they add no posting engine, accounting policy or new requirement.

| Current source at review | Confirmed source finding | Required correction and ownership |
|---|---|---|
| `manual_journal_screen.dart:51` and `_JournalPicker:627` | Picker owns cached account/rate/tax/attachment rows, does not subscribe to controller access changes and accepts a result using only `!locked`. Rows remain in its root dialog after disconnect, denial or disposal; reconnect can make an old selection usable. | Finance review agent: use current read-access dialog/epoch for display, reads and returned choices; suppress obsolete denial. |
| `manual_journal_screen.dart:65` | Plain root posting dialog captures private total/currency/date; disconnect does not hide it. Returned confirmation invokes `act` without its originating epoch. | Finance review agent: hide obsolete private display and reject the old result even after fresh authorization. |
| `period_fx_screen.dart:42` | Plain period/FX root confirmation invokes `execute` after only `mounted`. Disconnect/reconnect and new authorization can revive that earlier confirmation. | Finance review agent: bind original epoch and controller, retaining sealed pending commands. |
| `landed_extension_screen.dart:48` | Plain root confirmation captures held/transit/consumed monetary preview. Disconnect clears controller preview but keeps dialog amounts visible; later confirmation can post a replacement current preview after reconnect/recalculation. | Requirements/database agent: current read-access interface/dialog and origin checks before dispatch. |
| `stock_count_screen.dart:56` | Recall/cancel/reject reason dialog uses no origin epoch. After reconnect the earlier result enters a fresh controller operation. | Requirements/database agent: retain exact reason locally, invalidate old dialog and returned result. Existing current picker boundary remains. |
| `disposition_screen.dart:90` | Same unbound recall/cancel/reject reason dialog. | Requirements/database agent: same source/epoch boundary; existing serial/reference pickers remain. |
| `control_reconciliation_screen.dart:52` | Allocation reversal confirmation uses no original epoch. A refreshed correction after reconnect can be sent by an old confirmation. Controller disposal also did not clear its current report/correction display or notify the surviving dialog. | Requirements/database agent: read-access interface, clear server evidence on disposal and current origin-bound confirmation. Original encrypted correction remains. |
| `landed_extension_controller.dart:167` | Initialization retains an entry epoch but checks it only at the end. An obsolete encrypted recovery or receipt read can start account/posted reads in a replacement epoch after reconnect, or after disposal. | Requirements/database agent: check the entry epoch after recovery and every awaited read; do not dispatch subsequent obsolete reads. |

These findings were recorded before correction. Test execution remains
separate: `inventory_control_dialog_access_20261003_test.dart` covers
20 actual-root-dialog widget scenarios, comprising four modules across
disconnect/reconnect/current denial/disposal and four fresh positive controls.
Three additional paused-receipt initialization scenarios require no subsequent
account/posted read after disconnect, reconnect or disposal; 23 cases total.
The synthetic encrypted SQLite fixtures use existing public fake gateways. No
database/HTTP, native credential, persistent fixture or acceptance action occurs.
The serialized actual `dialogs-chain-red-20261003.log` compiled these 23 cases;
the stale dialog and chained-read scenarios failed while all four permitted
positive controls passed. After the contract-first correction, all 23 passed in
`dialogs-chain-green-20261003.log`. That batch also included other owned/root
cases: 64 passes and four existing reservation pixel golden failures remain
separate. Own product hashes match
`requirements-dialog-green-ready-sources-20261003.json`; subsequent brace-only
test formatting is included in final run capture. This is synthetic widget and
controller evidence, not native authentication, installation or visual signoff.

The next sales correction is bounded by this pre-implementation clarification:
all seven existing quotation/order scope guards permanently invalidate their
originating dialog after scope or capability loss, including refresh/loading;
fresh workspace authorization permits a newly opened dialog. A credit dialog
also clears its server exposure display permanently after disconnect. Its caller
retains the originating controller, scope, capabilities and preview across the
credit read and root-route return, rejecting any intervening invalidation before
dispatch. Local encrypted discard/recovery remains usable offline; this is not a
new restriction on draft composition. Named server commands retain locked credit
recalculation, immutable envelopes and current authorization. Five prepared
`sales_dialog_access_20261003_test.dart` cases cover same-capability restoration,
disconnect/reconnect private evidence, offline local positive behavior and one
fresh permitted command. Actual `sales-dimension-dialog-red-20261003.log`
compiled the five sales cases: three intended negatives failed and the two
positive controls passed. The three-path sales correction is now frozen at
`requirements-sales-green-ready-sources-20261003.json` pending serialized GREEN.

The expanded nine-case sales test then reproduced four additional real gaps in
the first correction: scope loss/restoration before a frame, capability loading
and restoration before a frame, rapid disconnect/reconnect before a frame, and
originating route disposal with a surviving credit root dialog. Actual
`sales-rapid-dialog-red-20261003.log` recorded five passes/four intended failures.
The revised three-path correction records sticky invalidation on provider
notifications and uses a caller-owned token to clear surviving private credit
content on origin disposal. Logical token validity changes immediately; listener
notification during a framework build is deferred safely to the frame boundary.
Its current hashes are separately preserved in
`requirements-sales-rapid-green-ready-sources-20261003.json`; serialized GREEN and
final whole-client measurement remain required. Offline local positive behavior
and one current credit command remain part of the same test.

The quotation reference picker is the next confirmed source gap. It retains
server rows while temporarily inactive and displays them again after restoring
the original capability/scope/connection set. Its helper returns the root result
without rechecking the originating access epoch. The approved current-display
clarification requires notification-driven permanent invalidation of that root
picker after access loss, strict nonloading/error-free capability and connection
state, and an epoch check after the root route returns. Existing scoped gateway
parameters, bounded pagination, exact rate values and local draft semantics stay
unchanged. Eight actual-helper regressions are prepared before product changes:
five display/access transitions, two post-pop changes and one current positive
selection. Source correction awaits actual RED. Two additional credit connection
loading/error regressions examine retained AsyncValue data before any stricter
connection check is introduced.

Current controller-only correction review found no change to accounting arithmetic,
immutable open-item/journal lineage or command identities. Manual confirmation uses
the returned input-only form before optional reads; stale completion clears its
obsolete same-document presentation. Period retry now checks the capability of the
sealed action and selects its matching gateway. Purchase-return disposal advances
its epoch and clears register/eligible source evidence before notifying listeners.
Single-receipt landed optional denial retains typed guidance after clearing current
server evidence. These source observations do not substitute for GREEN regression.

Operational attachment link/rejection dialogs use `showOperationalReadDialog`,
capture the original controller/epoch, reject late native file/link responses and
hide denied signed URLs. Count/disposition reference/serial pickers already use the
same wrapper plus returned-result checks. Governed export, frozen financial/report
workspaces and contextual navigation source paths are reviewed separately from
installation, real authenticated access and owner/native acceptance.

The expanded sales nine-case notification/origin tests subsequently passed. Two
additional credit connection cases then genuinely failed while old online data
was retained in loading/error AsyncValues. The credit dialog and originating
caller now require settled, error-free online observations; their eleven-case
current-source GREEN remains a separate serialized check.

`quote-inventory-final-red-20261003.log` compiled all sixteen owned inventory
provider scenarios: four modules, loading/error, initial/notification state.
Every case failed the intended unavailable-state assertion (`false` expected,
`true` actual). Contracts 33/51 were clarified before changing the four factories
and listeners to reject uncertain observations, including retained online data.
The original encrypted-input sentinel remains a regression assertion. Product
sources are frozen at
`requirements-inventory-provider-green-ready-sources-20261003.json` pending GREEN.

That same run observed six quotation picker failures and two permitted behaviors,
but fixture edits during startup require a frozen source-matched repeat before
helper correction. Earlier timeout/cancelled and fixture compile logs establish
no behavior result. The three quotation confirmation cases failed on absent theme
tokens, including their positive control, and do not establish an authorization
gap. Their corrected fixture supplies the real Jentra theme and explicit provider
subscriptions before the next run; quotation screen behavior remains unchanged.

The frozen `quotation-stable-retry-red-20261003.log` then source-matched all eight
quotation picker cases: six intended stale/revive/post-pop failures, immediate
disconnect hiding and one fresh successful selection. The minimal correction
uses the existing OperationalReadAccess dialog wrapper and a caller-owned epoch
bound to actual provider notifications, origin route lifetime, strict capability
and connection observations, and post-pop validation. All three subscriptions
are closed after return. Current picker/test hashes are preserved in
`requirements-quotation-picker-green-ready-sources-20261003.json` pending GREEN.
The same run's three confirmation failures were fixture finder failures; actual
`Confirm reject` selection and its required reason-entry rebuild are corrected
before the next run, with quotation screen product source still unchanged.

The clean themed/font-loaded confirmation regression then passed the capability
loss and current positive controls while the connection root-pop case dispatched
one command despite its lost originating authority. Before correction, the public
clarification binds server action dialogs to scope, settled capabilities and
settled online connection for their complete lifetime and after route return.
Local discard/conflict continuations bind scope/capability lifetime without
adding an online requirement to local resolution. Existing document/version/slot
checks, immutable commands and encrypted recovery semantics remain in force.

The picker clarification additionally requires a current typed authorization
denial to invalidate its access epoch and remove retryable private presentation.
A caller widget removed while its parent route survives must notify the same
existing access token from its state disposal; route completion alone is
insufficient. Two actual widget regressions are prepared before those additional
picker/caller changes. This does not introduce a new domain or posting protocol.

The current sixteen inventory provider cases and eleven credit/scope cases all
passed in `resumed-inventory-payment-green-20261003.log` (33 total, including six
payment cases). The clean three confirmation regressions then passed alongside
the eleven sales cases (14 total). Current denial/origin-unmount picker regressions
both failed before their correction. Callers now retain one existing access token
per dialog, invalidate it during their actual State disposal, and dispose it only
after the picker finally closes. A current typed denial invalidates only after
the original request-generation/access check. No frame polling is used.

Final frozen-source quotation execution passed all 24 cases, including both
denial/origin-unmount regressions. The paired capture is
`client-sources-quotation-final-green-20261003.json`. Whole desktop direct analyzer
completed with zero issues. This supersedes earlier pending/failure statements
only for these actual captured synthetic checks; final whole-client execution,
source-checked coverage, isolated compilation, rendered visual/native acceptance,
installed roles, target-scale p95 and owner signoff remain separate evidence.
