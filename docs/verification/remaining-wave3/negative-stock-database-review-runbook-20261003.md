# Approved negative-stock candidate verification — 2026-10-03

The owner explicitly approved interim issues at the last authoritative positive moving-average cost, blocking unknown cost basis, and linked later-receipt variance corrections. This replaces the earlier missing-policy-selection status for FR-353/EC-323. It authorizes development within the synthetic candidate boundary. Installation, persistent fixtures, independent authenticated sessions, native acceptance and release signoff still require their separate concrete approval bindings.

The historical 45-candidate bodies and their nonlexical dependency order remain immutable. The new `20261003090000_wave3_negative_stock_policy.sql` is ordinal 46 after that full stack. Posted-journal evidence at ordinal 36 still precedes operational evidence at ordinal 37. The additive builder leaves `build_remaining_wave3_candidate.ps1` untouched, inserts the tail before the first pgTAP extension/fixture boundary, and inserts the procurement policy assertions before final immediate constraints. Every composed suite requires strict `finish(true)` and ends in `rollback;`.

The enabled reserve→delivery→receipt policy fixture depends on the procurement fixture. Include `wave3_negative_stock_policy_20261003_test.sql` for procurement. Inventory and receivables compose the same 46 candidate bodies with their existing full assertions and omit the procurement-only policy fixture. Execute all three as fresh strict rollback suites; the historical 991/155/182 counts cannot be relabelled as execution against the new tail. Keep failure iterations and their real outcomes. Counts overlap across suites and do not prove exhaustive scenarios.

Prepare the procurement query from the repository root with a UTF-8 writer that adds no BOM:

```powershell
$candidateSource = 'supabase/migrations/20261003090000_wave3_negative_stock_policy.sql'
$policyAssertions = 'supabase/tests/wave3_negative_stock_policy_20261003_test.sql'
$queryPath = 'docs/verification/remaining-wave3/database-strict-procurement-negative-stock-policy-reviewed-20261003.sql'
if (Test-Path -LiteralPath $queryPath) { throw 'Retain the existing query; choose a new reviewed iteration path.' }
$query = & './supabase/tests/build_negative_stock_policy_candidate_20261003.ps1' -Suite procurement -CandidatePath $candidateSource -AssertionsPath $policyAssertions -IncludeSchemaCapture
[IO.File]::WriteAllText($queryPath, $query, [Text.UTF8Encoding]::new($false))
```

For inventory and receivables, select their suite name and omit `-AssertionsPath`. Write separate additive query files with that same unused iteration tag. Do not overwrite historical strict 45-stack SQL, an already submitted 46-stack query, its corresponding prepared hash manifest, or any execution response. The initial 114-assertion procurement query was submitted before later review corrections were ready; its outcome and exact query stay historical. The reviewed 123-assertion fixture/source are a separate execution revision.

The optional procurement-only `-IncludeSchemaCapture` collects metadata before and after the tail within the same transaction, before synthetic fixtures, and returns both schemas with the actual TAP/read-plan aggregate. Its copied query changes only the metadata label; the historical `capture_wave3_schema.sql` remains untouched. These captures support actual 45→46 function signature/ACL, view and constraint review after successful execution. The prepared query alone is not a schema observation.

The prepared 46-stack manifest/package generator takes the exact composed procurement SQL, the fresh read-only refresh, candidate source and assertion source:

```powershell
node tools/wave3/prepare-negative-stock-database-package-20261003.mjs docs/verification/remaining-wave3/database-strict-procurement-negative-stock-policy-reviewed-20261003.sql docs/verification/remaining-wave3/refresh-policy-resume-20261003.json supabase/migrations/20261003090000_wave3_negative_stock_policy.sql supabase/tests/wave3_negative_stock_policy_20261003_test.sql reviewed
```

This generator sends no SQL. It verifies current HEAD, the refreshed installed versions, all 45 original hashes/order, the tail's unapplied version, exact 46-body composition and strict transaction boundaries. Its package retains the older 45-body compatibility result as historical: zero breaking/eight potential warnings do not imply the new tail has zero additional compatibility risks. Fresh tail/source compatibility review remains explicit.

The added ordinal 46 installation phase follows the original ordinal 45 phase and precedes installed synthetic checks and native acceptance. Its restore/failure procedure inherits the explicit isolated restore/forward-repair boundary; there is no generated destructive downgrade. The selected-policy implementation decision does not approve installation.

Root alone runs the prepared SQL using the existing authorized candidate runner and saves each response to a new execution JSON. An accepted result requires HTTP success, exact query hash, actual TAP successes without any failure or plan mismatch, immediate constraints, strict `finish(true)` and final rollback. The dated matrix records only completed source-matched results. The same policy model/UI/ports must also receive current-source client/domain checks and additive coverage measurement before their development claims are closed.

The builder's offline self-test checks composition and fail-closed guards without sending SQL. It is preparation evidence; it does not verify the accounting implementation. No persistent migration, production/authentication change, native store, acceptance-owned data or sequence, or Git mutation is part of this procedure.
