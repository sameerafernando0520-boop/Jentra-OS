# Corporate Audit & Assurance — readiness matrix (18 Oct 2026, after A5 and dev installation)

Legend: **D** domain test · **R** candidate rollback pgTAP · **I** installed (dev = development project `xpdoufauvrbdmxgngetv`, 228/228 installed rollback suite) · **N** native authenticated · **C** contention/load · **O** owner accepted. "–" = not yet.

| FR | Summary | D | R | I | N | C | O |
|---|---|---|---|---|---|---|---|
| FR-6801 | Universe & risk assessment | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6802 | Plan approval | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6803 | Scoped engagement | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6804 | Lead/team, time-bound external | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6805 | Control mapping + independence | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6806 | Evidence/PBC requests | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6807 | Evidence provenance metadata | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6808 | Evidence review + rework | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6809 | Freeze with cutoff digest | – | ✓ | ✓ dev | – | – | – |
| FR-6810 | Test procedures / sampling | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6811 | Exceptions ≠ findings | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6812 | Ordered attributable events | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6813 | Independent finding issuance | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6814 | Management response | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6815 | Independent risk decision | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6816 | Remediation + independent retest | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6817 | Reopen findings | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6818 | Immutable versioned report | – | ✓ | ✓ dev | – | – | – |
| FR-6819 | Legal holds, segregated release | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6820 | Carry-forward | ✓ | ✓ | ✓ dev | – | – | – |
| FR-6821 | Evidence adapters | ✓ | ✓ (8 of 8 kinds exercised) | ✓ dev | – | – | – |
| FR-6822 | Governed export | ✓ (+ platform verifier) | ✓ | ✓ dev | – | – | – |
| FR-6823 | Templates/reminders/dashboards | ✓ (templates, recurrence, reminder levels) | ✓ (templates, recurrence, overdue queue) | ✓ dev | – | – | – |
| FR-6824 | Desktop workspace | ✓ (controller, widget, 200% goldens; A6a/A6b auditor actions; A7 planning) | ✓ (read models) | ✓ dev | – | – | – |
| FR-6825 | Process metrics | ✓ (calc) | – | – | – | – | – |

24 of 25 requirements are installed in the development project (FR-6825 process metrics is domain-only). None is native-verified, load-tested or owner-accepted; nothing is in production.
