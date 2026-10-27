import test from "node:test";
import assert from "node:assert/strict";
import { handleDocument, sha256 } from "../people-private-documents/handler.mjs";

const id = n => `00000000-0000-4000-8000-${String(n).padStart(12,"0")}`;
async function fixture() {
  const metadata = {tenant_id:id(1),legal_entity_id:id(2),branch_id:id(3),document_id:id(4),document_version:7,publication_version:3,operation:"employee_download"};
  const bytes = new TextEncoder().encode("Synthetic employee-visible bytes");
  const path = [id(1),id(2),id(5),id(4)].join("/");
  const doc = {...metadata,employee_id:id(5),operation:"download",object_path:path,mime:"text/plain",byte_size:bytes.length,checksum:await sha256(bytes),status:"active"};
  const calls=[];
  const deps={userId:id(6),
    userRpc:async(name,args)=>{calls.push({name,args});return {ticket_id:id(7)};},
    adminRpc:async(name,args)=>{calls.push({name,args});return doc;},
    storage:{download:async(value)=>{assert.equal(value,path);return {data:new Blob([bytes])};}}
  };
  const request=(changes={})=>new Request("https://synthetic.invalid/private-documents",{method:"POST",headers:{
    "x-jentra-hr-request":Buffer.from(JSON.stringify({...metadata,...changes})).toString("base64")}});
  return {metadata,bytes,path,doc,calls,deps,request};
}
test("employee download derives subject server-side and rechecks after storage bytes",async()=>{
  const f=await fixture();const response=await handleDocument(f.request(),f.deps);
  assert.equal(response.status,200);
  assert.deepEqual(new Uint8Array(await response.arrayBuffer()),f.bytes);
  assert.deepEqual(f.calls.map(c=>c.name),["employee_document_access_ticket","people_hr_service_document","employee_document_access_ticket","people_hr_service_document"]);
  assert.deepEqual(f.calls[0].args,{p_tenant_id:id(1),p_legal_entity_id:id(2),p_branch_id:id(3),p_document_id:id(4),p_document_version:7,p_publication_version:3});
  assert.equal(response.headers.get("content-disposition"),'attachment; filename="hr-document.txt"');
  assert.equal(response.headers.get("cache-control"),"private, no-store");
  assert.equal(response.headers.get("x-jentra-hr-mime"),"text/plain");
});
test("employee selector, path, completion and unsafe versions are rejected before RPC",async()=>{
  const f=await fixture();
  for(const changes of [{employee_id:id(99)},{object_path:f.path},{completion:{}},{document_version:0},{document_version:1.1},{document_version:Number.MAX_SAFE_INTEGER+1},{publication_version:0},{publication_version:null}]) {
    assert.equal((await handleDocument(f.request(changes),f.deps)).status,400);
  }
  assert.equal(f.calls.length,0);
});
test("cross-scope, document revision and malformed server subjects discard bytes",async()=>{
  for(const [field,value] of [["branch_id",id(99)],["document_version",8],["publication_version",4],["employee_id","invalid"],["object_path","foreign/path"]]) {
    const f=await fixture();f.doc[field]=value;
    assert.equal((await handleDocument(f.request(),f.deps)).status,403);
  }
});
test("fresh service descriptor must match after storage and every issued ticket is consumed",async()=>{
  for(const [field,value] of [["checksum","0".repeat(64)],["mime","application/pdf"],["publication_version",4],["document_version",8]]) {
    const f=await fixture();let count=0;
    f.deps.adminRpc=async(name,args)=>{f.calls.push({name,args});return ++count===1?f.doc:{...f.doc,[field]:value};};
    const response=await handleDocument(f.request(),f.deps);
    assert.equal(response.status,403);
    assert.deepEqual(await response.json(),{code:"HR_DOCUMENT_DENIED"});
    assert.equal(count,2);
  }
});
test("revocation during storage never returns bytes or private errors",async()=>{
  const f=await fixture();let count=0;
  f.deps.userRpc=async()=>{if(++count>1)throw {code:"42501",message:f.path};return {ticket_id:id(7)};};
  const response=await handleDocument(f.request(),f.deps);
  assert.equal(response.status,403);assert.deepEqual(await response.json(),{code:"HR_DOCUMENT_DENIED"});
});
test("corrupt bytes and oversized stored objects never reach the employee",async()=>{
  const f=await fixture();f.deps.storage.download=async()=>({data:new Blob(["different"])});
  assert.equal((await handleDocument(f.request(),f.deps)).status,409);
  f.deps.storage.download=async()=>({data:{size:10*1024*1024+1,arrayBuffer:()=>{throw Error("must not read");}}});
  assert.equal((await handleDocument(f.request(),f.deps)).status,409);
});
