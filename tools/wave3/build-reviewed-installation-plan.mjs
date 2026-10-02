import fs from 'node:fs';
import crypto from 'node:crypto';
const root='docs/verification/remaining-wave3/';
const manifestPath=root+'migration-order-final-20260930-45.json';
const raw=fs.readFileSync(manifestPath,'utf8'),manifest=JSON.parse(raw);
if(manifest.candidate_count!==45||manifest.installed_count!==37||manifest.candidates.some(c=>c.installed))throw Error('Re-review current manifest first');
const definitions=[['baseline',0,0],['procurement',1,12],['inventory',13,18],
 ['finance',19,34],['integrated_evidence',35,40],['inventory_dashboard_observability',41,45],
 ['installed_synthetic_checks',46,46],['native_owner_acceptance',47,47]];
const phases=definitions.map(([name,from,to],i)=>({name,dependencies:i?[definitions[i-1][0]]:[],
 description:from===0?'Pin checkout, ledger, catalogues, helper hashes and an owner-approved isolated snapshot':
 from<=45?'Apply only these reviewed candidate bodies in recorded dependency order':
 from===46?'Run strict installed rollback fixtures, independent authenticated sessions and target-scale plans/p95':
 'Use separately approved synthetic Windows profile and isolated compiled binary, then obtain owner signoff',
 duration_hours:0,duration_basis:'Not estimated; zero is a generator placeholder, not an installation ETA',
 ordinals:from>0&&from<=45?[from,to]:null,
 candidates:manifest.candidates.filter(c=>c.ordinal>=from&&c.ordinal<=to),
 validation_criteria:['Record exact target and actual ledger after the phase','Validate scoped grants, source/query hashes and approved phase invariants','Keep installed, synthetic and native evidence separate'],
 rollback_triggers:['Unexplained ledger, source, grant or signature drift','Failed migration or strict assertion','Unauthorized scope, partial effect or changed historical evidence','Measured target gate or native acceptance failure'],
 rollback:{before_writes:'Abort without changing the target',
 transaction_failure:'Rollback the failing transaction; stop further installation and retain diagnostics',
 successful_phase_before_business_writes:'Restore only the explicitly approved isolated snapshot, with owner authorization, or review an additive repair',
 after_business_writes:'Coordinated approved restore or additive forward repair; no journal, open-item, serial, attachment or ledger deletion',
 scope:'Never restore/reset shared acceptance or concurrent Wave 4; never execute generated destructive downgrade placeholders'},
 tasks:from>0&&from<=45?manifest.candidates.filter(c=>c.ordinal>=from&&c.ordinal<=to).map(c=>`Review/apply ordinal ${c.ordinal}: ${c.path} at SHA-256 ${c.sha256}`):
 ['Follow the corresponding reviewed runbook phase and obtain its specific external approval'],
 risk_level:'high',resources_required:['Owner-selected isolated target/profile','Explicit installation, fixture and native authorization','Verified snapshot and documented restore owner']}));
const plan={migration_id:'jentra-wave3-reviewed-45-20260930',migration_type:'database',complexity:'critical',
 source_system:'Development baseline xpdoufauvrbdmxgngetv: 37 installed through 20260929224939_wave4_private_hr',
 target_system:'Owner-approved isolated synthetic development target, not selected or installed under this prompt',
 manifest:manifestPath,manifest_sha256:crypto.createHash('sha256').update(raw).digest('hex'),
 estimated_duration_hours:null,approval_status:'pending_concrete_user_approval',
 compatibility:{evidence:root+'schema-compatibility-final-20260930.json',breaking:0,potential:8,owner_written_acceptance_required:true},
 phases,boundary:'Reviewed preparation artifact only. No persistent installation, fixture generation, resource allocation, native launch or credential changes authorized or executed.'};
fs.writeFileSync(root+'migration-plan-reviewed-20260930-45.json',JSON.stringify(plan,null,2)+'\n');
fs.writeFileSync(root+'rollback-reviewed-20260930-45.json',JSON.stringify({migration_id:plan.migration_id,manifest_sha256:plan.manifest_sha256,
 phases:phases.map(p=>({name:p.name,ordinals:p.ordinals,triggers:p.rollback_triggers,rollback:p.rollback})),boundary:plan.boundary},null,2)+'\n');
console.log(JSON.stringify({phases:phases.length,candidates:manifest.candidate_count,approved:false}));
