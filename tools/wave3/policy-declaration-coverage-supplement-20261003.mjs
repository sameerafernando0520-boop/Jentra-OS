import fs from 'node:fs';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {artifactTag, writeNewJson} from './strict-candidate-evidence.mjs';

const file='packages/jentra_domain/lib/src/negative_stock_policy_repository.dart';
const expectedHash='a0cfa5c78ad1d383e7b96a1058d07673ae2b97957e1dedc6fbc6135d1c13e90a';
const canonical='abstractinterfaceclassNegativeStockPolicyRepository{Future<NegativeStockPolicy>readPolicy(TenantContextscope);Future<NegativeStockEvidencePage>evidence(TenantContextscope,NegativeStockEvidenceKindkind,{BigInt?after,});Future<CommandResult<NegativeStockPolicy>>configure(CommandEnvelope<Map<String,Object?>>command,);}';
const strip=source=>source.replace(/\/\*[\s\S]*?\*\//g,'').replace(/\/\/[^\n]*/g,'').replace(/^\s*(?:library|import|export)\b[^;]*;/gm,'').replace(/\s/g,'');
export function supplement(report,capture,source,sourceHash) {
  if(sourceHash!==expectedHash||strip(source)!==canonical||!capture.files.some(row=>row.file===file&&row.sha256===expectedHash))throw Error('Exact selected-policy interface/source/capture mismatch.');
  const reviewed=structuredClone(report),row=reviewed.files.find(row=>row.file===file);
  if(!row||row.source_sha256!==expectedHash||!row.changed||row.measured||row.lines!==0||row.branches!==0)throw Error('Selected-policy interface unexpectedly executable or unreviewed.');
  row.declarations_only=true;row.execution_source_matches=true;
  for(const total of [reviewed.changed_dart,reviewed.pure_domain]) {
    total.unmeasured_executable=total.unmeasured_executable.filter(path=>path!==file);
    total.source_mismatches=total.source_mismatches.filter(path=>path!==file);
  }
  reviewed.gates.changed_dart_line_80=reviewed.changed_dart.line_percent>=80&&!reviewed.changed_dart.unmeasured_executable.length&&!reviewed.changed_dart.source_mismatches.length;
  reviewed.gates.pure_domain_branch_90=reviewed.pure_domain.branch_percent>=90&&!reviewed.pure_domain.unmeasured_executable.length&&!reviewed.pure_domain.source_mismatches.length;
  for(const key of ['files','lines','lines_hit','branches','branches_hit','line_percent','branch_percent']) {
    assert.equal(report.changed_dart[key],reviewed.changed_dart[key]);assert.equal(report.pure_domain[key],reviewed.pure_domain[key]);
  }
  assert.equal(report.files.length,reviewed.files.length);
  reviewed.policy_declaration_correction={file,sha256:expectedHash,abstract_methods:3,executable_lines:0,
    boundary:'Only one exact new abstract interface declaration and paired-source flags are corrected. Named parameter braces and a generic Map type have no method bodies. All194 cumulative paths, actual executable hits/lines/branches/denominators and80/90 thresholds remain unchanged. Rawreport and earlier two-interface correction remain preserved.'};
  return reviewed;
}
if(process.argv.includes('--self-test')) {
  const source=canonical;
  const row={file,source_sha256:expectedHash,changed:true,measured:false,lines:0,branches:0};
  const total={files:194,lines:100,lines_hit:80,branches:100,branches_hit:90,line_percent:80,branch_percent:90,unmeasured_executable:[file],source_mismatches:[file]};
  const report={files:[row],changed_dart:total,pure_domain:{...total,files:25},gates:{changed_dart_line_80:false,pure_domain_branch_90:false}};
  const capture={files:[{file,sha256:expectedHash}]};
  assert.equal(supplement(report,capture,source,expectedHash).gates.changed_dart_line_80,true);
  assert.equal(report.gates.changed_dart_line_80,false);
  const low=structuredClone(report);low.changed_dart.line_percent=79.9;
  assert.equal(supplement(low,capture,source,expectedHash).gates.changed_dart_line_80,false);
  const other=structuredClone(report);other.changed_dart.unmeasured_executable.push('executable.dart');
  assert.equal(supplement(other,capture,source,expectedHash).gates.changed_dart_line_80,false);
  assert.throws(()=>supplement(report,{files:[]},source,expectedHash),/mismatch/);
  assert.throws(()=>supplement(report,capture,source,'changed'),/mismatch/);
  assert.throws(()=>supplement(report,capture,source.replace('readPolicy(TenantContextscope);','readPolicy(TenantContextscope)=>fetch();'),expectedHash),/mismatch/);
  const body=structuredClone(report);body.files[0].measured=true;
  assert.throws(()=>supplement(body,capture,source,expectedHash),/executable/);
  assert.equal(crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'),expectedHash);
  assert.equal(strip(fs.readFileSync(file,'utf8')),canonical);
  console.log('Selected-policy exact-interface supplement self-test passed: source/capture/body/threshold/remaining-executable guards; allcounts unchanged.');
} else {
  const base='docs/verification/remaining-wave3/';
  const [reportPath,capturePath,selectedTag='20261003']=process.argv.slice(2);
  const tag=artifactTag(selectedTag);
  if(!reportPath||!capturePath)throw Error('Pass actual source-checked report and fresh paired execution capture.');
  const read=path=>JSON.parse(fs.readFileSync(path,'utf8').replace(/^\uFEFF/,''));
  const hash=path=>crypto.createHash('sha256').update(fs.readFileSync(path)).digest('hex');
  const result=supplement(read(reportPath),read(capturePath),fs.readFileSync(file,'utf8'),hash(file));
  const output=base+`requirements-coverage-policy-declaration-reviewed-${tag}.json`;
  const out={...result,generated_at:new Date().toISOString(),policy_declaration_input:{file:reportPath,sha256:hash(reportPath)},policy_declaration_paired_execution_capture:{file:capturePath,sha256:hash(capturePath)}};
  writeNewJson(output,out);
  console.log(JSON.stringify({output,selected_paths:out.changed_dart.files,changed_dart:out.changed_dart.line_percent,gates:out.gates}));
}
