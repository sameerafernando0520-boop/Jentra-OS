# W4-02B private HR development installation review

2026-09-30. Target **development `xpdoufauvrbdmxgngetv` only**. This review
implements the specific installation boundary in
[the user's remaining-development instruction](../../development/remaining-wave4-development-prompt.md):
"Follow the established owner-approval boundary for that specific installation."
Generic continuation is development authority; this persistent installation and
deployment still require their specific approval.

## Exact proposed change

Install `20260926185432_wave4_private_hr.sql`, SHA-256
`37E14C5A789B9D73BC7B5738CC087C4E5A59D4BF74F2E075CD2BAF70CF87C6C3`.
It creates 15 forced-RLS API-only `people_private` tables; named scoped contact,
document, review, account-link, own-receipt, metadata export and erasure APIs;
explicit private permission definitions; a private `jentra-hr-private` Storage
bucket with restrictive policies; and bounded ticket/purge/readiness APIs.
Existing plan entitlements, role grants, memberships, identities and acceptance
data receive no changes. Employee/calendar applied migration files remain intact.

Deploy these source entries and their local handler/config files with the pinned
`npm:@supabase/server@1.8.0` wrapper:

| Entry | Authentication | Source SHA-256 |
|---|---|---|
| `people-private-documents/index.ts` | wrapper `auth: user` plus scoped ticket/current permission checks | `E8C054954DE54ED75C485A3DB7D1ED47F1E6B4930105EBB59B8BA68170557B54` |
| `people-private-documents/handler.mjs` | private byte upload/download/export, no public URL | `7641A9547B22ED67682DABF7345AEA15C6CA027C3CED89353F687EC66741C613` |
| `people-private-purge/index.ts` | wrapper `auth: secret`; service-only APIs | `A190F04749BB8C75A7FE3A9C692AE97A8DA0CFBD6E615E1ACD731E1E2657DF17` |
| `people-private-purge/handler.mjs` | verified probe and bounded leased object/redaction jobs | `8B8761A4BED4709646AAC9FC813F7F7DDB79B3114C1E95DF5975A5F051C57A27` |

Worker writes remain unavailable until the nonsecret
`JENTRA_HR_WORKER_ARTIFACT_SHA256` configuration is set and an authorized worker
probe uploads, reads back and removes its own random probe object successfully.
Credential/secret-key provisioning and scheduler activation remain separately
owner/provider-controlled. This approval does not authorize extracting tokens,
changing Auth configuration, activating a schedule or erasing existing data.
Missing worker readiness is an explicit failure, never fabricated success.

## Verification and practical limits

Fresh private HR rollback tests passed **82 assertions**. The unchanged Edge
entries previously passed pinned Deno 2.9.6 type checking; today's **11 injected
Node handler tests passed** again. The current combined People run passed
**45 domain, 64 gateway/recovery and 82 native tests**, including the private HR
6/17/19 focused cases. Final relevant analyzers report no issues. Refreshed
private HR light/dark, both density and 200% goldens passed and the updated search
view was inspected. The isolated Windows release build and refreshed build passed;
see [current client evidence](workforce-checkpoint-20260930.md) and
[build/source hashes](client-source-hashes-20260930.json).

The latest database read still finds 36 installed migrations, no private HR
installation and no synthetic workspace tenant. Installation/deployment,
Storage/runtime byte retries, worker probe/jobs, signed-in HR/subject/reviewer
separation, Credential Manager restart, real concurrency and owner acceptance are
not yet verified. These remain required after an approved install and bootstrap
reconciliation. Rollback fixtures and fake HTTP/JWT harnesses are not live Auth.

## Install verification sequence

After specific approval, reread project/ledger and source hashes, install only
this migration, deploy only these two functions and verify ledger, forced RLS,
explicit authenticated/service grants, restrictive Storage and advisors. Report
worker configuration/probe state separately; do not mark an unavailable worker
ready. Preserve all data and continue payroll/projects/service/assets development
while owner-managed authentication/provider gates remain pending. This review
does not approve organization, attendance/leave or concurrent Wave 3 candidates.
