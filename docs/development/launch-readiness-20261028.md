# Jentra OS launch readiness — 28 October 2026

**The OS is not yet certified for general company launch.** The current workspace includes all 43 advertised desktop navigation routes, the major business modules, reviewed intelligence workflows and Jentra Employee. The [capability review](../user-guide/feature-completeness.md) identifies functional gaps and the separate [route inventory](../user-guide/feature-inventory.csv) records source inclusion. A route or passing test does not establish installed production behavior.

**Sales continuation, 30 October:** the separate adaptive Jentra Sales client now
implements an explicit sample-data preview for phone, tablet and desktop browser
workflows. The reviewed source passes 19 tests and clean analysis. See the
[Sales release record](jentra-sales-release-20261030.md) for exact artifact and
Hosting evidence. This does not install portfolio authorization, governed live
order commands or customer email confirmation, or award full S1 acceptance.

**Administration continuation, 28 October:** the Company & access candidate now
implements extra company/branch creation and permitted edits, custom roles,
scoped staff assignments, suspension/revocation/restore and verified-email
invitation acceptance. See [the candidate runbook](company-access-administration-candidate.md)
and [administrator instructions](../user-guide/company-access-administration.md).
The real PostgreSQL probe passed 73 rollback-safe checks, and the exact pgTAP
harness passed 31 assertions in that engine with pinned upstream pgTAP SQL and
simulated Auth/ledger support. The full Supabase step is prepared but has not run
locally or on GitHub. The final desktop suite passed 2,343 tests after dialog and
invitation recovery hardening. Original goldens and all 460 existing diagnostic
artifacts were preserved. The
[source-matched verification record](../verification/company-access-20261028/README.md)
states the limits and exact evidence. Additive core-table guards close legacy
invitation bypasses while preserving original function bodies and grants.

The separately requested PR 16 CI repair was committed/pushed as `451168e` in
its isolated worktree. All ten PR/push checks passed, including the 77-assertion
HR candidate suite. That result applies to the narrow repaired PR, not the
unpublished administration work or the earlier broad workspace commit `6785840`.
The historical audit below remains a dated checkpoint. This continuation makes
no hosted installation, deployment, cleanup or production acceptance claim.

The owner and staff instructions are available as a [Word manual](<../user-guide/Jentra OS Company Setup and Operating Guide.docx>) and [editable operating guide](../user-guide/README.md). The ten-page Word manual was rendered with native Microsoft Word and visually reviewed. It covers real company setup, individual access, opening records, business workflows, employee services, analytics/AI, troubleshooting and the pilot checklist. It contains no real company identity or private credentials.

## Current functional gaps

| Priority | Gap | Required next outcome |
| --- | --- | --- |
| Company pilot | General company/branch administration candidate now implemented | Complete the full isolated database gate, reviewed installation and native acceptance against the actual company structure |
| Company pilot | General staff invitation, role and membership administration candidate now implemented | Review rollout; verify individual accounts, branch-scoped roles, independent approvers and uncertain-result recovery |
| Employee pilot | Candidate self service, HR cases/documents and notification producers | Complete the isolated database regression gate and reviewed backend rollout; activate push separately only when authorized |
| AI pilot | Hosted model readiness and actual trusted usage are not freshly verified | Prove a reviewed provider response, source authorization, quota accounting, separate human approval/execution and recovery |
| Mobile sales | Standalone Jentra Sales preview now implemented; live governed selling and verified confirmations remain open | Complete portfolio authorization, canonical commercial commands and independent customer/company/delivery evidence under the separate blueprint; no sending activated |
| Real payroll or payments | Synthetic payroll and payment evidence do not establish statutory payroll or real payment integration | Qualified finance/payroll review, configuration and end-to-end acceptance |
| General release | Production target, restore drill, monitoring, signed distribution, independent load, native accessibility and business signoff | Complete Wave 6 evidence against the exact release and selected staging/production projects |

Shared setup includes job registers for imports/exports. Actual import, export, external API, webhook and payment providers need their own installed and delivered evidence. The full approved requirements and earlier acceptance matrices remain authoritative; this audit awards no new acceptance and claims no completeness percentage.

## AI intelligence scope

**Analytics** includes Process, Pipeline, Historical pipeline, Financial ratios, Cash scenarios, Integrations and Governed exports. **Jentra Control** includes reviewed suggestions/proposals, trusted usage and separately authorized operator health. `apps/jentra_desktop/lib/main.dart` wires the actual Supabase gateways, including `SupabaseReviewedModelGateway`; the null defaults in feature providers are overridden when a connected client exists.

The reviewed model client calls `wave5-runtime/model/suggestion`. The optional server adapter uses OpenAI only with an explicitly reviewed provider/model configuration. The current retrieval contract is a redacted numeric pipeline projection. The versioned proposal policy permits `analytics.freeze_pipeline.v1`; a model suggestion does not grant authority to execute it. Separate human approval with MFA and execution-time source/scope/expiry/quota checks remain required. General AI chat and arbitrary autonomous financial/HR commands are not implemented features.

Current worker tests use controlled transports and providers. Their results do not prove actual hosted delivery, model quality, billable usage or live operator authority. Older Wave 5 deployment/acceptance records remain dated historical evidence and were not relabeled as current.

**31 October AI/integrations continuation:** canonical worker routing and
server-key handling now retain the reviewed V6/V7 fixes; public hosted probes
and a read-only accounting reconciler are implemented. The worker suite passes
287 tests and the exact accounting query passes nine isolated PostgreSQL checks.
Actual hosted requests returned the expected unsigned schedule/external/receiver
denials, while the model returned `503 MODEL_PROVIDER_UNAVAILABLE`. CLI/browser
authentication is now restored. Actual read-only accounting shows no model/quota
records, one unresolved retry delivery and expired runtime authority. The model
key is absent. Positive model/usage/delivery gates remain open; no worker was
deployed or authority renewed.
See the [current runbook](ai-integrations-hosted-verification-20261031.md).

