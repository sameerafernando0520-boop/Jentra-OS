import fs from 'node:fs';
import {execFileSync} from 'node:child_process';
import {sourceHash, writeNewJson} from './strict-candidate-evidence.mjs';
const base='docs/verification/remaining-wave3/';
const candidate='supabase/migrations/20261003090000_wave3_negative_stock_policy.sql';
const assertions='supabase/wave_tests/wave3_negative_stock_policy_20261003_test.sql';
if(sourceHash(candidate)!=='9cc3aaa66c884397dbbc47919f5f758682129e403d7c334eaffdc4bd53736f4a'||sourceHash(assertions)!=='c600ca2eae6c91fda4a1135a71ff59d1b28056292326e4a50f6769c01e1176bb')throw Error('Frozen policy197 sources changed.');
const check=(kind,tag,passed,failed=0)=>({kind,file:base+tag+'.log',source_capture:base+'client-sources-'+tag+'.json',passed,failed,complete:true,
  boundary:'Actual completed named synthetic local checks; complete source-capture drift remains visible and no native/install/load/owner acceptance is inferred.'});
const input={head:execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).trim(),
  database_package:base+'database-installation-package-negative-stock-policy-role-reviewed-20261004-46.json',
  coverage_scope:base+'requirements-coverage-paths-negative-stock-policy-20261003.txt',
  coverage_raw:base+'requirements-coverage-source-checked-20261004-boot-client.json',
  coverage_reviewed:base+'requirements-coverage-policy-declaration-reviewed-20261004-boot-client.json',
  coverage_additional_pure_domain:base+'requirements-coverage-additional-pure-domain-20261004-boot-client.json',
  desktop_failure_classification:base+'desktop-current-failure-classification-20261004.json',
  policy:{selection:'last_authoritative_positive_moving_average',approved:true,implemented_verified:false,
    owner_reply:'Approve interim issues at the last authoritative positive moving-average cost, block unknown cost basis, and post linked later-receipt variance corrections.',
    contract:'docs/blueprint/64_WAVE3_NEGATIVE_STOCK_POLICY_CONTRACT.md',candidate,assertions,
    dart_sources:['packages/jentra_domain/lib/src/negative_stock_policy.dart','packages/jentra_domain/lib/src/negative_stock_policy_repository.dart','packages/jentra_domain/lib/src/lead_to_cash.dart',
      'packages/jentra_platform/lib/src/supabase_negative_stock_policy_gateway.dart','packages/jentra_platform/lib/src/quotation_draft_store.dart',
      'apps/jentra_desktop/lib/src/features/negative_stock/negative_stock_policy_controller.dart','apps/jentra_desktop/lib/src/features/negative_stock/negative_stock_policy_screen.dart',
      'apps/jentra_desktop/lib/src/features/sales/quotation_controller.dart','apps/jentra_desktop/lib/src/features/sales/sales_order_controller.dart','apps/jentra_desktop/lib/src/features/sales/sales_order_dialogs.dart',
      'apps/jentra_desktop/lib/src/features/sales/sales_order_screen.dart','apps/jentra_desktop/lib/main.dart','apps/jentra_desktop/lib/src/router.dart','apps/jentra_desktop/lib/src/shell/navigation.dart']},
  checks:[check('domain-current-policy-scope','domain-policy-scope-green-20261003',318),check('platform-whole-recorded','platform-policy-full-20261003',1018),
    check('desktop-whole-recorded','desktop-current-20261004',1617,76),check('policy-controller-scoped-recovery','policy-controller-20261004',43),check('policy-widget-render-scoped-recovery','policy-widgets-final-20261004',20),
    check('sales-command-dialog-original-ack','sales-checked-20261004',88),check('preview-boot-crm-companion','entry-crm-20261004',9,1),
    {kind:'authorized-current-libraries-analyzer',file:base+'analyzer-closure-authorized-20261004.log',source_capture:base+'client-sources-analyze-closure-20261004.json',complete:true,outcome:'No issues found; actual libraries only, not full protected test analysis or native proof.'}],
  additional_review:[base+'acceptance-binding-procedure-20261004.md',base+'verification-resume-review-20261004.md',base+'supabase-transport-failure-20261004.json',
    base+'database-procurement-negative-stock-author-event-executed-20261004.json',base+'database-procurement-negative-stock-policy-event-executed-20261004.json',base+'database-procurement-negative-stock-multi-actor-red-executed-20261004.json',
    base+'policy-visual-review-20261004.json',base+'policy-visual-review-20261004.md']};
const output=base+'interim-matrix-input-20261004.json';
for(const file of [input.database_package,...input.additional_review,...input.checks.flatMap(row=>[row.file,row.source_capture])])if(!fs.existsSync(file))throw Error('Missingactual named evidence: '+file);
writeNewJson(output,input);console.log(JSON.stringify({output,checks:input.checks.length,implementation_verified:false}));
