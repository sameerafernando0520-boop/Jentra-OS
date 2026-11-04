import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {main,validateCandidate} from '../run-field-rollout-test.mjs';
import {prepare} from '../../../tools/field-sales/prepare-rehearsal.mjs';
import {prepareReview} from '../../../tools/field-sales/prepare-rollout-review.mjs';
test('rollout runner rejects hosted targets before opening a database',async()=>{
 for(const args of [[],['--linked'],['--db-url','postgresql://forbidden.invalid/db'],['--run-isolated','--linked']])await assert.rejects(()=>main(args));
});
test('candidate composition cannot escape the transaction wrapper',async()=>{
 const source=await readFile(new URL('../20261102120000_field_confirmation_company_workspace.sql',import.meta.url),'utf8');
 assert.doesNotThrow(()=>validateCandidate(source));
 for(const suffix of ['\ncommit;','\nrollback;','\n\\ir other.sql'])assert.throws(()=>validateCandidate(source+suffix));
});
test('rehearsal preparation has no hosted execution or target override',async()=>{
 for(const args of [[],['--run-hosted'],['--prepare-only','--linked']])await assert.rejects(()=>prepare(args));
});

test('expanded rollout preparation cannot acquire execution authority from the old rehearsal',async()=>{
 for(const args of [[],['--run-hosted'],['--prepare-only','--linked'],['--install']])await assert.rejects(()=>prepareReview(args));
});
