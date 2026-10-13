import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {loadApprovedInputs} from './approved_management_installer.mjs';
import {hashBytes} from './runtime_contract.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/';
const expected={review:[base+'worker-routing-runtime-review-20261013-r5-a2.json','7b5f7f62dba4cfb5557285dd08af5f7239b192295b5dce44f4175da748492968'],
 peer:[base+'worker-routing-independent-peer-review-20261013-r5-a1.json','210bd493785e219343e83b7d6f3170ba81befa5fced55e00ce1b0d0a0858a24a'],
 html:['dist/Jentra OS Worker Routing Review 20261013 r5 a2.html','85330b60ba23182614773179ab041788f9ad76949ba144adcb0e329387e0f375']};
const must=(v,c)=>{if(!v)throw Error(c);};
await loadApprovedInputs();const found={};
for(const [kind,[file,sha]]of Object.entries(expected)){const b=await fs.readFile(path.join(root,file));must(hashBytes(b)===sha,'EXACT_ROUTING_READY_BINDING_REQUIRED');found[kind]=kind==='html'?b.toString('utf8'):JSON.parse(b);}
must(found.peer.passed&&found.peer.verdict==='approve-for-owner-review'&&found.peer.summary.tests===110&&found.peer.summary.fail===0
 &&found.peer.candidateBundleSha256===found.review.bundleSha256&&found.peer.selectedSourcesUnchanged,'INDEPENDENT_ROUTING_READINESS_REQUIRED');
for(const b of found.peer.filesAfter)must(hashBytes(await fs.readFile(path.join(root,b.path)))===b.sha256,'PEER_REVIEWED_SOURCE_CHANGED');
const rootLog=base+'worker-routing-root-peer-tests-20261013-r5.log',bytes=await fs.readFile(path.join(root,rootLog)),log=bytes.toString('utf8');
must(/# tests 5\s/.test(log)&&/# pass 5\s/.test(log)&&/# fail 0\s/.test(log),'ROOT_PEER_TESTS_REQUIRED');
const now=new Date().toISOString();
const html=found.html.replace('Independent review is pending.','Independent review is complete: 110 tests passed with zero failures or skips; all 5539 original inputs and the exact 15/9 file payload closures were verified. Root also reran the five independent probes successfully. No deployment or owner acceptance is implied.');
must(html!==found.html,'READY_PRESENTATION_CHANGE_REQUIRED');
const htmlPath='dist/Jentra OS Worker Routing Review 20261013 r5 a3.html';
const record={kind:'focused-worker-routing-owner-decision-ready',preparedAt:now,projectId:found.review.projectId,
 candidateBundleSha256:found.review.bundleSha256,ownerApproved:false,livePostPatchVerified:false,
 review:{path:expected.review[0],sha256:expected.review[1]},peerReview:{path:expected.peer[0],sha256:expected.peer[1]},
 rootPeerTest:{execChunkId:'5df556',exitCode:0,tests:5,passed:5,failed:0,log:{path:rootLog,sha256:hashBytes(bytes)}},
 originalReadyPresentation:{path:expected.html[0],sha256:expected.html[1]},
 currentReadyPresentation:{path:htmlPath,sha256:hashBytes(html)},
 sourcePayloadBytesChangedSinceIndependentReview:false,sourceScopeExpansion:false,newOwnerAcceptance:false};
await fs.writeFile(path.join(root,htmlPath),html,{flag:'wx'});
const recordPath=base+'worker-routing-owner-decision-ready-20261013-r5.json',recordBytes=JSON.stringify(record,null,2)+'\n';
await fs.writeFile(path.join(root,recordPath),recordBytes,{flag:'wx'});await loadApprovedInputs();
process.stdout.write(JSON.stringify({ready:true,candidateBundleSha256:record.candidateBundleSha256,record:{path:recordPath,sha256:hashBytes(recordBytes)},html:record.currentReadyPresentation,liveActions:false})+'\n');
