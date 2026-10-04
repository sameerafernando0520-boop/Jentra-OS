import fs from 'node:fs';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {artifactTag, writeNewJson} from './strict-candidate-evidence.mjs';

// Preserve the locked 25-file report, then explicitly account for newly added
// pure domain code using its already merged/source-checked executable records.
const base = 'docs/verification/remaining-wave3/';
const read = file => JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,''));
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
export function aggregate(report, additionalPaths, currentHash) {
  if (!Array.isArray(additionalPaths) || !additionalPaths.length || new Set(additionalPaths).size !== additionalPaths.length ||
      additionalPaths.some(file=>!/^packages\/jentra_domain\/lib\/src\/[a-z0-9_]+\.dart$/.test(file))) throw Error('Select explicit distinct new pure-domain paths.');
  const rows = additionalPaths.map(file=>report.files.find(row=>row.file===file));
  if (rows.some((row,index)=>!row || row.pure_domain || !row.changed || !row.measured || !row.execution_source_matches ||
      row.source_sha256 !== currentHash(additionalPaths[index]))) throw Error('Additional pure-domain record missing, stale, unmeasured, not cumulative, or already counted.');
  const total = structuredClone(report.pure_domain);
  total.files += rows.length;
  for (const row of rows) for (const key of ['lines','lines_hit','branches','branches_hit']) total[key] += row[key];
  total.line_percent = total.lines ? 100*total.lines_hit/total.lines : null;
  total.branch_percent = total.branches ? 100*total.branches_hit/total.branches : null;
  total.unmeasured_executable = [...report.pure_domain.unmeasured_executable];
  total.source_mismatches = [...report.pure_domain.source_mismatches];
  return {locked_pure_domain:report.pure_domain,additional_pure_domain:rows,combined_pure_domain:total,
    gates:{combined_pure_domain_branch_90:total.branch_percent>=90&&!total.unmeasured_executable.length&&!total.source_mismatches.length},
    boundary:'Explicit added pure-domain files extend the locked 25-file gate using source-matched actual measured branches. Original raw report, source scope, per-file hits/denominators and 90% threshold are preserved; no synthetic coverage or discarded executable paths.'};
}
if (process.argv.includes('--self-test')) {
  const file='packages/jentra_domain/lib/src/negative_stock_policy.dart';
  const row={file,changed:true,pure_domain:false,measured:true,execution_source_matches:true,source_sha256:'same',lines:10,lines_hit:9,branches:10,branches_hit:9};
  const pure={files:25,lines:100,lines_hit:90,branches:100,branches_hit:90,line_percent:90,branch_percent:90,unmeasured_executable:[],source_mismatches:[]};
  const report={files:[row],pure_domain:pure};
  const checked=aggregate(report,[file],()=> 'same');
  assert.equal(checked.combined_pure_domain.files,26);
  assert.equal(checked.combined_pure_domain.branches,110);
  assert.equal(checked.combined_pure_domain.branches_hit,99);
  assert.equal(checked.gates.combined_pure_domain_branch_90,true);
  assert.equal(pure.branches,100);
  const low=structuredClone(report);low.files[0].branches_hit=8;
  assert.equal(aggregate(low,[file],()=> 'same').gates.combined_pure_domain_branch_90,false);
  for (const flag of ['measured','execution_source_matches','changed']) {
    const invalid=structuredClone(report);invalid.files[0][flag]=false;
    assert.throws(()=>aggregate(invalid,[file],()=> 'same'),/missing/);
  }
  const duplicate=structuredClone(report);duplicate.files[0].pure_domain=true;
  assert.throws(()=>aggregate(duplicate,[file],()=> 'same'),/already counted/);
  assert.throws(()=>aggregate(report,[file,file],()=> 'same'),/distinct/);
  assert.throws(()=>aggregate(report,[file],()=> 'changed'),/stale/);
  console.log('Additional pure-domain aggregation self-test passed: preserves original counts, extends genuine measured scope, fails on low coverage, missing/stale/duplicated data.');
} else {
  const [reportPath,selectionPath,selectedTag='20261003'] = process.argv.slice(2);
  const tag=artifactTag(selectedTag);
  if (!reportPath || !selectionPath) throw Error('Pass source-checked coverage report and explicit additional pure-domain path list.');
  const selected=fs.readFileSync(selectionPath,'utf8').trim().split(/\r?\n/);
  const result=aggregate(read(reportPath),selected,hash);
  const out={generated_at:new Date().toISOString(),report:{file:reportPath,sha256:hash(reportPath)},selection:{file:selectionPath,sha256:hash(selectionPath)},...result};
  const output=base+`requirements-coverage-additional-pure-domain-${tag}.json`;
  writeNewJson(output,out);
  console.log(JSON.stringify({output,combined_pure_domain:out.combined_pure_domain,gates:out.gates}));
}
