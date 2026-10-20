# Corporate Audit & Assurance — readiness matrix (20 Oct 2026, after A15 dev installation)

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
| FR-6824 | Desktop workspace | ✓ (workspace, planning, access, settings, metrics, inbox; 200% goldens; A14 UI/UX and accessibility pass) | ✓ (read models) | ✓ dev (+ two evidence edge functions) | – | – | – |
| FR-6825 | Process metrics | ✓ (calc + parser) | ✓ (A11) | ✓ dev | – | – | – |

25 of 25 requirements are installed in the development project. None is native-verified, load-tested or owner-accepted; no member holds an assurance role yet; nothing is in production.
