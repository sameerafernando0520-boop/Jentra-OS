import fs from 'node:fs';
import crypto from 'node:crypto';
const sourcePath='supabase/migrations/20260926008000_wave3_close_control_review.sql';
const targetPath='supabase/migrations/20260927200629_wave3_operational_evidence.sql';
const source=fs.readFileSync(sourcePath,'utf8');
const target=fs.readFileSync(targetPath,'utf8');
const start=source.indexOf('create function finance.build_cash_controls(t uuid,e uuid,d date) returns jsonb');
const end=source.indexOf('\nend $$;',start);
if(start<0||end<0) throw new Error('Original immutable cash-control source missing');
let helper=source.slice(start,end+'\nend $$;'.length+1);
const header='create function finance.build_cash_controls(t uuid,e uuid,d date) returns jsonb';
const branchLoop='for bank in select * from finance.cash_bank_accounts where tenant_id=t and legal_entity_id=e order by id loop';
if(!helper.includes(header)||!helper.includes(branchLoop)) throw new Error('Source helper contract changed');
helper=helper.replace(header,'create function finance.build_branch_cash_controls(t uuid,e uuid,b uuid,d date) returns jsonb')
 .replace(branchLoop,'for bank in select * from finance.cash_bank_accounts where tenant_id=t and legal_entity_id=e and branch_id=b order by id loop');
const marker='create function api.generate_operational_report(';
if(target.indexOf(marker)<0||target.includes('create function finance.build_branch_cash_controls(')) throw new Error('Target state unexpected');
fs.writeFileSync(targetPath,target.replace(marker,()=>helper+'\nrevoke all on function finance.build_branch_cash_controls(uuid,uuid,uuid,date) from public,anon,authenticated;\n\n'+marker));
console.log(JSON.stringify({source_sha256:crypto.createHash('sha256').update(source).digest('hex'),helper_sha256:crypto.createHash('sha256').update(helper).digest('hex')}));
