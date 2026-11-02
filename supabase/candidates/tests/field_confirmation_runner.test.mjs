import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {main,validateCandidate} from '../run-field-confirmation-test.mjs';

test('runner refuses hosted targets and arbitrary options before opening an engine',async()=>{
 for(const args of [[],['--linked'],['--db-url','postgresql://forbidden.invalid/db'],['--run-isolated','--linked']]){
  await assert.rejects(()=>main(args));
 }
});
test('candidate composition refuses direct transaction control and file includes',async()=>{
 const candidate=await readFile(new URL('../20261102090000_field_order_email_confirmation.sql',import.meta.url),'utf8');
 assert.doesNotThrow(()=>validateCandidate(candidate));
 for(const suffix of ['\ncommit;','\nrollback;','\n\\ir other.sql']){
  assert.throws(()=>validateCandidate(candidate+suffix));
 }
});
