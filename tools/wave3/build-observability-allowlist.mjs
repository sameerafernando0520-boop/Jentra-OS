import fs from 'node:fs';
const manifest=JSON.parse(fs.readFileSync('docs/verification/remaining-wave3/migration-order-final-20260930-45.json','utf8'));
const files=new Set(manifest.candidates.map(r=>r.path));
for(const name of fs.readdirSync('supabase/migrations')) {
 if(/wave3|crm_pipeline|quotation_workspace|sales_order_workspace|complete_delivery_receivables/.test(name))files.add('supabase/migrations/'+name);
}
const names=new Set();
// These eight named RPCs are created by a reviewed SQL loop using api.%I.
const generatedReceivables=fs.readFileSync('supabase/migrations/20260910135010_complete_delivery_receivables.sql','utf8');
for(const kind of ['delivery','sales_invoice','customer_receipt','sales_return']) {
 for(const action of ['upsert','post']) {
  const name=action+'_'+kind;
  if(!generatedReceivables.includes("'"+name+"'"))throw Error('Missing generated receivables RPC '+name);
  names.add(name);
 }
}
const generatedBills=fs.readFileSync('supabase/migrations/20260913007000_procurement_supplier_bills.sql','utf8');
for(const name of ['post_supplier_bill','approve_supplier_bill_match','cancel_supplier_bill']) {
 if(!generatedBills.includes("'"+name+"'"))throw Error('Missing generated supplier-bill RPC '+name);
 names.add(name);
}
const codes=new Set(['40001','42501','23505','55000','54000']);
for(const file of files) {
 if(!file || !fs.existsSync(file))throw Error('Missing candidate path '+file);
 const sql=fs.readFileSync(file,'utf8');
 for(const m of sql.matchAll(/message\s*=\s*'([A-Z][A-Z0-9_]{1,63})'/g))codes.add(m[1]);
 for(const m of sql.matchAll(/create\s+(?:or\s+replace\s+)?function\s+api\.([a-z_][a-z0-9_]*)/gi)) {
  if(!/stock_opening|people_|invitation|bootstrap|register_attachment|complete_attachment/.test(m[1]))names.add(m[1]);
 }
}
const target='packages/jentra_platform/lib/src/wave3_observability_allowlist.dart';
fs.writeFileSync(target,'// Allowlisted public Wave 3 RPCs and fixed outcome codes from reviewed sources.\n// Regenerate with tools/wave3/build-observability-allowlist.mjs.\nconst wave3ObservedRpcs = <String>{\n'+[...names].sort().map(n=>`  '${n}',`).join('\n')+'\n};\nconst wave3ObservedOutcomeCodes = <String>{\n'+[...codes].sort().map(n=>`  '${n}',`).join('\n')+'\n};\n');
console.log(JSON.stringify({target,operations:names.size,codes:codes.size}));
