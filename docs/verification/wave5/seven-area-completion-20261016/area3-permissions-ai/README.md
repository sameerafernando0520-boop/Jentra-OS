# Area 3 permissions, AI and operator completion review

Reviewed all 26 assigned complete statements. Three concrete model-runtime defects were fixed in candidate source. No additional requirement acceptance is justified from controlled tests alone.

| Fix | Result |
|---|---|
| A3-01 | Reject untrusted usage adapters before protected retrieval or any side effect. |
| A3-02 | Apply shared exact usage/suggestion validation before replay settlement; malformed, over-budget and foreign suggestions cannot cause a settlement write. |
| A3-03 | Reauthorize the source after settlement and before returning a saved suggestion, matching the fresh invocation flow. |

Verification: before-fix regression run failed 4 of 8 tests as expected; after-fix focused run passed 16 of 16; all worker tests passed 260 of 260, with no failures or skips.

Only workers/wave5/model_runtime.mjs and model_runtime.test.mjs were edited. No versioned V7 or frozen execution file was changed. Current deployed behavior is not claimed fixed. Independent source review and updated bindings are required before candidate deployment.

| Requirement | Remaining complete-statement evidence |
|---|---|
| FR-501 | Complete genuine scoped/foreign/branch and access-loss cases for every query, job, proposal, integration and command; 500 process/forecast reads with two sessions cover only those reads. |
| FR-503 | Verify live source permission/entitlement revocation for all metrics and saved-result creation/reopen/drill-through, including immediate protected display clearing. |
| FR-504 | Inspect every analytics projection, exported payload and prompt against the prohibited-field list; limited metadata and process wire-shape checks do not cover all projections. |
| NFR-501 | Installed metadata checks cover forced RLS/grants, but every new view/RPC/job/export still needs all anonymous/foreign/branch/source-revocation zero-leak behavior cases. |
| NFR-507 | Complete zero-prohibited-field scans of Connected binary, exports, actual prompts and logs plus native access-revocation display clearing before another protected action. |
| AC-501 | Complete permitted/forbidden two-tenant/branch metric/job/detail/saved-result behavior before/after access changes and immediate visible evidence clearing. |
| EC-501 | Exercise live tenant/entity/branch mismatch and permission loss during active jobs, including report download and cleared native evidence. |
| FR-557 | Exercise installed analytics/workflow/source capability, entitlement, tenant/entity/branch and current drill-through permission cases through genuine actors. |
| NFR-553 | Complete all genuine anonymous/foreign/own-event-without-source-permission/revocation/missing-entitlement zero-leak adapter cases. |
| AC-554 | Use a genuine own-event actor lacking source-domain permission and prove zero event/aggregate/detail output from the installed adapter. |
| EC-556 | Domain foreign/null scopes reject correctly; genuine own-event RLS/source permission/capability loss adapter cases remain incomplete. |
| FR-516 | Complete the reviewed private retrieval/provider path with genuine scoped evidence, malicious source text and field redaction before actual invocation; no model invocation occurred. |
| FR-517 | Read back genuine immutable proposals with exact allowlisted command, target versions/hash, evidence, explanation, expiry and budget; verify edit/revision behavior. |
| FR-518 | Exercise genuine distinct proposer/approver sessions and MFA, self-approval denial, exact revision approval, edit invalidation and downgrade/expiry rejection. |
| FR-519 | Run approved execution through existing business command checks with stale/expired/revoked targets and overlapping genuine executor requests. |
| FR-520 | Complete trusted worker invocation reservation/usage settlement, retries and unknown outcome reconciliation; the private model key and actual usage remain absent. |
| AC-507 | Complete installed scoped retrieval/malicious text/private field and absent-provider attempts; full private coordinator/redaction behavior remains incomplete. |
| AC-508 | Run genuine self-approval denial, distinct required-MFA approval and approved-revision edit invalidation through the installed workflow. |
| AC-509 | Run stale and overlapping genuine approved execution plus retries/unknown provider completion, reconciling exactly one business effect and usage settlement. |
| EC-507 | Complete real reviewed retrieval injection/provider-unavailable/quota/unknown-outcome policy boundaries; no genuine model output or settlement exists. |
| EC-508 | Complete genuine expiry/self-approval/stale-target/MFA-downgrade execution denials with retained proposal and decision evidence. |
| FR-527 | Use the separate genuine MFA operator identity to verify owner denial, cross-tenant isolation and only reviewed health projections. |
| FR-528 | Issue the exact reviewed expiring/reasoned operator authority and prove MFA access plus immutable audits and expiry/revocation; scan Connected binary for service secrets. |
| FR-529 | Observe installed worker lag/retries/dead-letter/quota/readiness timestamps and missing-probe unknown states using real authorized operator reads. |
| AC-514 | Run genuine tenant-owner/operator/grant expiry cases with authorized projections, audit and stopped-probe unknown readiness. |
| EC-512 | Exercise real operator grant expiry mid-read and stopped health probes with access denial and unknown readiness. |

No live SQL, provider invocation, private input, SDK job or deployment was performed. The inspected runtime/private snapshots are historical October 14 observations. Actual actor, MFA, provider and native cases remain open.

[Machine-readable full statements and hashes](completion-report.json)
