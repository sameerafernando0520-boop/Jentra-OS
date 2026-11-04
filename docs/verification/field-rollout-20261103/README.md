# Sales rollout continuation — November 3, 2026

Candidate implementation and verification record. The selected provider is **verified-domain Resend**. No sender/domain/mailbox credentials, persistent migration installation, worker/client deployment, real email delivery or company signoff is claimed.

## Results

| Verification | Observed result | Limit |
| --- | --- | --- |
| Six-candidate isolated database composition | **222 checks**, **24 rollback assertions**, all passed | PGlite 0.5.12/PostgreSQL 18, repository prefix plus workforce/private HR baseline; synthetic Auth/MFA and provider replies |
| Hosted full-schema rehearsal | Original **three** candidates composed on actual PostgreSQL **17.6**, then removed; original functions/ACLs/policies/permissions/entitlements restored | 130 migrations at observed trial; no genuine Auth flow, persistent installation or new three-candidate coverage |
| Expanded hosted full-schema rehearsal | All **six** candidates composed and rolled back; `candidate_removed` and `original_state_restored` both **true** | Explicit new owner approval; exact SQL SHA below, PostgreSQL 17/ledger guards passed; no genuine Auth/MFA, persistent installation, business document or email |
| Sales app | **67 tests passed** | Full Sales suite, including 12 new delivery controller/layout/privacy checks; widget sizes are not physical devices |
| Desktop company workflow | **65 tests passed** | Scoped seven-file cohort; explicit delivery issuance, recovery, credit review and scope-loss behavior |
| Platform gateways/recovery | **24 tests passed** | Six-file cohort, including purpose-specific facades, scoped encryption and late actor denial |
| Default-disabled navigation | **1 test passed** | Both recipient/company destinations remain hidden by default |
| Lead-to-cash domain | **10 tests passed** | Existing exact quantity/credit/reservation contracts |
| Worker and runner safety | **14 tests passed** | Real HTTP adapter with simulated provider; frozen retry/key separation; new and legacy Supabase headers; preparation refuses execution/target overrides |
| Static checks | 24 Dart files: no analyzer issues, no formatting changes; Deno entry check passed | Deno `checkJs=false`; JS behavior is covered by Node tests |
| Local web builds | Sales and desktop release bundles compiled with all three candidate flags, CSP/local resources, optimization level 1 | No Wasm build, deployment, signing or live acceptance |
| Current hosted public GET | Sales root/version **200**, privacy headers present; worker and six recipient RPC probes **404** | Existing preview only; no installed/deployed recipient POST or email evidence |
| Local browser preview | Attempt failed: connected IAB could not reach Windows loopback | No real browser fragment-scrubbing/render result claimed; temporary server stopped |

The database cases exercise the actual canonical order confirmation, two **non-stocked** partial delivery postings, exact received/refused/short responses, conflicting/original retry behavior, MFA/actor/scope denial and independent states. They do not establish real stocked-company setup, load/contention, external inbox delivery or genuine authentication.

## Evidence and reproducibility

- [Machine record and hashes](verification.json), [database cases/rollback/source hashes](postgres-result.json).
- [Hosted three-candidate result](hosted-rehearsal.json), [exact executed SQL](full-schema-rollback.sql), [visible SQL Editor evidence](hosted-rehearsal.png). Approved trial SQL SHA-256: `06953135b63b9ea19ae9d5ff482a65509ed4908a62cadb327296118d2d4b8e71`.
- [Hosted six-candidate result](hosted-six-rehearsal.json), [complete result screenshot](hosted-six-rehearsal.png). Executed after the owner's separate approval; the full editor buffer matched SQL SHA-256 `cca874a3461a73933e4081b228f9ce97d8a714ac655d87318c8d183df74fd3db`. Observed at **12:46:13 Asia/Colombo on November 3** (`07:16:13 UTC`). All in-transaction assertions and restoration checks passed before outer ROLLBACK; installation and mail enablement remained false.
- [Current hosted GET observations](hosted-http.json). Source: public GET only; keys, response bodies and private addresses are not recorded.
- [Prepared six-candidate review](review/rollout-plan.json), [rollback-only SQL](review/six-candidate-rollback.sql), [concrete rollout/rollback runbook](review/rollout-runbook.md), [per-organization acceptance template](review/organization-acceptance-template.json).
- Logs: [Sales](sales-tests.log), [desktop](desktop-tests.log), [platform](platform-tests.log), [default navigation](default-navigation.log), [domain](domain-tests.log), [worker/runner](node-tests.log), [analysis](analyze.log), [format](format.log), [Deno](deno-check.log), [Sales build](sales-web-build.log), [desktop build](desktop-web-build.log).

From the repository root, the pinned isolated runtime is already present:

```powershell
node supabase/candidates/run-field-rollout-test.mjs --run-isolated
node --test workers/field-sales/mail_worker.test.mjs supabase/candidates/tests/field_rollout_runner.test.mjs
node tools/field-sales/prepare-rollout-review.mjs --prepare-only
node tools/field-sales/check-hosted-readiness.mjs --read-only
node tools/field-sales/record-verification.mjs --record-local
```

The last command checks source consistency and existing test/build logs before recording artifacts. It runs no test or hosted action itself. Flutter jobs use the installed SDK, `--no-pub`, serialized test concurrency and the three candidate defines; default navigation is run without them. The reviewed source belongs to a dirty shared checkout; unrelated AI, MFA and assurance work was preserved, not staged or committed.

The initial three-candidate hosted rehearsal had an approval rejection under the user's no-install boundary; explicit owner approval resolved it. A subsequent proposed console “Run without RLS” was rejected. The safer script places RLS on its temporary snapshot inside the transaction and passed. A console auto-fix appended after ROLLBACK failed with a missing temporary table and is not an accepted result. Only the final source-bound successful trial above is counted.

## Remaining gates

**Email-link activation:** actual sender domain/address and approved pilot mailbox; verified Resend DNS and tracking policy; server secrets; explicit deployment/enablement; real link and code receipt; hosted POST, forwarded-link/scanner/cache/log/abuse checks. Provider acceptance and mailbox delivery remain separate observations.

**Company acceptance:** the full-schema DDL/ACL rehearsal of **all six** exact candidates has passed. Remaining: coordinated installation/client authorization and capability review; genuine independent sessions/MFA/revocation; actual stocked-company workflows and contention; named physical devices/browser/privacy/accessibility evidence; each organization's sales/warehouse/finance/customer/owner pilot signoff.

**Separate commercial gates:** company discount approval, customer order acceptance, company confirmation/credit/stock progression, delivery quantity acknowledgement, invoicing and payment retain distinct permissions, commands and evidence. Neither an email nor a delivery response advances a company order or ledger automatically.

Migration installation/deployment remain outside the user's existing authorization. The six-candidate trial used a separate explicit rollback-only approval; the earlier three-candidate approval was not reused. The prepared plan retains its pre-execution authorization snapshot; `hosted-six-rehearsal.json` and `verification.json` record the subsequent approved execution and result.
