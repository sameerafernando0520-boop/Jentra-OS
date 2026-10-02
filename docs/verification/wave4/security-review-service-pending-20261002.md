# Interrupted service security review

The active task returned to Wave 3 before this service proposal was executed.
No service controller, provider migration or installed state was changed by this
review. The controller's read-to-edit hash changed concurrently from
`05B0BC9064947CBE8F04B551B083126759E835584B5F3C2595C3571F2B9244FE`
to `9862DC0C47511B5903267D1B68E5403DD1A6E345FFB34A432BEF2D7A7E444ACF`;
ownership must be refreshed before further edits.

The unexecuted regression proposal is preserved in
`security-review-service-test-20261002.dart.pending`. It needs its paused-key
fixture corrected (`armed = true`, rather than the nonexistent `arm()`), current
source review, RED/GREEN execution and final verification. The isolated
`service_command_acknowledgement.dart` helper is a proposal with no production
callers; its idempotency, encrypted persistence, current-scope recovery and cleanup
failure behavior remain unverified. Contract 61 documents the intended epoch and
durable acknowledgement behavior; this record is not implementation evidence.

Confirmed source observations at the reviewed hash: service connection changes
did not advance the read epoch; `_live` omitted online state; begin/picker/save
continuations did not bind an entry epoch; command success could return before
local acknowledgement when its view lost access. Projects had analogous checks
using `current` alone. Those paths remain with the concurrent Wave 4 owner.

The service and project finance candidates already contain protected labor billing
source/consumption hooks. Actual service stock/equipment providers, integration
verification and native discovery remained development gaps. No fabricated stock
provenance, standalone invoiced flag or provider installation was introduced.
