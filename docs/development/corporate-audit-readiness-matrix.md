# Corporate Audit & Assurance — readiness matrix (21 Oct 2026)

Legend: **D** domain test · **R** candidate rollback pgTAP · **I** installed (dev = development project `xpdoufauvrbdmxgngetv`; A1–A5 on 18 Oct, version guard to A14 on 20 Oct; installed suite in CI) · **N** native authenticated · **C** contention/load · **O** owner accepted. "–" = not yet.

| FR | Summary | D | R | I | N | C | O |
|---|---|---|---|---|---|---|---|
| FR-6801 | Universe & risk assessment | ✓ (+ tenant rating bands, A9) | ✓ | ✓ dev | – | – | – |
| FR-6802 | Plan approval | ✓ (+ revision/supersede, A9; plan register) | ✓ | ✓ dev | – | – | – |
| FR-6803 | Scoped engagement | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6804 | Lead/team, time-bound external | ✓ (+ assurance roles and access, A8) | ✓ | ✓ dev | – | – | – |
| FR-6805 | Control mapping + independence | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6806 | Evidence/PBC requests | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6807 | Evidence provenance metadata | ✓ (+ stored-byte verification, A7; reviewer download, A12) | ✓ | ✓ dev | – | – | – |
| FR-6808 | Evidence review + rework | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6809 | Freeze with cutoff digest | ✓ (A13, equal to the SQL digest) | ✓ | ✓ dev | – | – | – |
| FR-6810 | Test procedures / sampling | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6811 | Exceptions ≠ findings | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6812 | Ordered attributable events | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6813 | Independent finding issuance | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6814 | Management response | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6815 | Independent risk decision | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6816 | Remediation + independent retest | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6817 | Reopen findings | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6818 | Immutable versioned report | ✓ (A13, equal to the SQL digest) | ✓ | ✓ dev | – | – | – |
| FR-6819 | Legal holds, segregated release | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6820 | Carry-forward | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6821 | Evidence adapters | ✓ | ✓ (8 of 8 kinds exercised) | ✓ dev | – | – | – |
| FR-6822 | Governed export | ✓ (+ platform verifier) | ✓ | ✓ dev | – | – | – |
| FR-6823 | Templates/reminders/dashboards | ✓ (templates, recurrence, tenant reminder bands, reminder scan, inbox) | ✓ | ✓ dev | – | – | – |
| FR-6824 | Desktop workspace | ✓ (workspace, planning, access, settings, metrics, inbox; 200% goldens; A14 UI/UX and accessibility pass; A16 date pickers, panels with status badges, empty and error states, one header on every audit screen) | ✓ (read models) | ✓ dev (+ two evidence edge functions) | – | – | – |
| FR-6825 | Process metrics | ✓ (calc + parser) | ✓ (A11) | ✓ dev | – | – | – |

Installation records show all 25 requirements in development. No requirement has
native, load or owner acceptance. The recorded member-role state has not been
refreshed: administration access is currently unavailable. The owner authorized
isolated development test accounts on 21 October; creation is pending reconnection.
No production change was made in this completion run.

Fresh verification: domain 500/500, platform 1,198/1,198, desktop 2,145/2,145
including goldens (focused assurance UI 98 tests), Windows release built,
ZIP runtime hashes 35/35, deployed development
unauthorized-function checks 4/4, and desktop/domain/platform analysis clean.
These results do not change N/C/O. See
[status](corporate-audit-status.md), [screen references](../verification/assurance/screen-review-20261021.html)
and the [production packet](../verification/assurance/production-promotion-20261021.md).
