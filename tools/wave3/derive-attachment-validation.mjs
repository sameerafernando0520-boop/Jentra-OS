import fs from 'node:fs';
import crypto from 'node:crypto';
const sourcePath='supabase/migrations/20260901091132_validate_wave2_attachment_aggregates.sql';
const targetPath='supabase/migrations/20260927200629_wave3_operational_evidence.sql';
const source=fs.readFileSync(sourcePath,'utf8');
const target=fs.readFileSync(targetPath,'utf8');
const start=source.indexOf('create function core.validate_attachment_aggregate()');
const end=source.indexOf('\n$$;',start);
if(start<0||end<0||target.includes('create or replace function core.validate_attachment_aggregate()'))
 throw new Error('Validation source/target state changed');
const kinds=['lead','opportunity','quotation','sales_order','delivery','sales_invoice','customer_receipt','sales_return',
 'purchase_requisition','rfq','purchase_order','goods_receipt','supplier_bill','payment_proposal','supplier_payment',
 'purchase_return','inventory_transfer','stock_count','inventory_value_adjustment','manual_journal','budget','bank_statement','bank_match'];
let validator=source.slice(start,end+'\n$$;'.length)
 .replace('create function core.validate_attachment_aggregate()','create or replace function core.validate_attachment_aggregate()');
if(!validator.includes('    else false'))throw new Error('Original allowlist changed');
const cases=kinds.map(k=>`    when '${k}' then core.wave3_attachment_access(new.tenant_id,new.aggregate_type,new.aggregate_id)`).join('\n');
validator=validator.replace('    else false',cases+'\n    else false');
const marker='create function core.wave3_document_rows(';
if(!target.includes(marker))throw new Error('Insertion point changed');
fs.writeFileSync(targetPath,target.replace(marker,()=>validator+'\n'+marker));
console.log(JSON.stringify({original_validator_sha256:crypto.createHash('sha256').update(source).digest('hex'),kinds:kinds.length}));
