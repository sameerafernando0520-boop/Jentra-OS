# Wave 5 authoritative payroll and reimbursement payment dates

Candidate contract, 2026-10-08. Installation and authenticated owner acceptance remain separate gates.

Wave 4 owns issued payroll obligations, signed correction balances, reimbursement ownership, journals, settlements and original-only reversals. Wave 5 reads those sources and owns an append-only payment-date registry. This contract neither alters a Wave 4 table/function nor creates supplier AP, payroll calculations, milestones, bank transactions or settlements. A posting date proves recognition; a milestone proves project progress. Neither supplies a payment date.

## Date authority

The source kinds are `payroll_obligation`, `payroll_correction` and `project_reimbursement`. A source must be an issued obligation with a posted original journal. Its immutable fingerprint binds kind, UUID, tenant, entity, branch, currency, original signed amount, control account, issue effect and original journal/date. Employee identities, payslip bodies and expense evidence stay in Wave 4.

`analytics.cash_dates.prepare` plus the source settlement capability permits a proposer to capture a civil `YYYY-MM-DD` payment date, a reason code (`payroll_calendar`, `payment_terms`, `reviewed_reschedule`, `correction_recovery`), original source fingerprint and expected approved version. Dates must be finite, four-digit civil dates on or after recognition. Negative corrections represent recovery inflows and retain their signed source amount. Dates may precede the cash horizon, in which case the obligation is explicitly overdue and excluded from that horizon.

`analytics.cash_dates.approve` plus the source approval capability permits a distinct MFA actor to approve or reject the exact proposal digest. Preparation also requires MFA. Approval rechecks current scope, entitlements, original source fingerprint, remaining balance and expected approved version under a per-source transaction lock. One concurrent approval wins; stale proposals cannot overwrite it. Rejection leaves the prior approved date effective. A revised date requires another proposal and independent approval. Proposals and decisions are immutable; approved versions are monotonic. No default dates or automatic approvals exist.

The command identity, idempotency key, original timestamp and bounded parameters survive uncertain responses in an encrypted, actor/scope-bound draft. Retry repeats that original envelope. Current authorization runs before replay or recovery. Generic receipts/audit/outbox contain only IDs, versions, decision and digests; private dates/amounts and source bodies stay in scoped APIs. No existing role or subscription gains a permission/entitlement.

## Dated remaining cash

Contract revision 3 (`dated_transaction_cash_all_obligations.v3`) requires `bank_cash`, `receivables`, `payables`, `payroll` and `project_reimbursements`. Revision 2 remains a historical, explicitly partial bank/AR/AP publication. Source adapters are optional at installation: absence is `source_not_installed`, never an empty complete family. Payroll completeness requires both regular and correction source contracts.

Residuals sum immutable signed effects with effective journal posting date strictly before horizon start and effect recorded time at or before the captured UTC cutoff. Settlement reversals use their reversal journal date; current mutable parent status cannot rewrite history. Project effects carry their own authoritative posting date/journal. An incomplete/unposted journal reference, wrong-sign or over-allocated residual fails closed. A negative payroll correction residual becomes an inflow with positive magnitude; regular payroll and reimbursements are outflows. Same-day/future settlements do not reduce opening obligations. Fully settled/reversed obligations require no date.

The latest approved revision recorded at or before the cutoff supplies the date. Its original source fingerprint must still match. Pending/rejected proposals never supply dates. Any nonzero recognized residual without an approved date makes the entire family `missing_payment_date`, including obligations whose horizon membership cannot yet be known. Denied source access, missing People/Projects/Finance entitlements or missing MFA makes the family unavailable. A family never publishes a readable subset as complete. Entity-wide reads require source access for every active branch and every contributing source branch.

Amounts are exact decimal strings / six-place `BigInt` units. Scopes and currencies remain separate. Bounds are 10,000 total controls/obligations, 10,000 manifest references, 100 currencies, 366 days and 8 MiB; overflow is an error. Sources retain original issue, included effect and approved date revision identities. Duplicate obligation UUIDs across providers fail closed because scenario overrides use UUID keys.

Immutable scenario freeze requires all five families for revision 3. Reopen, export creation, download and reopen recheck current source permissions, entitlements and MFA for every captured family/branch. Governed export uses explicit inflow direction, includes recovery and reimbursement flows, and identifies the exact calculation revision and captured provider coverage. Scenario date/amount overrides remain hypothetical and cannot change an authoritative approved payment date.

## Evidence and rollout

The new migration is an unapplied Wave 5 candidate. Preserve byte hashes of the Wave 4 source migrations and use their actual schemas in strict rollback-only composition checks. Candidate SQL, installed SQL, source-matched Flutter/native rendering, authenticated MFA, independent sessions/load and owner signoff are different gates. Rollback fixtures do not demonstrate real MFA or persistent delivery. Additional installation, bootstrap, entitlement activation, secrets and deployment require a concrete review and separate authorization; real billing and production remain excluded.
