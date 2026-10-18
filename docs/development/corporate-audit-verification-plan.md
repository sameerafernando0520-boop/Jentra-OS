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
4. **Platform client** — typed response validation, uncertain-result handling (timeout after commit → replay same key), revocation.
5. **Desktop** — widget/controller tests for loading, empty, denied, error, offline; keyboard, focus, 200% text, light/dark goldens.
6. **Recovery** — encrypted draft restore after restart and after access loss (draft discarded, never submitted).
7. **Export** — generate, download, SHA-256 match, reopen.
8. **Contention** — two independent sessions racing the same engagement version and the same idempotency key.
9. **Scale** — `EXPLAIN (ANALYZE, BUFFERS)` and p95 for engagement detail at target volume.
10. **Native** — isolated Windows build, authenticated walkthrough ([checklist](corporate-audit-native-acceptance.md)).
11. **Owner review and sign-off** — final, separate gate.
