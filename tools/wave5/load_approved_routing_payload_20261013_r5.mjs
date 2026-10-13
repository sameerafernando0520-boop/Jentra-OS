import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {loadApprovedInputs,PROJECT} from './approved_management_installer.mjs';
import {hashBytes} from './runtime_contract.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/';
const must=(v,c)=>{if(!v)throw Error(c);};
const name=process.argv[2];must(['wave5-runtime','wave5-receiver'].includes(name)&&process.argv.length===3,'EXACT_ROUTING_FUNCTION_REQUIRED');
await loadApprovedInputs();
const reviewBytes=await fs.readFile(path.join(root,base+'worker-routing-runtime-review-20261013-r5-a2.json'));
must(hashBytes(reviewBytes)==='7b5f7f62dba4cfb5557285dd08af5f7239b192295b5dce44f4175da748492968','EXACT_ROUTING_REVIEW_REQUIRED');
const review=JSON.parse(reviewBytes),{bundleSha256,...body}=review;
must(bundleSha256==='bce677a0c8e53fea2ba44c30b81e0fa2d897d8f43af5dc6d109e2a1e6feaa552'&&hashBytes(JSON.stringify(body))===bundleSha256,'EXACT_ROUTING_BUNDLE_REQUIRED');
const decision=JSON.parse(await fs.readFile(path.join(root,base+'worker-routing-owner-decision-20261013-r5.json'),'utf8'));
must(decision.decision==='approve'&&decision.projectId===PROJECT&&decision.candidateBundleSha256===bundleSha256
 &&decision.source.kind==='direct_user_message'&&decision.source.preservedReply.length===1
 &&decision.source.preservedReply[0].questionItemId==='["request_user_input_async","call_1d5e39edc6404891a04c0aad1ddaa176",0]'
 &&decision.source.preservedReply[0].answer==='Approve the exact routing correction','EXACT_DIRECT_ROUTING_APPROVAL_REQUIRED');
const peerBytes=await fs.readFile(path.join(root,base+'worker-routing-independent-peer-review-20261013-r5-a1.json'));
must(hashBytes(peerBytes)==='210bd493785e219343e83b7d6f3170ba81befa5fced55e00ce1b0d0a0858a24a','EXACT_ROUTING_PEER_REQUIRED');
const peer=JSON.parse(peerBytes);must(peer.passed&&peer.selectedSourcesUnchanged&&peer.summary.tests===110&&peer.summary.fail===0,'PASSING_ROUTING_PEER_REQUIRED');
const deployment=review.deployments.find(d=>d.name===name),payloadBytes=await fs.readFile(path.join(root,deployment.payload.path));
must(hashBytes(payloadBytes)===deployment.payload.sha256,'EXACT_DEPLOYMENT_PAYLOAD_REQUIRED');
const payload=JSON.parse(payloadBytes);must(payload.link_id==='link_6aa8c9ca60408191b9e7e8344c5a6693'&&payload.project_id===PROJECT
 &&payload.name===name&&payload.verify_jwt===false&&payload.entrypoint_path===deployment.entrypoint
 &&payload.files.length===(name==='wave5-runtime'?15:9),'EXACT_DEPLOYMENT_SCOPE_REQUIRED');
for(const binding of deployment.files){const submitted=payload.files.find(f=>f.name===binding.path);
 must(submitted&&hashBytes(submitted.content)===binding.sha256&&hashBytes(await fs.readFile(path.join(root,binding.path)))===binding.sha256,'EXACT_REVIEWED_DEPLOYMENT_SOURCE_REQUIRED');}
process.stdout.write(JSON.stringify(payload));
