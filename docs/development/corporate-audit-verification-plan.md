# Corporate Audit & Assurance — candidate verification plan

Each layer is separate evidence; none substitutes for a later one.

1. **Domain** — `cd packages/jentra_domain && dart analyze && dart test test/assurance_test.dart`.
   Covers state maps, command allow-lists, evidence metadata, SoD helpers, sampling, typed-response fail-closed parsing, percentiles.
2. **Candidate database (rollback only)** — `.\supabase\tests\build_assurance_candidate.ps1` produces one
   `begin … rollback` query; the builder refuses output containing `commit` or not ending in `rollback;`.
   Run through the read/write connector against the dev project, record source and query SHA-256,
   then a read-only post-check that `assurance` schema, permissions, pgTAP and fixture users are absent.
   Required coverage: grants/forced RLS; tenant/entity/branch isolation; external limits; SoD; recent MFA;
   idempotency/version; immutable history; provenance/digest; holds; report issue/reopen.
3. **A2 (done, 98/98 rollback)** — test design/execution/review, `decide_risk` approve/reject, `dismiss_exception`, `cancel_request`, archive guard with carry-forward, late-failure rollback, `revoke_team_member`. Build with `build_assurance_candidate.ps1 -Slice A2`.
3b. **A4 (done, 129/129 rollback)** — adapters (module guard reuse, branch/period checks, canonical digest), access-review snapshot, re-verification, export MFA/supersession, manifest re-hash, external read. Build with `-Slice A4`.
3c. **A4b (done, 153/153 rollback)** — the four remaining report kinds with fixtures and re-verification; procurement three-way-match and workforce attendance snapshots (module guards, People entitlement, no identities); monitoring rules create candidates once, never findings, with independent promotion. Build with `-Slice A4b`.
3d. **A3 (done, 208/208 rollback)** — universe and risk assessment independence, template allow-lists and versioning, plan maker-checker with MFA and approval digest, uncovered high-risk report, engagement instantiation per occurrence (period, lead, template controls and PBC requests), A1 rules on instantiated engagements, read isolation. Build with `-Slice A3`.
3e. **A5 (done, 228/228 rollback)** — register and work-queue read models: reminder bands, response SLA, caller and team scoping, archived exclusion, paging, external/foreign/branch isolation. Build with `-Slice A5`. Desktop: `apps/jentra_desktop/test/assurance_workspace_test.dart` (13 tests incl. 200% light/dark goldens); platform `assurance_gateway_test.dart` (6).
4. **Platform client** — typed response validation, uncertain-result handling (timeout after commit → replay same key), revocation.
5. **Desktop** — widget/controller tests for loading, empty, denied, error, offline; keyboard, focus, 200% text, light/dark goldens.
6. **Recovery** — encrypted draft restore after restart and after access loss (draft discarded, never submitted).
7. **Export** — generate, download, SHA-256 match, reopen.
8. **Contention** — two independent sessions racing the same engagement version and the same idempotency key.
9. **Scale** — `EXPLAIN (ANALYZE, BUFFERS)` and p95 for engagement detail at target volume.
10. **Native** — isolated Windows build, authenticated walkthrough ([checklist](corporate-audit-native-acceptance.md)).
11. **Owner review and sign-off** — final, separate gate.
