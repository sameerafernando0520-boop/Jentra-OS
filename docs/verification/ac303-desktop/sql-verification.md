# AC-303 desktop slice: fresh development SQL verification

Verified 2026-09-06 at 16:03 UTC against development project
`xpdoufauvrbdmxgngetv` only. No production calls, permanent database changes,
migration application or immutable migration edits were performed.

The live migration ledger contains **28** entries; latest version is
`20260906153036`. Scoped `api.sales_quotations`,
`api.sales_quotation_details`, and `api.sales_quotation_decisions` columns were
re-read directly. The detail view includes current lines as JSONB; financial
values and decision amounts remain text.

## Fresh regression

Each existing suite ran sequentially in its own `BEGIN` / `ROLLBACK` transaction.
The executed copy promoted any `finish()` call to strict `finish(true)` without
changing tracked files. After strict completion, the query returned the suite
name, planned assertion count and pgTAP `_get('curr_test')` completed count.

| Existing suite | Planned | Completed and passed |
| --- | ---: | ---: |
| Greenfield foundation | 30 | 30 |
| Wave 2 shared foundation | 99 | 99 |
| Wave 3 operational foundation | 50 | 50 |
| Wave 3 CRM pipeline | 88 | 88 |
| Wave 3 lead-to-cash foundation | 46 | 46 |
| Wave 3 quotation workspace contracts | 43 | 43 |
| **Total** | **356** | **356** |

After rollback, direct counts confirmed zero quotation headers, lines,
revisions, sales orders, CRM leads and opportunities. All 12 distinct synthetic
auth user IDs present in the six suites were absent. The ledger remained
28 entries with the same latest version. Fresh security advisors returned zero
findings.

## Runtime configuration boundary

Development currently has zero active `sales_quotation` workflows. The SQL
suites create explicit synthetic workflows inside their rollback transactions;
passing suites do not make a live tenant ready to submit quotations. A real
authenticated development walkthrough requires governed customer/product/tax/
currency data, an active configured workflow and scoped users. The application
must surface server configuration denial rather than invent a policy.

## Existing lifecycle contract checked for the desktop implementation

Every action still requires the configured lifecycle edge and expected version.
The server maps `pending_approval` to `submitted` for edge checks.

| Action | Structural status eligibility | Additional server checks |
| --- | --- | --- |
| Save draft | Draft | Governed references, exact calculations |
| Create revision | Submitted, approved, rejected, expired | Required revision reason; new revision and line IDs |
| Submit | Draft | Current UTC validity, active unambiguous workflow and matching approval policy; pins policy |
| Recall | Submitted, pending approval, approved | Required reason; creates draft revision and new line IDs |
| Approve / reject | Pending approval | Live decision capability and scoped step role, segregation of duties; rejection note required |
| Accept | Submitted, approved | Validity compared with the later of server UTC today and client UTC date |
| Expire | Submitted, pending approval, approved | Validity strictly before server UTC today |
| Cancel | Any except cancelled and converted | Configured cancellation edge; resolves pending approval |

Structural eligibility is insufficient to infer a permitted workflow edge.
Approval may remain pending when another pinned approval step exists. Pending
approval documents must be recalled before revising. Accepted quotation
contents remain immutable; cancellation is possible only if its configured
edge allows it. No stock or credit mutation belongs in this editor.

This evidence verifies unchanged server contracts and rollback behavior. It
does not prove desktop rendering, authenticated UI use, Windows launch,
multi-session contention or the full Wave 3 release gate.
