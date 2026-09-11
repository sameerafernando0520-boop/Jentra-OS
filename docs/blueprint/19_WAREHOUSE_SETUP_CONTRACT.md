# Warehouse setup for stock-opening acceptance

Development-only continuation, 2026-09-11. The authenticated user confirmed the
repaired navigation and requested setup of stock-opening prerequisites.

The existing `core.warehouses` table and security-invoker `api.warehouses` view
have no creation command or setup form. Add Warehouses to the Catalogue section
of Business setup, with code, name, active/inactive status and a named branch
selector restricted to the selected legal entity. Existing warehouse scope is
immutable; updates require the current version. Branch/entity/tenant scope and
active references are checked by the server, and writes require
`core.setup.manage` in that scope, including its existing MFA guard.

`api.upsert_warehouse(p_tenant_id, p_legal_entity_id, p_payload,
p_expected_version, p_idempotency_key)` uses the existing command receipt,
request-hash, audit and outbox infrastructure. Matching retries return the same
receipt; mismatched retries fail. The command creates no stock or journal.
Read policy and existing warehouse consumers remain unchanged. No import/export
support or reparenting is added in this slice.

Verification covers permission/MFA denial, foreign scope, invalid fields,
optimistic versions, immutable scope, retry deduplication and audit/outbox
evidence in rollback-only fixtures, plus client validation and rendered forms.
Published migrations and existing dirty work remain untouched.

Setup target: Jentra Acceptance Lab / Jentra Acceptance Trading / Head Office.
The user designated `test@lh.com` as independent approver. It exists but has no
workspace membership. An invitation and appropriately scoped approval role
must be resolved before testing independent approval; MFA remains user-managed.

The additive command migration is applied as `20260911065744`. See the
[verification record](../verification/stock-opening/warehouse-setup-verification.md)
for database, domain, desktop, rendered and Windows evidence. The prepared
business records remain separate from command/schema verification.
