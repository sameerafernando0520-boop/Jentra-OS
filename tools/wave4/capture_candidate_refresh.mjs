import fs from 'node:fs';
import crypto from 'node:crypto';
const input=JSON.parse(fs.readFileSync(0,'utf8'));
const evidence={review_date:'2026-10-02',query_sha256:crypto.createHash('sha256').update(input.query).digest('hex'),query:input.query,...input.evidence,
  boundary:'Read-only development ledger/API/helper refresh. No installation, production, authentication, native or acceptance-owned change.'};
fs.writeFileSync('docs/verification/wave4/candidate-refresh-20261002.json',JSON.stringify(evidence,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({ledger:evidence.ledger.length,api_functions:evidence.api_functions.length,observed_at:evidence.observed_at,query_sha256:evidence.query_sha256}));
