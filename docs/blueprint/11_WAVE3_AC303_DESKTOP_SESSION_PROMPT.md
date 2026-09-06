# Next session prompt — AC-303 Windows quotation workspace

Copy the prompt below into a new session.

```text
Continue Jentra OS Wave 3 from the existing working tree. Do not start over.

Workspace: C:\Users\sheha\Desktop\Jentra OS
Branch: main
Specification: docs/blueprint/08_WAVE3_INTEGRATED_COMMERCE_FINANCE_SPEC.md
Verification: docs/blueprint/10_WAVE3_QUOTATION_AC303_VERIFICATION.md
Wave 3 is approved for synthetic development only. Do not touch production.

Immediate objective: implement and verify the AC-303 Windows quotation workspace
(FR-319–FR-321), using the existing server and client contracts. Finish this slice
before extending the AC-304 quote-to-order/credit/reservation interaction.

Completed foundation:
- CRM pipeline and its protections remain intact.
- Quotation drafting/revision, exact pricing/tax/FX, workflow-pinned approval,
  recall, acceptance, expiry and cancellation RPCs exist.
- Scoped api.sales_quotation_details and api.sales_quotation_decisions views,
  bounded QuotationWorkspaceRepository reads, QuotationDraftCodec and encrypted
  QuotationDraftStore retry/conflict handling are implemented.
- Development migration 20260906153036_complete_quotation_workspace_contracts.sql
  is applied and immutable. Do not edit or reapply it.
- Last verified baseline: 149 Dart/Flutter tests, 356 SQL assertions, clean
  analyzer/formatter/SQL lint and a passing Windows debug build. Development
  ledger had 28 migrations; security advisors had no findings. These results
  are a baseline, not proof of the next UI slice or the full Wave 3 release gate.

Required implementation:
1. Inspect AGENTS.md, Git status/diff, the approved specification, verification
   report, existing domain/gateway/draft APIs and desktop design-system patterns.
   Preserve all existing changes and immutable migrations. Re-query development
   Supabase project xpdoufauvrbdmxgngetv and its ledger before assuming live state.
2. Work test-first. Wire the gateway/providers and capability-gated Sales route.
   Build quotation list/search/pagination, coherent detail, draft/revision editor,
   bounded governed-reference pickers, exact server-calculated totals and readable
   customer-facing revisions/approval decisions.
3. Add permitted submit/approve/reject/recall/accept/expire/cancel controls. Follow
   the configured server workflow; never manufacture approvals or authoritative
   totals in the client. Keep stock/credit mutations out of the quotation editor.
4. Preserve financial data as decimal strings/BigInt; never use binary floating
   point or aggregate different currencies. Use scoped api.* views for reads and
   named permission-checked RPCs for writes.
5. Persist actor/tenant/entity/branch-scoped drafts and complete retry envelopes
   before transport. Reuse command IDs, idempotency keys, timestamps and versions
   after uncertain outcomes. Preserve local edits on errors; show explicit
   conflict resolution. Guard offline writes, double submissions and stale async
   responses after actor/scope/capability changes.
6. Add widget, gateway and controller tests for happy paths, denial, offline,
   retry, conflict, recovery and scope switching. Inspect fresh rendered goldens
   and responsive/accessibility states. Run focused and full regression,
   formatter, analyzer, SQL checks when relevant and a secret scan.
7. Before a Windows build run flutter pub get --offline, then
   flutter build windows --debug --no-pub from apps/jentra_desktop. Verify Git
   still tracks zero generated Windows Flutter/plugin artifacts.

Do not reset, stash, clean, discard or overwrite existing work. Do not stage,
commit, push or deploy production changes unless explicitly asked. Any required
database correction must be additive, tested in rollback first and limited to
the approved development project.

Implement and verify, not merely plan. At completion report exactly what works,
test/build counts, development changes, remaining UI/runtime/load gaps and the
precise next AC-304 slice. Do not claim AC-303 desktop completion until its editor,
lifecycle controls, durable recovery, history and visual evidence are proven.
```
