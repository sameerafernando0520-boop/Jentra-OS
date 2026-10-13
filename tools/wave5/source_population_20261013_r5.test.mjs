import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { sourcePopulationSql } from './prepare_source_population_20261013_r5.mjs';
const review=JSON.parse(await fs.readFile(new URL('../../docs/verification/wave5/complete-app-runtime-review-20261010-r5.json',import.meta.url),'utf8'));
const actors={proposer:'8b740ab8-24f7-4455-a78b-aea0d99d20f6','foreign-member':'cb1e2d20-08b0-44f0-b012-a76c47d0255a'};
test('missing, duplicate and injected scopes refuse SQL preparation',()=>{
 assert.throws(()=>sourcePopulationSql(review.syntheticScopes.slice(1),actors));
 assert.throws(()=>sourcePopulationSql([...review.syntheticScopes.slice(1),review.syntheticScopes[1]],actors));
 assert.throws(()=>sourcePopulationSql([{...review.syntheticScopes[0],branchId:"';DROP TABLE core.tenants;--"},...review.syntheticScopes.slice(1)],actors));
});
test('real distinct actor bindings are required',()=>{
 assert.throws(()=>sourcePopulationSql(review.syntheticScopes,{...actors,proposer:'invented'}));
 assert.throws(()=>sourcePopulationSql(review.syntheticScopes,{...actors,proposer:actors['foreign-member']}));
});
test('rollback and commit differ only at the transaction terminator; only new scoped source records are inserted',()=>{
 const rollback=sourcePopulationSql(review.syntheticScopes,actors),commit=sourcePopulationSql(review.syntheticScopes,actors,true);
 assert.equal(commit,rollback.replace(/ROLLBACK;$/,'COMMIT;'));
 assert.doesNotMatch(commit,/(?:INSERT INTO|UPDATE|DELETE FROM) auth\.|request\.jwt\.claims|UPDATE core\.|DELETE FROM|CREATE (?:FUNCTION|SCHEMA)/i);
 assert.match(commit,/SOURCE_POPULATION_COLLISION_REQUIRES_RECONCILIATION/);
 assert.match(commit,/generate_series\(1,2\)/);assert.match(commit,/EXACT_NONEMPTY_SOURCE_COUNTS_REQUIRED/);
});
