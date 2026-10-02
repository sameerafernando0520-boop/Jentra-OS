import fs from 'node:fs';
import crypto from 'node:crypto';
const output=process.argv[2];
if(!output?.startsWith('docs/verification/remaining-wave3/')||!output.endsWith('.json'))throw Error('Use task-owned JSON evidence');
const files=fs.readFileSync(process.argv[3],'utf8').replace(/^\uFEFF/,'').trim().split(/\r?\n/).map(p=>p.replaceAll('\\','/'));
files.push('pubspec.yaml','pubspec.lock');
if(!/^[0-9a-f]{40}$/.test(process.argv[4]??''))throw Error('Supply freshly read Git HEAD');
const evidence={observed_at:new Date().toISOString(),head:process.argv[4],
 boundary:'Source fingerprint only; captures concurrent Wave 4/5 too, without claiming they belong to Wave 3 or are verified.',
 files:files.map(file=>({file,sha256:crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')}))};
fs.writeFileSync(output,JSON.stringify(evidence,null,2)+'\n');
console.log(JSON.stringify({output,files:files.length,head:evidence.head}));
