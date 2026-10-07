# Internal asset equipment Spec review

2026-10-05. Root reviews the service owner's contract 66, SQL source, typed
gateway/model and native controller/workspace against FR-431–435, AC-401/414/415
and EC-402/413/415/416. Root implemented only shared application provider/router
wiring for this vertical. Source review and synthetic checks are distinct from
installation, authenticated runtime and real contention.

The adapter binds an actual scoped active asset register row, exact selected
version/digest and immutable operational identity. Linking creates neither value
nor stock/accounting effects. It exposes location/custodian/ownership rather than
private book/cost fields. Authoritative asset row locks serialize future dispatch
and maintenance with asset transfers/disposal; harmless depreciation changes
preserve the original association. Internal tickets have no invented customer,
internal labor is nonbillable, and completion requires a reasoned exception.

Three actionable integration findings were sent to the owner:

- Mixed customer/internal directories initially raised asset-access denial for
  the whole page when a service operator lacked asset authority. The source now
  filters unauthorized internal rows before pagination, preserving customer rows.
  The actual 171-assertion final rollback verifies the mixed-directory case and
  closes this source finding.
- The current eligibility guard initially ran before original service replay,
  blocking recovery after transfer/disposal. The source now rechecks current
  service/asset authority, then returns the exact historical actor receipt before
  eligibility checks for a new effect. A post-transfer occurrence replay
  regression passes in the actual 171-assertion final rollback; this source
  finding is closed.
- That earlier replay return bypasses the base command envelope checks. A null or
  future issued time with otherwise matching original identifiers/body could
  return a receipt the base command rejects. The owner must preserve the base
  validation contract before that return. Both null/future cases pass against a
  real original receipt in the final 171-assertion rollback; this source finding
  is closed. Earlier failed/results remain preserved.

The native form uses named source choices and scoped encrypted original requests,
access/form epochs, immutable source review and receipt reconciliation. Source,
gateway, recovery, native/rendered tests, independent Standards review and the
current whole-app build remain pending while the owner finishes this vertical.

Final SQL binding: migration SHA256
`D4723BD8025E44CCDC651E6FEAB21E8AE939F4E2C850A14357453BE3E24CA77E`;
the exact executed query, actual result and all dependency/fixture/builder hashes
are saved in `asset-milestone-sql-final-hashes-20261005.json`. Real internal
dispatch/labor/completion, maintenance, depreciation, transfer and disposal paths
are exercised. These are rolled-back business/security checks, not overlapping
session or authenticated owner acceptance.
