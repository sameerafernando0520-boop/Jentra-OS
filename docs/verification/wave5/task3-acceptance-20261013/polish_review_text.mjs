import fs from 'node:fs';

const folder = 'docs/verification/wave5/task3-acceptance-20261013';
const substitutions = new Map([
  ['Original October10 direct human acceptance retained; the fresh domain check confirms the same25calculation+2filter cases without rewriting the decision.', 'Original October 10 direct human acceptance retained; the fresh domain check confirms the same 25 calculation and 2 filter cases without rewriting the decision.'],
  ['Original43ledgerentries and six originals', 'Original 43 ledger entries and six originals'],
  ['Exact87source isolated domain snapshot', 'Exact 87 source bindings in an isolated domain snapshot'],
  ['Local240worker tests and48source/evidence bindings', 'Local 240 worker tests and 48 source/evidence bindings'],
  ['The2010/0/0 desktop result is a datedOctober10source snapshot. The later o13r6fullsuite ran out of memory after1384passes; an isolated9requisitioncase rerun passed.', 'The 2,010/0/0 desktop result is a dated October 10 source snapshot. The later o13r6 full suite ran out of memory after 1,384 passes; an isolated 9 requisition case rerun passed.'],
  ['original106review coverage', 'original 106 review coverage'],
  ['Original109historical rows', 'Original 109 historical rows'],
  ['directhuman', 'direct human'],
  ['approvedspecs', 'approved specifications'],
  ['noacceptedBy', 'no accepted-by identity'],
  ['exactauthority and actualcalculationcases', 'exact authority and actual calculation cases'],
  ['cannot beaccepted', 'cannot be accepted'],
  ['bounded,preserved andnot promoted', 'bounded, preserved and not promoted'],
]);
for (const name of ['publish_acceptance.mjs', 'validate_acceptance.mjs']) {
  const path = `${folder}/${name}`;
  let text = fs.readFileSync(path, 'utf8');
  for (const [before, after] of substitutions) text = text.replaceAll(before, after);
  fs.writeFileSync(path, text);
}
