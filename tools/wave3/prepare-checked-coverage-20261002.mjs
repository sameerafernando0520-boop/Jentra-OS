import fs from 'node:fs';
const base='docs/verification/remaining-wave3/';
const entries=[
 ['domain-branch-coverage-final5-20260930','packages/jentra_domain','client-sources-read-access-start-20260930'],
 ['desktop-final-current-20261001','apps/jentra_desktop','client-sources-final-current-start-20261001'],
 ['platform-final-current-20261001','packages/jentra_platform','client-sources-final-current-start-20261001'],
 ['desktop-full-20261002','apps/jentra_desktop','client-sources-full-start-20261002'],
 ['platform-full-20261002','packages/jentra_platform','client-sources-platform-final-start-20261002'],
 ['security-second-procurement-green-20261002','apps/jentra_desktop','security-second-procurement-sources-20261002'],
 ['security-review-finance-recovery-20261002','apps/jentra_desktop','security-finance-recovery-full-sources-20261002'],
 ['security-root-final-20261002','apps/jentra_desktop','client-sources-root-final-start-20261002'],
];
const checked_inputs=entries.map(([name,base,fingerprint])=>({file:`build/remaining-wave3/${name}.info`,base,source_fingerprint:`${basePath()}${fingerprint}.json`}))
 .filter(entry=>fs.existsSync(entry.file)&&fs.existsSync(entry.source_fingerprint));
function basePath(){return 'docs/verification/remaining-wave3/';}
const profile={inputs:checked_inputs.map(entry=>[entry.file,entry.base]),checked_inputs,
 source_fingerprint:base+'client-sources-platform-final-start-20261002.json',
 changed_paths:'build/remaining-wave3/changed-dart-paths-final-20261002.txt',
 output:base+'coverage-source-checked-20261002.json'};
fs.writeFileSync('build/remaining-wave3/coverage-profile-source-checked-20261002.json',JSON.stringify(profile,null,2)+'\n');
console.log(JSON.stringify({checked_inputs:checked_inputs.length,changed_paths:profile.changed_paths,output:profile.output}));
