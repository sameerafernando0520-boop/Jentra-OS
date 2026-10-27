import test from "node:test";
import assert from "node:assert/strict";
import {buildSuite,main} from "../run-employee-cases-test.mjs";
const names=["20261023090000_employee_push.sql","20261025090000_employee_self_service.sql","20261025100000_employee_cases_documents_notifications.sql"];
const candidates=Object.fromEntries(names.map((n,i)=>[n,`select ${i};`]));
const harness=`begin;\n${names.map(n=>`\\ir ../${n}`).join("\n")}\nrollback;\n`;
test("runner inlines exactly the reviewed prerequisites inside rollback",()=>{
  const result=buildSuite(candidates,harness);
  assert.ok(result.startsWith("begin;"));assert.match(result,/rollback;\s*$/);
  assert.ok(!result.includes("\\ir"));for(let i=0;i<3;i++)assert.ok(result.includes(`select ${i};`));
});
test("runner rejects missing rollback, includes and nested transaction control",()=>{
  assert.throws(()=>buildSuite(candidates,harness.replace("rollback;","commit;")));
  assert.throws(()=>buildSuite(candidates,harness+"\\ir other.sql\n"));
  assert.throws(()=>buildSuite({...candidates,[names[1]]:"commit;"},harness));
  assert.throws(()=>buildSuite(candidates,harness.replace(`\\ir ../${names[1]}`,"")));
});
test("runner refuses hosted, linked and db URL options before CLI work",async()=>{
  for(const args of [[],["--linked"],["--run-local","--linked"],["--db-url","postgresql://synthetic.invalid"]])await assert.rejects(main(args));
});
