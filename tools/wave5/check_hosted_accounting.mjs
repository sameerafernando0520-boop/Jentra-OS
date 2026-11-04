import fs from 'node:fs/promises';
import {assessHostedAccounting} from './hosted_accounting.mjs';

if(process.argv.length!==3)throw Error('Usage: node tools/wave5/check_hosted_accounting.mjs <saved-snapshot.json>');
const file=await fs.open(process.argv[2],'r');
let value;
try{
 const bytes=Buffer.alloc(1048577);
 let length=0;
 while(length<bytes.length){const part=await file.read(bytes,length,bytes.length-length,null);if(!part.bytesRead)break;length+=part.bytesRead;}
 if(length>1048576)throw Error('HOSTED_SNAPSHOT_LIMIT');
 value=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes.subarray(0,length)));
}catch{throw Error('INVALID_BOUNDED_HOSTED_SNAPSHOT');}
finally{await file.close();}
const snapshot=Array.isArray(value)&&value.length===1?value[0]?.hosted_accounting_snapshot
 :value?.hosted_accounting_snapshot??value;
const report=assessHostedAccounting(snapshot);
process.stdout.write(JSON.stringify(report,null,2)+'\n');
if(!report.ledgerReconciled)process.exitCode=2;
