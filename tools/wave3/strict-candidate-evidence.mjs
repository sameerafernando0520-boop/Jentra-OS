import assert from 'node:assert/strict';
import fs from 'node:fs';
import crypto from 'node:crypto';

export const sourceHash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');

// Some MCP responses wrap the JSON rows in a text content block. Decode only
// valid JSON values; the original saved response remains the execution source.
export function decodedResult(value) {
  if (typeof value === 'string' && /^[\s]*[\[{]/.test(value)) {
    try { return decodedResult(JSON.parse(value)); } catch { return value; }
  }
  if (Array.isArray(value)) return value.map(decodedResult);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, decodedResult(item)]));
  return value;
}

export function strictTapPlan(result) {
  const leaves = value => typeof value === 'string' ? [value] : value && typeof value === 'object' ? Object.values(value).flatMap(leaves) : [];
  const strings = leaves(decodedResult(result));
  if (strings.some(text => /not ok \d|Looks like you failed|Looks like you planned/.test(text))) throw Error('Failed TAP assertion or plan mismatch.');
  const successes = strings.flatMap(text => [...text.matchAll(/^ok (\d+)(?: -|\s*$)/gm)].map(match => Number(match[1])));
  const plans = strings.flatMap(text => [...text.matchAll(/^1\.\.(\d+)\s*$/gm)].map(match => Number(match[1])));
  if (!successes.length || plans.length !== 1 || plans[0] !== successes.length || successes.some((number, index) => number !== index + 1)) throw Error('Require one completed sequential TAP plan without missing, duplicate or truncated assertions.');
  return {assertions: successes.length, failures: 0, plan: plans[0]};
}

export function verifyStrictExecution(execution, query, expectedHash) {
  const transportSucceeded = execution.http_status === 200 || (execution.transport === 'connected_supabase_mcp' && execution.mcp_is_error === false);
  if (!transportSucceeded || execution.project_id !== 'xpdoufauvrbdmxgngetv' || execution.query_sha256 !== expectedHash || !execution.observed_at ||
      !/^\s*begin;/i.test(query) || !query.includes('finish(true)') || !/rollback;\s*$/i.test(query) || /^\s*commit\s*;/im.test(query)) throw Error('Execution transport, project, date, exact source or strict rollback boundary mismatch.');
  return strictTapPlan(execution.result);
}

export function verifyCandidateOrder(query, candidates, readSource = file => fs.readFileSync(file,'utf8')) {
  const fixtureBoundary=query.indexOf('create extension if not exists pgtap');
  if(fixtureBoundary<0||!Array.isArray(candidates)||candidates.length!==46)throw Error('Require all46 reviewed candidate bodies before the pgTAP fixture boundary.');
  let previous=-1;
  for(const [index,row]of candidates.entries()) {
    const body=readSource(row.path),offset=query.indexOf(body);
    if(row.ordinal!==index+1||offset<0||offset<=previous||offset+body.length>fixtureBoundary||query.indexOf(body,offset+1)>=0)throw Error('Executed candidate dependency order, duplication or fixture boundary mismatch.');
    previous=offset;
  }
  return {candidates:46,exact_order:true,before_fixtures:true};
}

export function artifactTag(value = '20261003') {
  if (!/^2026100[3456](?:-[a-z0-9]+)*$/.test(value)) throw Error('Use an explicit 20261003/20261004/20261005/20261006 artifact tag with optional lowercase iteration words.');
  return value;
}

export function writeNewJson(file, value) {
  fs.writeFileSync(file, JSON.stringify(value, null, 2) + '\n', {flag: 'wx'});
}

if (process.argv[1]?.replaceAll('\\', '/').endsWith('/strict-candidate-evidence.mjs') && process.argv.includes('--self-test')) {
  const good = {rows: [{tap: 'ok 1 - first'}, {tap: 'ok 2 - second'}, {tap: '1..2'}]};
  assert.deepEqual(strictTapPlan(good), {assertions: 2, failures: 0, plan: 2});
  assert.deepEqual(strictTapPlan({content: [{text: JSON.stringify(good)}]}), {assertions: 2, failures: 0, plan: 2});
  for (const bad of [
    {tap: 'ok 1 - truncated'}, {tap: 'ok 1 - missing\n1..2'},
    {tap: 'ok 1 - duplicate\nok 1 - duplicate\n1..2'},
    {tap: 'ok 1 - gap\nok 3 - gap\n1..2'},
    {tap: 'ok 1 - first\nnot ok 2 - fails\n1..2'},
    {tap: 'ok 1 - first\n1..1\n1..1'},
  ]) assert.throws(() => strictTapPlan(bad));
  const execution = {project_id: 'xpdoufauvrbdmxgngetv', transport: 'connected_supabase_mcp', mcp_is_error: false, query_sha256: 'exact', observed_at: '2026-10-03T00:00:00Z', result: good};
  const query = 'begin;\nselect finish(true);\nrollback;';
  assert.equal(artifactTag('20261005-role-reviewed'), '20261005-role-reviewed');
  assert.equal(artifactTag('20261006-tracking-fixed'), '20261006-tracking-fixed');
  assert.throws(() => artifactTag('20261007'));
  assert.equal(verifyStrictExecution(execution, query, 'exact').assertions, 2);
  for (const mutation of [{mcp_is_error: true}, {project_id: 'another'}, {query_sha256: 'changed'}, {observed_at: null}]) assert.throws(() => verifyStrictExecution({...execution, ...mutation}, query, 'exact'));
  assert.throws(() => verifyStrictExecution(execution, query.replace('rollback;', 'commit;'), 'exact'));
  const candidates=Array.from({length:46},(_,index)=>({ordinal:index+1,path:'candidate-'+String(index+1).padStart(2,'0')}));
  const body=file=>'-- BODY '+file+' END';
  const ordered='begin;\n'+candidates.map(row=>body(row.path)).join('\n')+'\ncreate extension if not exists pgtap;\nselect finish(true);\nrollback;';
  assert.equal(verifyCandidateOrder(ordered,candidates,body).exact_order,true);
  assert.throws(()=>verifyCandidateOrder(ordered.replace(body(candidates[0].path),body(candidates[1].path)),candidates,body));
  assert.throws(()=>verifyCandidateOrder(ordered+'\n'+body(candidates[0].path),candidates,body));
  assert.throws(()=>verifyCandidateOrder(ordered.replace('create extension if not exists pgtap;','').replace('begin;','begin;\ncreate extension if not exists pgtap;'),candidates,body));
  console.log('Strict candidate evidence self-test passed: real transport/source boundaries and complete sequential plan required; failures, gaps, duplicates and truncation rejected.');
}
