// Read only the exact reviewed local-account existence and target path metadata.
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {lstat,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const accountName='jentra-w5-runtime';
let exitCode=0,stdout='',stderr='';
try { ({stdout,stderr}=await promisify(execFile)(path.join(process.env.SystemRoot,'System32/net.exe'),['user',accountName],{windowsHide:true})); }
catch(e){if(typeof e.code!=='number')throw e;exitCode=e.code;stdout=e.stdout??'';stderr=e.stderr??'';}
const rawOutput=(stdout+'\n'+stderr).trim();
if(exitCode!==2||!rawOutput.includes('The user name could not be found')||!rawOutput.includes('2221'))throw Error('EXACT_NATIVE_ACCOUNT_ABSENCE_UNVERIFIED:'+exitCode);
const exists=async p=>{try{await lstat(p);return true;}catch(e){if(e.code==='ENOENT')return false;throw e;}};
const packageDirectory='C:/Users/Public/Documents/JentraWave5Runtime/20261009';
const record={observedAt:new Date().toISOString(),method:'Windows net.exe user exact local account',accountName,
 accountExistenceVerified:true,accountExists:false,exitCode,namedError:'NERR_UserNotFound / NET HELPMSG 2221',rawOutput,
 packageDirectory,packageDirectoryExists:await exists(packageDirectory),profileDirectoryExists:await exists('C:/Users/jentra-w5-runtime'),
 readOnly:true,accountOrSessionContentsRead:false,provisionedByThisCheck:false,
 previousUnverifiedRecordPreserved:'docs/verification/wave5/complete-live-preflight-20261010-r2-native.json',
 recordingAttempts:'Earlier PowerShell recording attempts wrote no file: exitCode1 was incorrect (actual2), and Set-Content has no NoClobber parameter. This record uses exclusive file creation.'};
const relative='docs/verification/wave5/complete-live-preflight-20261010-r2-native-net.json';
const bytes=Buffer.from(JSON.stringify(record,null,2)+'\n');await writeFile(path.join(root,relative),bytes,{flag:'wx'});
console.log(JSON.stringify({path:relative,sha256:createHash('sha256').update(bytes).digest('hex'),observedAt:record.observedAt,
 accountExistenceVerified:true,accountExists:false,packageDirectoryExists:record.packageDirectoryExists,profileDirectoryExists:record.profileDirectoryExists}));
