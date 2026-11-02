# Company and access verification

28 October 2026. This record covers the additive administration candidate in the
original workspace at base commit `678584047d7f4a5fd0e50192b2d3ea576f33b1c7`.
The administration changes remain workspace work. The separate PR 16 repair at
`451168e` and its green CI do not certify these new changes.

| Check | Result | Evidence and limit |
| --- | --- | --- |
| Desktop suite and existing goldens | 2,343 passed | Final source after dialog/session/recovery hardening; Windows automated tests |
| New desktop controller and invitation tests | 21 passed | Included in the full desktop count; not an additional 21 |
| New domain contracts | 10 passed | Exact input/receipt binding and immutable snapshots |
| New platform adapters and encrypted recovery | 11 passed | Controlled RPC transport and real SQLite close/reopen; concurrent seal protection |
| Workspace analyzer | No issues | Desktop, domain and platform packages |
| Formatting | 880 files checked, zero changes | All apps and packages |
| Candidate runner | 5 passed | Hosted/linked flags and unsafe composition refused; `--check` does not execute PostgreSQL |
| PostgreSQL behavioral probe | 73 passed | Actual foundation/candidate SQL in in-memory PGlite 0.5.12 / PostgreSQL 18 with real pgcrypto/btree_gist |
| Exact pgTAP harness | 31 passed | Pinned official pgTAP 1.3.4 SQL in the same isolated engine; all candidate/users/companies/receipts rolled back |
| Prior diagnostic artifacts | 460 unchanged | Compared before/after hashes; no approved baseline replacement |
| Administration Word addendum | Two pages rendered and reviewed | Native Microsoft Word PDF rendered to page PNGs; original ten-page manual preserved |

[The behavioral JSON](postgres-result.json) lists each check and source hashes.
[The pgTAP JSON](pgtap-result.json) and [TAP output](pgtap-output.tap) record the
actual harness results. The final manifest binds evidence/logs to source hashes.
There is no production completeness percentage in this record.

## Database boundary

The probes simulate Auth users/JWT functions and, for pgTAP, an empty migration
ledger. They execute actual Wave 1 migrations, the exact Wave 2 business-schema
prefix before Storage provider setup, actual command helpers and the candidate.
The pgTAP runner substitutes only the extension-load statement with the pinned
upstream SQL already loaded in that engine; no assertions are replaced. It checks
the real TAP plan/count and refuses any failed assertion.

The checks include live scoped delegation, recent MFA, plan/company/seat caps,
version conflicts, exact replay, unavailable/foreign scope, canonical verified
email, expired/revoked invitations and inactive staff's retained roles. Legacy
token APIs are exercised directly, including owner/unavailable-role delegation,
stale MFA, unverified email, revoked inviter, exhausted seats and attempted
reactivation. Valid old-client acceptance and first-workspace bootstrap still
work. Original API/core bodies and execution grants remain unchanged.

These are not the full Supabase Auth/Storage stack, current hosted acceptance,
independent connections/contention/load, actual employee delivery or a rollout.
The new local/CI Supabase harness step has not executed on that stack. No
migration was installed, no sender deployed/activated and no real company data
was read or deleted. The target and restored management access remain external
gates before inventory or company cleanup.

## Reproduce locally

The ordinary runner has only `--check` and `--run-local`; see
[the runbook](../../development/company-access-administration-candidate.md).
For these additional in-memory probes, the build-only runtime was installed with
`npm install --prefix build/launch-validation-runtime --ignore-scripts --no-audit
--no-fund --save-exact @electric-sql/pglite@0.5.12`. This is a verification
dependency, not a Supabase migration or production application dependency.

The pgTAP probe uses the official
[v1.3.4 release archive](https://github.com/theory/pgtap/releases/tag/v1.3.4).
Save `pgTAP-1.3.4.zip` under `build/`, then copy only the archive entry
`pgTAP-1.3.4/sql/pgtap.sql.in` to `build/pgtap-1.3.4.sql.in` (do not extract
untrusted archive paths). The runner checks these SHA-256 values before SQL:

```text
archive   5de16455e3e29898813f05cc9f396a31f878309a94d8adb34e80f423a5841736
template  383ecd73edfd1c7ed5f3b835134ee1fe74e201ee31599346c92ea029b65dcdce
```

From the repository root:

```powershell
node docs/verification/company-access-20261028/run-postgres.mjs
node docs/verification/company-access-20261028/run-pgtap-postgres.mjs
```

Both instantiate an in-memory engine, accept no hosted connection and close the
engine after execution. Keep the original candidate and harness assertions when
reproducing. Use each Flutter package/app directory for its tests so native
assets resolve correctly.

## Document and diagnostic provenance

The addendum builder uses the bundled workspace Python/python-docx runtime. The
packaged renderer was attempted and reported missing LibreOffice; native Word
then exported the actual DOCX without changing it, and PDFium rendered both
pages for visual inspection. Those internal render files remain under `build/`.
The existing Word manual is unchanged and linked with the new addendum.

Earlier test diagnostics are preserved under `build/`: the initial root-directory
platform run lacked native assets; rerunning in the owning package passed. A
new widget transport gate initially waited in Flutter's fake async zone; moving
that controlled gate to the real async zone resolved the test timeout without
weakening its late-result/recovery assertion. The final full suite passed after
these changes. No golden was regenerated to hide a failure.

## Remaining release work

The administration candidate needs the full isolated Supabase regression gate,
reviewed installation, independent contention, old-client retry checks and
authenticated native/company acceptance. Retain the additive invitation and
membership guards during a UI rollback; removing them reopens known bypasses.
The [runbook](../../development/company-access-administration-candidate.md)
describes the separate database recovery controls.

The separate Jentra Sales app, governed commercial integration and verified email
confirmation implementation remain next work. The owner's discount/email
decisions are recorded in the Sales blueprint. Hosted AI, employee rollout/push,
statutory payroll, production restoration/monitoring, signing/distribution and
company acceptance retain their individual gates. None is certified by these
administration tests.
