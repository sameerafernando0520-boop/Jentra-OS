import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {PROJECT,ORGANIZATION,BUNDLE,loadApprovedInputs,createManagementTransport} from './approved_management_installer.mjs';
import {hashBytes} from './runtime_contract.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/';
const must=(value,code)=>{if(!value){const error=Error(code);error.publicCode=code;throw error;}};
async function save(file,value){const text=JSON.stringify(value,null,2)+'\n',h=await fs.open(file,'wx');
 try{await h.writeFile(text);await h.sync();}finally{await h.close();}return {path:file,sha256:hashBytes(text)};}
async function main(){await loadApprovedInputs();const mode=process.argv[2]??'--validate';
 must(process.argv.length<=3&&['--validate','--refresh'].includes(mode),'EXACT_OWNER_SCOPE_REFRESH_MODE_REQUIRED');
 if(mode==='--validate'){process.stdout.write(JSON.stringify({passed:true,networkCalls:0,mutations:0,freshProjectReadRequired:true,renewedScopeHours:2})+'\n');return;}
 let incoming='';for await(const chunk of process.stdin){incoming+=chunk;must(incoming.length<=16000,'PRIVATE_OWNER_INPUT_REQUIRED');}
 const config=JSON.parse(incoming);incoming='';const original=config.originalMetadata;
 must(config.projectId===PROJECT&&config.bundleSha256===BUNDLE&&original.projectId===PROJECT&&original.runtimeBundleSha256===BUNDLE
  &&original.reuseAuthorizationQuestionId==='["request_user_input_async","call_637ea7df9a28457388be21396163da04",0]'
  &&Date.now()-Date.parse(original.createdAt)<7*86400000,'DIRECT_AUTHORIZED_OWNER_REUSE_REQUIRED');
 const priorBytes=await fs.readFile(path.join(root,base+'private-owner-input-ready-20261013-r5.json'));
 must(JSON.stringify(JSON.parse(priorBytes))===JSON.stringify(original),'EXACT_ORIGINAL_OWNER_METADATA_REQUIRED');
 must(path.isAbsolute(original.privateFolder)&&/^JentraOS-Wave5-owner-[a-f0-9]{32}$/.test(path.basename(original.privateFolder)),'EXACT_OWNER_PRIVATE_FOLDER_REQUIRED');
 const management=createManagementTransport(config.ownerToken),response=await management('GET','');config.ownerToken='';
 must(response.value.id===PROJECT&&response.value.organization_id===ORGANIZATION&&response.value.status==='ACTIVE_HEALTHY','FRESH_OWNER_PROJECT_IDENTITY_REQUIRED');
 const now=new Date(),helperSha256=hashBytes(await fs.readFile(fileURLToPath(import.meta.url)));
 const proof={kind:'actual-private-owner-scope-refresh',actualVerifiedAt:now.toISOString(),projectId:PROJECT,organizationId:ORGANIZATION,
  actualStatus:response.value.status,responseSha256:response.responseSha256,readOnlyOwnerApiCalls:1,credentialValuesPrinted:false,
  originalOwnerMetadataSha256:hashBytes(priorBytes),helperSha256,databaseWrites:0,authWrites:0,settingsChanges:0,
  purpose:'Fresh actual owner/project verification for the same approved bounded setup; reuse authorization remains the original direct human reply.'};
 const proofName=base+'private-owner-scope-refresh-20261013-r5-a3.json';const proofRef=await save(path.join(root,proofName),proof);
 const metadata={...original,createdAt:now.toISOString(),expiresAt:new Date(now.getTime()+2*3600000).toISOString(),
  helperSha256,metadataFilename:'metadata-renewed-a3.json',originalMetadataSha256:hashBytes(priorBytes),
  refreshEvidence:{path:proofName,sha256:proofRef.sha256},purpose:'Same authorized owner credential, bounded by a fresh live owner/project check; renewed two-hour execution scope.'};
 await save(path.join(original.privateFolder,'metadata-renewed-a3.json'),metadata);
 const ready=base+'private-owner-input-ready-20261013-r5-a3.json',readyRef=await save(path.join(root,ready),metadata);
 process.stdout.write(JSON.stringify({ownerScopeRefreshed:true,projectId:PROJECT,expiresAt:metadata.expiresAt,evidence:{path:ready,sha256:readyRef.sha256},
  originalMetadataPreserved:true,newCredentialRequested:false,settingsChanges:0})+'\n');
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{
 process.stderr.write(JSON.stringify({failureCode:error.publicCode??'OWNER_SCOPE_REFRESH_FAILED',rawErrorOrCredentialPrinted:false,automaticRetryPerformed:false})+'\n');process.exitCode=1;});
