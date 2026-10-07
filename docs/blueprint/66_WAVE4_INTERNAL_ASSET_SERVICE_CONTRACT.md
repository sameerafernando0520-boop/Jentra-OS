# Internal fixed assets as service equipment

2026-10-05. Additive, unapplied operational association for FR-431–434 and
FR-435, AC-401/414/415/416. Depends on reviewed Service and Assets candidates.

A scoped active fixed asset may become internal equipment only after fresh
module.service and module.assets entitlement checks, service.configure,
assets.view and MFA. Named sources expose operational identity, branch, location,
custodian, ownership, current version and digest. They expose no book, cost,
account, compensation or capitalization values. Link creation locks the asset's
authoritative register row, verifies the exact selected version/digest, and retains
an immutable source basis and reason. One scoped asset has one equipment link.
The association creates no journal, stock movement or capitalization effect.

Lock order is payroll entity, projects entity, service entity, then the asset
register row, then the existing employee/ticket/order rows. Assets commands never
acquire a service lock. Disposal/transfer and service mutation therefore serialize
on the same authoritative asset row. Harmless book version changes do not erase
the link or block service; dispatch, new tickets/readings/plans and occurrence
generation verify current active status and the accountable branch while holding
the asset lock. Historical service reads require both current scoped authorities.
Cancellation and historical approval retain their original operational facts.

Internal tickets have customer_id and contact_id both null. Customer equipment
still requires its actual active customer and matching contact. Internal labor
is explicitly nonbillable; the protected billing provider rejects an internal
source. Completion records customer_confirmed=false and a reasoned internal
confirmation exception. No customer identity or external acceptance is invented.

The source picker and immutable link detail are named bounded APIs. Clients have
no direct table/helper grants; link history forces RLS and rejects updates/deletes.
Every mutation and actor-owned receipt checks current scope, permissions,
entitlements and MFA before replay. The native link form uses named source choices,
seals encrypted recovery before issue, preserves exact uncertain retries, and
binds acknowledgement to the canonical complete envelope digest. Scope/access
epochs clear plaintext and prevent late reads or permission results from entering
a replacement view. Missing provider functions produce an explicit unavailable
state. Stock equipment, procurement and service part providers remain separate.

Required verification covers stale source/version/digest, both entitlement and
permission revocation before replay/read, another tenant/branch, immutable basis,
duplicate link, current disposed/transferred guards, customer-null maintenance,
nonbillable labor and atomic late failure. Synthetic rollback and widget checks
remain distinct from installed behavior, authenticated acceptance, true contention,
Credential Manager restart and owner signoff.
