# W4-02B private HR candidate checkpoint

2026-09-28. Development project `xpdoufauvrbdmxgngetv`. This is source and
rollback verification, not installation or authenticated acceptance.

Candidate `supabase/migrations/20260926185432_wave4_private_hr.sql` has SHA-256
`37E14C5A789B9D73BC7B5738CC087C4E5A59D4BF74F2E075CD2BAF70CF87C6C3`.
It adds a separate `people_private` API-only schema with 15 forced-RLS tables,
explicit private permissions, a private `jentra-hr-private` bucket, scoped
contact/review/account-link APIs, metadata-only frozen export preparation,
actual scoped erasure status, and bounded erasure jobs. Existing role and plan
grants remain unchanged. The candidate builder ends in `rollback;`; the latest
development rollback run returned `1..82` with no assertion error. This does not
establish installed behavior, live Storage policy enforcement or a running worker.

User and secret-key Edge entries use the current Supabase wrapper with pinned
`@supabase/server` 1.8.0. Both entries passed a Deno 2.9.6 type check. Eleven Node
handler tests passed with injected services; they do not exercise deployed Auth,
Storage or scheduler state. Earlier focused suites passed six domain, 17 platform
and 19 native tests. The native test generated six light/dark and 200%-text
screenshots; four were visually inspected. A later search-label change requires
re-generating the goldens and re-running final client analysis/tests.

An isolated Windows build script is prepared at
`docs/verification/wave4/build-private-hr-windows.ps1`. Its required
outside-workspace execution was rejected before starting by automatic approval
review because of an account usage limit. No build result is claimed. The default
sandbox also denied the Dart analyzer's child process, so final analysis is open.

Before installation review: complete final client checks/build, inspect the
refreshed images, compare candidate SQL to this hash, and verify that the worker
artifact and private Storage behavior are ready to deploy. Specific owner
approval is still required for the persistent SQL/bucket and Edge deployment.
After any approved deployment, verify ledger/RLS/grants/advisors, actual worker
probe and readiness, signed-in HR/subject/reviewer separation, document byte
retries, OS-keystore restart and genuine overlapping-session behavior. No real HR
data, existing acceptance tenant, original plans or external payroll flows are
used by this candidate.