## Issues corrected in this workspace

1. **Assurance evidence HTTP body handling:** both evidence handlers previously read an unbounded body before checking its length. They now enforce the byte limit while streaming, validate declared length and UTF-8, and bound stalled reads/abort handling. Regression tests cover oversized, malformed and stalled inputs. No function was deployed.
2. **HR preservation verification:** the committed CI run exposed a false function-definition mismatch caused by different `search_path` settings during deparsing. The rollback harness now uses the same fixed-path temporary helper for both snapshots, preserves ACL checks and detects genuine body changes. The [candidate amendment](employee-hr-event-producers-candidate.md) distinguishes the historical 74/75 result, the local five-check PostgreSQL probe and the still-pending full 77-assertion suite. The producer candidate was not rewritten.
3. **Employee release provenance:** the existing release preparation now refuses existing artifact/manifest paths, creates unique folders atomically, records exact input and output hashes, and rejects changed build inputs. Synthetic verification exercises competing creation, byte preservation and overwrite refusal without opening signing material or building an app. The current script still points to the approved development target; it does not establish a production backend.
4. **Current lint and large-text regression:** ten analyzer findings in four existing HR/employee files were corrected with small code-style changes. The 200% employee-navigation test now scrolls its lazy viewport before checking service feedback, retaining the original behavior assertion.
5. **CI coverage and development instructions:** CI now runs all Edge handlers, candidate runner tests and intelligence worker tests, checks both changed assurance Deno entrypoints, exercises installer/provenance safety and compiles an employee Android release using an explicit development identity. Windows release packaging depends on those gates. The root README now runs the desktop app from the correct app directory. The new CI steps are configured and YAML-parsed, but have not been executed by GitHub for this dirty workspace.

## Verification actually completed

Logs and the source/evidence hashes are in [the verification directory](../verification/launch-readiness-20261028/). Initial failures and diagnostics are retained alongside the final results.

| Check | Current local result | Limit |
| --- | --- | --- |
| Workspace Flutter analyzer | No issues | Static source analysis |
| Dart formatting | 867 files, zero changes needed | Source formatting |
| Desktop tests and strict goldens | 2,322 passed | Automated Windows suite; no authenticated native acceptance or baseline replacement |
| Employee app VM tests | 224 passed | Browser, physical devices, store distribution and actual push delivery remain separate |
| Domain tests | 500 passed | Pure domain behavior |
| Platform adapter tests | 1,251 passed | Controlled integration/transport/storage adapters |
| Design-system tests | 10 passed | Widget and asset behavior |
| Edge handlers, candidate runners and employee Hosting preparation | 98 passed | Controlled Node tests |
| Intelligence/model/integration workers | 260 passed | Controlled Node tests; no hosted provider or network delivery activation |
| Assurance Deno entrypoints | 2 checked successfully | Type/import checks, not deployed endpoints |
| Installer safety | 14 passed | Synthetic release folders; no application/profile installation |
| Employee artifact provenance | 17 passed | Synthetic files; no signing material opened and no build invoked |
| HR preservation probe | 5 passed | In-memory PostgreSQL 18.6, not the full Supabase suite |
| CI YAML | Parsed with `yaml@2.8.1`, no duplicate keys/errors | Not a hosted workflow run |
| Original employee push candidate | SHA-256 matches the preserved original | `D0A92D80C7BAA2E0012230716A2237FEFF31A4D0FC90E5DA80F5D18C8F9A1D31` |

The current Dart/Flutter total is **4,307 passing tests**; the Node total is **358**. No current Windows/Android production release compilation, fresh dependency advisory/secret scan, Chrome suite, full database run, hosted migration installation, load certification or company signoff is claimed here. The latest committed GitHub database result is described in the HR amendment; the new workspace fixes have not been pushed or run there.

## Named test-company cleanup

The owner requested deletion of named test companies and asked for discovery. The repository identifies only a development Supabase target. Management access was tried both with the environment override and the saved login; both returned **Invalid access token**. The Supabase plugin is installed/enabled, but this chat currently exposes no Supabase project or SQL tools. There is no verified current hosted company list.

The [read-only inventory SQL](../verification/launch-readiness-20261028/company-inventory-readonly.sql) is prepared for the renewed, project-confirmed connection. It lists group/entity/branch names and IDs and membership counts, in a read-only rollback transaction. It contains no deletion statements or credential access and has not been run against the hosted database. Old fixtures and reports are not used as deletion targets.

Cleanup remains pending a current inventory, exact scope and recoverable cleanup procedure. No company, account, private file, finance, HR or audit record was deleted. Renew the Supabase connection in Codex; credentials must remain outside chat/source/logs.

## Preservation and release boundaries

The checkout remains on `codex/employee-web-android-push` at base commit `b8429547074e38250944117d1ac1c81af61b2498`. Concurrent HR/employee, signing and acceptance work remains in place. No reset, clean, stash, broad staging, commit or push was performed by this readiness work. Applied migrations were not rewritten. No migration was installed, no hosted sender/worker/scheduler was deployed or enabled, and no production release was published.

The required next sequence is: finish the functional administration scope; renew and verify the target; identify named test companies safely; run current isolated database and CI gates; rehearse the reviewed rollout and restore; then perform authenticated native/company acceptance on the exact release. Each result must keep source, installed, delivered and accepted states distinct.
