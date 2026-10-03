# Procurement retained connectivity review — 2026-10-03

All eight actual procurement controller providers interpret connection state using
`AsyncValue.value == ConnectivityState.online` at initial construction and listener
notification. Riverpod can retain the previous online data inside loading/error
values. Those states are not freshly verified connectivity. Contract 56 requires
originating access epochs and cleared server evidence across connection changes;
it contains no exception authorizing retained connectivity while verification is
loading or unavailable. The actual app connection provider uses a current lookup
and service stream; their loading/error states can reach these consumers.

`procurement_connectivity_provider_20261003_test.dart` uses all eight actual
providers and their real encrypted draft repositories. Its 32 cases combine
loading/error values copied from verified online data with initial construction
or notification of an existing online controller. They explicitly establish that
the unverified value still contains `online`, then require closed server access,
cleared cached register rows, no transport commands, and unchanged exact local
inputs both in memory and encrypted storage. Fresh verified reconnection must not
revive a prior captured read epoch. Purchase return has no public dialog-read
interface, so its checks use actual connectivity, cleared rows and retained
inputs rather than inventing a public epoch API.

The first combined run `connection-providers-red-20261003.log` did not compile
this fixture: the Riverpod 3 public exports relocated `ProviderListenable`, and
the gateway cast promoted the dynamic fake to its narrower transport interface.
The next `connection-providers-corrected-red-20261003.log` compiled but each of
the 32 procurement cases stopped at Riverpod's internal listener setup before
the intended access assertion. These are fixture failures, **not behavioral
RED evidence**. Each log and pre-run capture is preserved.

The final fixture uses an explicit concrete generic controller type for each
actual provider subscription, with common dynamic assertions only after reading
the resulting subscription. Its
[concrete pre-RED capture](procurement-connectivity-provider-concrete-pre-red-20261003.json)
records the unchanged eight product controllers, fixture and contract before the
root-serialized behavioral rerun.

The actual behavioral RED is
[agent-providers-quote-red-root-green-20261003.log](../../../build/remaining-wave3/agent-providers-quote-red-root-green-20261003.log).
All **32 procurement cases executed and failed the intended `online` assertion**
with expected false and actual true. The combined job also executed twelve finance
cases, then was stopped during separate inventory fixture timeouts. It is not a
completed whole-suite result; these 32 observed procurement outcomes are distinct
from the earlier fixture failures.

Contract 56 was clarified before product correction. The shared
`procurementVerifiedOnline` predicate requires neither loading nor error state and
an online value. All eight initial provider reads and connectivity listeners use
that predicate, with their existing `setOnline` epoch clearing and encrypted
recovery logic intact. There is no change to command/sealing/retry implementation,
shared app providers, permission definitions or approved golden baselines. Direct
formatting of all eight controllers and scoped diff checks passed. The
[pre-GREEN capture](procurement-connectivity-provider-pre-green-20261003.json)
records exact corrected product/fixture/contract sources.

The completed
[combined GREEN](../../../build/remaining-wave3/finance-procurement-root-completed-green-20261003.log)
recorded **118 passes and one fixture failure**. All **32 procurement provider
regressions passed**, covering all eight initial and subsequent loading/error
states, cleared server evidence, exact encrypted inputs and fresh verified
reconnection. A comparison against all ten files in the procurement pre-GREEN
manifest found **zero mismatches**. Its other passing cases belong to finance,
AR and AP lifecycle checks and must not be added as independent suite totals.
The one failure was the additional AP editor fixture's assumption that edit()
reloads the durable draft into `c.local`; it saves the draft without reloading
that field. The fixture now inspects the actual encrypted repository, keeping the
original command-blocking and version-retention assertions. No product change was
needed.

The later whole-desktop analyzer reported fixture-only warnings: an unused
Riverpod miscellaneous import, redundant gateway casts and the intentionally
package-internal `copyWithPrevious` calls constructing real retained-value
regression states; it also requested braces around one conditional. The unused
import/casts and braces were corrected, and only those two intentional calls
carry precise explanatory lint ignores. No assertion or product behavior was
relaxed. The [lint-corrected source capture](procurement-connectivity-provider-lint-corrected-20261003.json)
preserves this final fixture revision separately. Current full-suite/analyzer
verification remains root-owned and pending.

This review and its synthetic tests do not establish installed authentication,
real independent sessions, native process recovery, load/p95, visual acceptance
or owner signoff. No Git or database write/installation was performed.
