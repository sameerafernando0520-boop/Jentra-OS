// Audit the two direct human replies received by the root in this conversation.
// This script cannot establish human provenance; the root verified the replies.
// Exclusive outputs keep the approved packet and original replies immutable.
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const base='docs/verification/wave5/';
const sha=b=>createHash('sha256').update(b).digest('hex');
const packetBytes=await readFile(path.join(root,base+'golden-owner-review-20261010-r2.json'));
const packet=JSON.parse(packetBytes);
if(packet.reviewSha256!=='fc9756a1847a12c94f18143607600e82825a2ddc69b31411b43a3d24e11d11aa'||
 packet.candidateBundleSha256!=='0e0426bf2e302afcc00adb9602bfb3a6448b6ac558fb85cceaf18d62027832bd'||
 sha(JSON.stringify(packet.reviewCore))!==packet.reviewSha256||packet.images.length!==83)throw Error('APPROVED_PACKET_DRIFT');
const common={kind:'direct-human-owner-decision',authorizationKind:'direct-human-message',submittedByOwner:true,
 reviewSha256:packet.reviewSha256,candidateBundleSha256:packet.candidateBundleSha256,
 packet:{path:base+'golden-owner-review-20261010-r2.json',sha256:sha(packetBytes)},
 provenanceNote:'The human replied to the exact packet questions in this chat. messageId below is the verbatim questionItemId supplied by the reply UI; an opaque platform message ID was not exposed. receivedAt is the root observation timestamp, not an inferred earlier send time.'};
const sourceMessage=index=>({role:'user',messageId:JSON.stringify(['request_user_input_async','call_3b49ddc5f8a64371a9dc5e16f4d0c097',index]),
 threadId:'01a121e1-81f0-76c1-8060-699f36ec225e',receivedAt:'2026-10-10T03:19:16Z'});
const imageReply='Approve all 83 proposed golden images';
const image={...common,messageVerbatim:imageReply,messageSha256:sha(imageReply),sourceMessage:sourceMessage(0),
 question:'Do you approve replacing those 83 approved golden images with the proposed candidates? Exact candidate bundle and owner review packet were linked. This does not approve runtime installation or production.',
 images:packet.images.map(i=>({approvedPath:i.approvedPath,candidateSha256:i.candidateSha256,decision:'accept'})),
 boundary:'Exactly 83 approved golden PNG replacements. No criterion, runtime installation, native, production or billing approval is inferred.'};
const criterionReply='Accept AC-551, AC-552 and AC-553';
const criterion={...common,messageVerbatim:criterionReply,messageSha256:sha(criterionReply),sourceMessage:sourceMessage(1),
 question:'Do you accept the complete AC-551, AC-552 and AC-553 statements and their 27 passing serial tests? The other 106 requirements remain open.',
 criteria:['AC-551','AC-552','AC-553'].map(id=>({id,decision:'accept-complete-criterion',decisionQuote:criterionReply,
 fullCriterionStatement:packet.requirements.find(r=>r.id===id).statement})),
 boundary:'Exactly three complete pure-calculation criteria. Other 106 requirements and whole-system signoff remain unaccepted.'};
for(const[name,data]of[['owner-golden-decision-20261010-r2.json',image],['owner-criterion-decision-20261010-r2.json',criterion]]){
 const bytes=Buffer.from(JSON.stringify(data,null,2)+'\n');await writeFile(path.join(root,base+name),bytes,{flag:'wx'});
 console.log(JSON.stringify({path:base+name,sha256:sha(bytes),directHumanReply:data.messageVerbatim}));
}
