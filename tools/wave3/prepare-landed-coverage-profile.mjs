import fs from 'node:fs';
const root='docs/verification/remaining-wave3/';
const profile=JSON.parse(fs.readFileSync('build/remaining-wave3/coverage-profile-value-20261001.json','utf8'));
profile.inputs[1][0]='build/remaining-wave3/desktop-landed-full-coverage-20261001.info';
profile.inputs[2][0]='build/remaining-wave3/platform-landed-full-coverage-20261001.info';
profile.inputs.push(['build/remaining-wave3/landed-procurement-interaction-final-20261001.info','apps/jentra_desktop']);
profile.source_fingerprint=root+'client-sources-landed-start-20261001.json';
profile.changed_paths='build/remaining-wave3/changed-dart-paths-review-20261001.txt';
profile.output=root+'coverage-landed-reviewed-20261001.json';
profile.source_overrides=[{
  files:['apps/jentra_desktop/lib/src/features/landed_value/landed_value_controller.dart',
    'apps/jentra_desktop/lib/src/features/landed_value/landed_value_screen.dart'],
  source_fingerprint:root+'client-sources-landed-focused-20261001.json',
  inputs:[['build/remaining-wave3/landed-procurement-interaction-final-20261001.info','apps/jentra_desktop']],
}];
fs.writeFileSync('build/remaining-wave3/coverage-profile-landed-reviewed-20261001.json',JSON.stringify(profile,null,2)+'\n');
console.log('Prepared source-checked coverage profile; unresolved source drift remains explicit.');
