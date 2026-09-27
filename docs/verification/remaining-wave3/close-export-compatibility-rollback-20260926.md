# Close-review/export candidate compatibility and rollback plan

Status: reviewed and rollback-tested as source candidates; **not approved for
installation**. Candidates 08000 and 09000 follow the existing immutable ordered
procurement/inventory/finance/tax/GRNI chain. Development testing uses synthetic
fixtures in one transaction ending in rollback.

## Compatibility

No existing public API signature, journal/open-item schema, exact-decimal contract
or finance posting/allocation/residual helper changes. Existing AR/AP/GRNI report
kinds remain available. New close/export APIs, one private immutable snapshot table,
indexes and the export permission are additive. Existing setup/bank codec limits
remain 500/2,000 rows; report export has a separate bounded constructor.

The existing private period-close exception entrypoint now rechecks independent
GRNI/inventory/bank evidence. Missing configuration and unexplained differences
can block a close that the preceding candidate would allow. This deliberate
governance change requires explicit compatibility review before installation;
a schema-only checker cannot approve the behavioral change. Read-only close
helpers are STABLE so the complete graph shares a statement snapshot.

New desktop routes are capability-gated. Export source APIs retain their current
permission rules and additionally require entity and working-branch export access.
Six report workspaces link to their saved, filtered evidence. Schema and client
installation must be coordinated: the new routes require their candidate APIs.
New export permission is not auto-granted by this candidate.

## Phase rollback and validation

1. **Candidate composition**: confirm current development project/ledger and helper
   fingerprints; compose with the builder in dependency order. Any compile/test
   failure aborts the transaction. Strict pgTAP finish and final rollback must pass.
   Verify that close-review and export APIs/tables are absent afterward and shared
   helper fingerprints unchanged. No migration ledger entry is written.
2. **Isolated desktop verification**: copy source/manifests/runner only, use cached
   dependency resolution, run scoped gateway/recovery/client checks and analyzers,
   inspect light/dark 200% previews, then compile Windows without launch. Keep the
   snapshot/log hashes. A build failure cannot replace the acceptance executable.
   The longer MSBuild tracking path failed; a shorter source copy is the retry.
3. **Future installation — separate authorization required**: refresh installed
   compatibility, obtain owner acceptance of stricter hard-close behavior, coordinate
   client/API versions and apply only reviewed additive migrations in order.
   Stop before business use if private RLS/ACL, source/branch checks, exact equations,
   API shape or recovery checks fail.
4. **Future operational rollback — not executed here**: revert the client to its
   preceding compatible package and disable new feature entrypoints. Preserve
   recorded command receipts, export jobs and immutable snapshots. Do not drop
   immutable history or restore older finance posting helpers over business writes.
   Repair a defective close check with a separately reviewed additive forward
   migration; an old saved review must never waive live ledgers. Before resuming,
   recheck all period-close exceptions and scope/permission behavior.

Real installed concurrency/load, authenticated native dialogs, Credential Manager
process recovery and owner signoff are outstanding gates. This plan neither
authorizes installation nor changes authentication or stock-opening acceptance.

