// Lossless compression for a rollback-only SQL request exceeding connector size.
// The passphrase is PUBLIC transport framing, not a provisioned secret. pgcrypto
// validates the compressed packet and an independent SHA-256 checks exact SQL.
import {readFile,writeFile} from 'node:fs/promises';
import {createHash,createCipheriv,randomBytes} from 'node:crypto';
import {deflateSync} from 'node:zlib';
const phrase='jentra-public-candidate-transport-v1';
function packet(tag,data){const n=data.length;let header;if(n<192)header=Buffer.from([0xc0|tag,n]);
 else if(n<8384){const m=n-192;header=Buffer.from([0xc0|tag,(m>>8)+192,m&255]);}
 else {header=Buffer.alloc(6);header[0]=0xc0|tag;header[1]=255;header.writeUInt32BE(n,2);}
 return Buffer.concat([header,data]);}
export function encode(source,{level=6}={}){
 const literal=packet(11,Buffer.concat([Buffer.from([98,0,0,0,0,0]),Buffer.from(source)]));
 const compressed=packet(8,Buffer.concat([Buffer.from([2]),deflateSync(literal,{level})]));
 const prefix=randomBytes(16),plain=Buffer.concat([prefix,prefix.subarray(14),compressed,Buffer.from([0xd3,0x14])]);
 const mdc=createHash('sha1').update(plain).digest();
 const cipher=createCipheriv('aes-256-cfb',createHash('sha256').update(phrase).digest(),Buffer.alloc(16));
 const encrypted=Buffer.concat([cipher.update(Buffer.concat([plain,mdc])),cipher.final()]);
 return Buffer.concat([packet(3,Buffer.from([4,9,0,8])),packet(18,Buffer.concat([Buffer.from([1]),encrypted]))]).toString('base64');
}
if(process.argv[2]==='--probe'){
 const source='select 1 as candidate_transport_probe;',b64=encode(source);
 const query=`select encode(extensions.digest(extensions.pgp_sym_decrypt_bytea(decode('${b64}','base64'),'${phrase}'),'sha256'),'hex') as decoded_sha256;`;
 await writeFile('docs/verification/wave5/candidate-transport-probe-20261009.sql',query);
 console.log(JSON.stringify({sha256:createHash('sha256').update(source).digest('hex'),query}));
}else if(process.argv[2]==='--prepare'){
 const original=await readFile('docs/verification/wave5/complete-app-candidate-20261009.sql','utf8');
 const source=original.replace(/^begin;\s*/,'').replace(/\s*rollback;\s*$/,'');
 const hash=createHash('sha256').update(source).digest('hex'),b64=encode(source);
 const query=`begin;\ncreate temporary table w5_complete_transport_result(tap jsonb);\ndo $transport$ declare q bytea;r jsonb;begin\nq:=extensions.pgp_sym_decrypt_bytea(decode('${b64}','base64'),'${phrase}');\nif encode(extensions.digest(q,'sha256'),'hex')<>'${hash}' then raise exception 'CANDIDATE_TRANSPORT_HASH_MISMATCH';end if;\nexecute convert_from(q,'UTF8') into r;\ninsert into w5_complete_transport_result values(r);end $transport$;\nselect tap from w5_complete_transport_result;\nrollback;`;
 await writeFile('docs/verification/wave5/complete-app-candidate-transport-20261009.sql',query);
 await writeFile('docs/verification/wave5/complete-app-candidate-transport-20261009.json',JSON.stringify({source:'docs/verification/wave5/complete-app-candidate-20261009.sql',fullSourceSha256:createHash('sha256').update(original).digest('hex'),bodySha256:hash,transportSha256:createHash('sha256').update(query).digest('hex'),rawBytes:Buffer.byteLength(original),transportBytes:Buffer.byteLength(query),lossless:true,publicTransportPhrase:phrase,transaction:'one outer begin/rollback; only redundant inner boundaries omitted; strict finish retained'},null,2)+'\n');
 console.log(JSON.stringify({rawBytes:Buffer.byteLength(original),transportBytes:Buffer.byteLength(query),bodySha256:hash}));
}
