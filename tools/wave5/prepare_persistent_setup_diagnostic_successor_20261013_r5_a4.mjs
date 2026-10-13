import fs from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {hashBytes} from './runtime_contract.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url));
let source=await fs.readFile(path.join(root,'tools/wave5/persistent_setup_20261013_r5_a3.mjs'),'utf8');
if(hashBytes(source)!=='53f2e198f8f99b43c3c191a75064588f837e3faa4fa424e23b3e13f2cad36586')throw Error('EXACT_FAILED_A3_SETUP_SOURCE_REQUIRED');
const replace=(before,after)=>{if(source.split(before).length!==2)throw Error('EXACT_SINGLE_DIAGNOSTIC_REPLACEMENT_REQUIRED');source=source.replace(before,after);};
replace("import {hashBytes} from './runtime_contract.mjs';", "import {hashBytes} from './runtime_contract.mjs';\nimport {runtimeSealKey,appendRuntimeSecret} from './private_runtime_seal.mjs';");
replace("base+'persistent-setup-20261013-r5-a3-'+Date.now()+'/'", "base+'persistent-setup-20261013-r5-a4-'+Date.now()+'/'");
replace("base+'persistent-setup-once-20261013-r5-a3.json'", "base+'persistent-setup-once-20261013-r5-a4.json'");
replace('function executeFixedSetup(token,sql){','function executeFixedSetup(token,sql,onPrivateHttpFailure){');
replace("res.on('end',()=>{if(settled)return;", "res.on('end',async()=>{if(settled)return;");
replace("error.responseSha256=hashBytes(raw);settled=true;clearTimeout(timer);reject(error);return;",
 "error.responseSha256=hashBytes(raw);settled=true;clearTimeout(timer);try{const diagnostic=await onPrivateHttpFailure(raw,res.statusCode);error.privateErrorRecord=diagnostic.privateErrorRecord;error.publicDiagnostic=diagnostic.publicDiagnostic;}catch{error.publicDiagnostic={category:'PRIVATE_DIAGNOSTIC_CAPTURE_FAILED'};}reject(error);return;");
replace("phase='persistent-commit';const written=await executeFixedSetup(config.ownerToken,sql);",
 `phase='persistent-commit';const sealingKey=runtimeSealKey(config.encryptionKey);
  const privateFailure=async(raw,status)=>{let value;try{value=JSON.parse(raw);}catch{value={responseBase64:raw.toString('base64')};}
   const privateErrorRecord=await appendRuntimeSecret(config.privateDirectory,sealingKey,'setup-error',{httpStatus:status,response:value,actualCapturedAt:new Date().toISOString()});
   const text=String(value.message??value.error?.message??'');
   const functionMatch=text.match(/function ([a-z_]+\\.[a-z_]+)\\([^\\n]*does not exist/i);
   const tableMatch=text.match(/permission denied for (?:table|relation) ([a-z_]+)/i);
   const readonly=/read-only transaction/i.test(text);
   const publicDiagnostic={category:functionMatch?'SQL_FUNCTION_UNAVAILABLE':tableMatch?'SQL_TABLE_PERMISSION_DENIED':readonly?'SQL_READ_ONLY_WRITE_REFUSED':'PRIVATE_ERROR_RETAINED',
    functionName:functionMatch?.[1]??null,tableName:tableMatch?.[1]??null,rawErrorPrinted:false};
   return {privateErrorRecord,publicDiagnostic};};
  let written;try{written=await executeFixedSetup(config.ownerToken,sql,privateFailure);}finally{sealingKey.fill(0);}`);
replace("responseSha256:error.responseSha256??null,automaticRetry:false", "responseSha256:error.responseSha256??null,privateErrorRecord:error.privateErrorRecord??null,publicDiagnostic:error.publicDiagnostic??null,automaticRetry:false");
replace("process.stderr.write(JSON.stringify({failureCode:error.publicCode??error.code??'FIXED_SETUP_STOP',secretsPrinted:false})+'\\n');",
 "process.stderr.write(JSON.stringify({failureCode:error.publicCode??error.code??'FIXED_SETUP_STOP',publicDiagnostic:error.publicDiagnostic??null,secretsPrinted:false})+'\\n');");
const destination='tools/wave5/persistent_setup_20261013_r5_a4.mjs';const h=await fs.open(path.join(root,destination),'wx');
try{await h.writeFile(source);await h.sync();}finally{await h.close();}
process.stdout.write(JSON.stringify({source:destination,sha256:hashBytes(source),networkCalls:0,previousSourcesPreserved:true,
 unchangedSqlMutation:true,diagnostic:'Any unsuccessful Management API response is encrypted outside the repository; only known SQL categories and names are public.'})+'\n');
