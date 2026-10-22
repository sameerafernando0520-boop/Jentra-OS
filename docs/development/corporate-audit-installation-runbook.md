# Corporate Audit & Assurance — installation and recovery runbook

Updated 21 October 2026. This runbook covers the complete assurance installation through A15 and the A16 desktop. It does not authorize production deployment.

Development project `xpdoufauvrbdmxgngetv` has six migrations recorded on 18 October and nine on 20 October; see the [18 October record](../verification/assurance/installation-dev-20261018.json) and [20 October record](../verification/assurance/installation-dev-20261020.json). These are historical observations, not a fresh production inspection. The [promotion packet](../verification/assurance/production-promotion-20261021.md) and [SHA-256 manifest](../verification/assurance/production-promotion-20261021.manifest.json) identify all 15 migration files and the evidence-function sources.

## Authority and prerequisites

1. Record the exact production project reference, owner, maintenance window and recovery contact. Production reference: **pending**. Never infer it from the linked development project or use a project merely because credentials exist.
2. Obtain separate owner approval for that target, the manifest hashes, both evidence functions and the window. A request to finish development does not supply this approval. Member grants and owner acceptance are separate decisions.
3. Refresh the target ledger and object definitions read-only. Compare prerequisite migrations with the reviewed branch and determine the exact missing assurance suffix. Stop for conflicting versions, a partial installation or unknown prerequisites. Do not install unrelated pending migrations under this approval.
4. Recompute every manifest SHA-256 from the files to be applied. Review any changed bytes. Preserve applied migrations: no renaming, editing, ledger repair or manual ledger deletion.
5. Rehearse the full migration chain, database lint and cumulative installed pgTAP suite in an isolated stack or approved staging clone with matching prerequisites. Generate the suite with `supabase/tests/build_assurance_candidate.ps1 -Slice A14 -Pgtap`; `-Installed` without `-Pgtap` is the rollback diagnostic variant. Check the transaction ends in rollback. Record source revision, query hash, result and fixture cleanup. Confirm CI (`supabase test db`) is green for the intended revision.
6. Complete the [native checklist](corporate-audit-native-acceptance.md) on development with owner-managed accounts, genuine MFA, actual evidence upload/verification/download, keyboard and screen-reader checks. Record contention/target-scale results separately. Obtain screen sign-off separately; automated tests do not establish these gates.
7. Verify the production backup/PITR or snapshot recovery point, access, restore procedure and approved restore destination. Record a rehearsal and acceptable outage/data-loss window. Verify storage recovery separately: a database backup alone does not establish recovery of evidence objects.

## Installation sequence after approval

1. Freeze the approved source revision and manifest. Check for concurrent migration work. Record the target's baseline ledger, grants, function versions and bucket policies.
2. Apply only missing files in manifest order through the normal migration path, one migration transaction at a time. Preserve repository versions. Stop on the first error and inspect the actual ledger before retrying. A lost receipt after commit is not permission to repeat DDL.
3. Inspect the resulting catalogue. A15's development baseline is **31 assurance tables, all forcing RLS; zero assurance-table grants to `anon`, `authenticated` or `service_role`; 26 `api.assurance*` functions, none executable by `anon`; no client-executable assurance helpers**. The service-only RPCs are `assurance_evidence_service_target`, `assurance_evidence_service_verify` and `assurance_evidence_service_download`; verify precise grants. Global migration/API totals vary by target.
4. Confirm five seeded system roles in eligible tenants, `assurance_seed_roles_on_tenant` and assurance permissions on existing tenant-owner roles. Seeding does **not** assign assurance roles to members. Member grants require the owner's exact member, role and tenant/entity/branch scope; use the audited API/UI with a tenant-wide role manager and fresh MFA. Never create real accounts or manufacture MFA claims for acceptance.
5. Confirm private bucket `jentra-assurance-evidence`, 100 MiB limit and all six assurance storage policies, including their interaction with existing target policies. Verify clients cannot replace/delete submitted evidence.
6. Deploy both evidence functions with **`verify_jwt = false` at the gateway** and **`withSupabase({ auth: "user" })` inside each function**, matching `config.toml` and the hashed sources. The wrapper verifies the session; caller-scoped RPCs mint one-use tickets and service-only RPCs recheck authority before storage access. Keep service credentials in function secrets. Record actual deployed versions and resolved dependencies; development version numbers do not establish production versions.
7. Check missing/invalid login returns 401, denied scope returns a safe refusal and malformed input reaches no privileged storage operation. Complete an authenticated upload → verify → review/download, matching SHA-256/size and rejecting foreign scope. Retain safe results only, never tokens or signed URLs.
8. Run the approved installed rollback suite against the result, verify no fixtures remain and run security advisors. Development's informational RLS-without-policy findings are intentional because guarded APIs have no client table grants; review fresh warnings/errors on their merits.
9. Smoke-test the intended desktop release with real accounts, MFA and selected scope. Record installation, native acceptance and owner sign-off separately, then hand over release/recovery records.

## Stored-text comparison and final newline

The 20 October development record says ledger text for `20261020072901_assurance_plan_register.sql` lacks only the repository file's final newline. SQL behavior is identical. **Disposition: accepted nonfunctional serialization difference; no migration, redeploy or ledger rewrite is required.** Keep the reviewed file and raw-byte SHA-256 unchanged. Retain raw comparison results and this exact exception; never normalize arbitrary differences into a pass.

The 18 October record separately identifies comment-only ledger differences in the first four migrations. Preserve those records. Compare executable statements explicitly if those differences recur; do not claim all ledger text is byte-identical or edit applied files to force equality.

## Failure handling and recovery

- A failed transactional migration should roll back its own statements. Inspect ledger/catalogue before retrying. Earlier committed migrations remain applied; record partial state and stop promotion until reviewed.
- Prefer a reviewed **new forward-fix migration** for schema defects. Test against the actual partial state, preserve audit history/holds/evidence and obtain approval for changed production scope. Never edit applied migrations or fabricate ledger entries.
- For an app defect, return to the previously approved desktop/function release only after checking compatibility with the installed schema. A function rollback cannot undo schema changes. Record old/new source hashes and versions.
- For security/integrity incidents, suspend affected operations through a reviewed, target-specific containment change, preserve evidence and stop further writes. Do not blindly revoke service access needed by recovery. Contact the named owner and recovery operator.
- If restore is required, restore verified database and storage recovery points to the approved recovery destination, validate references/digests/holds and reconcile later writes before cutover. Cutover and loss of newer data need explicit owner approval.
- This runbook provides no schema-cascade, evidence-deletion or ledger-deletion rollback. History and legal holds must survive recovery. Even an empty installation needs a separately reviewed compensating migration before removal.

## Current unverified gates

Production target/approval/window, member-role-scope mapping, genuine MFA, authenticated native Windows flow, real evidence round trip, screen-reader walkthrough, contention/load and owner screen sign-off remain pending unless newer linked evidence explicitly establishes them. The Firebase admin key must stay out of commits and deployment packets.
