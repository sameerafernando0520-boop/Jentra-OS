import test from 'node:test';
import assert from 'node:assert/strict';
import {buildSuite,main} from '../run-company-access-test.mjs';
const include='\\ir ../20261028130000_company_access_administration.sql';
const harness=`begin;\n${include}\nrollback;\n`;
test('CA-A8 exact candidate stays inside one rollback',()=>{
 const suite=buildSuite('select 1;',harness);assert.match(suite,/^begin;/);assert.match(suite,/rollback;\s*$/);assert.doesNotMatch(suite,/^\\ir /m);
 assert.match(buildSuite('select 1;',harness.replaceAll('\n','\r\n')),/select 1/);
});
test('CA-A8 altered, repeated and external includes are refused',()=>{
 for(const h of [harness.replace(include,include+'.extra'),harness.replace(include,''),
  harness.replace('rollback;',include+'\nrollback;'),harness.replace('rollback;','\\ir external.sql\nrollback;')])assert.throws(()=>buildSuite('select 1;',h));
});
test('CA-A8 commits and extra transaction controls are refused',()=>{
 for(const sql of ['begin;','commit;','rollback;'])assert.throws(()=>buildSuite(sql,harness));
 for(const h of [harness.replace('rollback;','commit;'),'select 1;\n'+harness,harness.replace('begin;','begin;\ncommit;')])assert.throws(()=>buildSuite('select 1;',h));
});
test('CA-E8 real source composes without executing a database',async()=>assert.equal(await main(['--check']),0));
test('CA-A8 linked and hosted flags fail before CLI work',async()=>{
 for(const args of [[],['--linked'],['--db-url','postgresql://example.invalid'],['--run-local','--linked'],['--check','--run-local']])await assert.rejects(main(args),/hosted\/linked/);
});
