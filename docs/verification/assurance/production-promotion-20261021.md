# Assurance production promotion — approval packet, 21 October 2026

**Prepared for review; production is not approved or changed.** Production project reference: **pending owner identification**. Development project `xpdoufauvrbdmxgngetv` is not the production target.

The [manifest](production-promotion-20261021.manifest.json) fixes order, raw-byte SHA-256 and byte length for all 15 assurance migrations, both evidence-function bundles and their configuration. It was generated from repository files on 21 October 2026. Recompute hashes at approval/deployment; any difference requires review. The [runbook](../../development/corporate-audit-installation-runbook.md) describes application, verification and recovery.

## Proposed change and effect

Apply the target's missing assurance migrations in manifest order, from engagement core (`20261018153931`) through people (`20261020093822`), after verifying prerequisite migrations. This installs guarded audit planning, engagements, evidence, testing, findings/remediation, versioned reports/export, roles/access, settings, reminders, metrics and member labels. Deploy `assurance-evidence-verify` and `assurance-evidence-download` from the hashed sources.

The access migration seeds five system roles and gives existing tenant-owner roles assurance capabilities. It does not assign those five roles to members. Existing owners' added capabilities are part of the production change for review. Reminder scans run when a lead opens the workspace or chooses Send reminders; no background scheduler is introduced.

The evidence bucket is private, limited to 100 MiB per object. Verification hashes stored bytes; download uses a one-use authorization ticket and 60-second signed URL. The device checks SHA-256/size before saving. Both functions have gateway JWT checking **off** and enforce login through `withSupabase({ auth: "user" })`. No service key or signed URL belongs in this packet.

## Manifest migration order

| Order | Version | Migration |
|---|---|---|
| 1 | 20261018153931 | assurance_engagement_core |
| 2 | 20261018154123 | assurance_testing_carry_forward |
| 3 | 20261018154309 | assurance_evidence_adapters_export |
| 4 | 20261018154450 | assurance_adapters_monitoring |
| 5 | 20261018155008 | assurance_universe_plans |
| 6 | 20261018155041 | assurance_workspace |
| 7 | 20261020072622 | assurance_version_guard |
| 8 | 20261020072800 | assurance_evidence_storage |
| 9 | 20261020072901 | assurance_plan_register |
| 10 | 20261020073016 | assurance_access |
| 11 | 20261020073524 | assurance_settings |
| 12 | 20261020093705 | assurance_reminders |
| 13 | 20261020093743 | assurance_metrics |
| 14 | 20261020093817 | assurance_evidence_download |
| 15 | 20261020093822 | assurance_people |

The final-newline difference recorded for development migration `20261020072901` is accepted as nonfunctional. Keep source hash and ledger unchanged. The first four development ledger texts have documented comment-only differences; original installation records retain those comparison results.

## Evidence and limitations

- Development installation is recorded for [A1–A5](installation-dev-20261018.json) and [version guard–A14](installation-dev-20261020.json). The latter records 31 forced-RLS tables, zero client table grants, 26 assurance API functions, private evidence storage and seeded roles. These are historical development observations; this packet makes no fresh production catalogue claim.
- On 21 October 2026, `node --test supabase/functions/tests/assurance_evidence_verify.test.mjs supabase/functions/tests/assurance_evidence_download.test.mjs` passed **12/12**. This verifies isolated handlers, including missing-user refusal and scope validation; it does not establish authenticated deployed-wrapper or storage behavior.
- CI must pass for the exact proposed revision: migration chain, database lint, cumulative installed pgTAP, analyzers, domain/platform/desktop tests, secret scan and Windows build. Link the actual run before approval; old results do not establish the proposed revision.
- Member assignment, genuine MFA, authenticated native Windows walkthrough, real upload/verify/download, screen-reader walkthrough, independent-session contention, target-scale latency and owner screen sign-off remain unverified. See the [native checklist](../../development/corporate-audit-native-acceptance.md) and [readiness matrix](../../development/corporate-audit-readiness-matrix.md). Source tests cannot mark these accepted.

## Fields required before approval

| Decision/evidence | Current value |
|---|---|
| Production project reference and owner | Pending |
| Exact release revision and green CI run | Pending |
| Read-only target ledger/prerequisite comparison; missing assurance suffix | Pending |
| Recomputed manifest equality | Pending at approval/deployment |
| Staging rehearsal and installed rollback-suite result | Pending |
| Backup/PITR point, storage recovery point and restore rehearsal | Pending |
| Maintenance window, recovery contact, outage/data-loss limit | Pending |
| Native/MFA/file/screen-reader evidence and owner screen sign-off | Pending |
| Contention and target-scale results | Pending |
| Exact member → role → tenant/entity/branch assignments | Pending; separate owner decision |
| Production approval naming this manifest | Pending |

## Proposed approval wording

After the fields above are complete, the owner may approve: “Install the missing assurance migrations and deploy the two evidence functions listed in `production-promotion-20261021.manifest.json`, with the verified hashes, to production project **[exact reference]** during **[window]**, using the linked recovery plan. The approved source revision and CI run are **[revision/run]**.” This template is not approval and does not authorize member grants or replace screen sign-off.

Stop on a failed gate or conflicting target state. Preserve migration history and business evidence; use a reviewed forward fix, compatible prior release or rehearsed restore as described in the runbook. Never delete assurance history, holds, evidence or ledger rows to manufacture a clean result.
