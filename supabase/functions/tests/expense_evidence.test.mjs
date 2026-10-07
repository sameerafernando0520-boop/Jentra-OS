import test from "node:test";
import assert from "node:assert/strict";
import { handleDocument, sha256 } from "../expense-private-documents/handler.mjs";
import { handlePurge } from "../expense-private-purge/handler.mjs";

const id = (n) => "00000000-0000-4000-8000-" + String(n).padStart(12, "0");
const scope = { tenant_id: id(1), legal_entity_id: id(2), branch_id: id(3), project_id: id(4), expense_id: id(15), document_id: id(5) };
const path = [id(1), id(2), id(4), id(15), id(5)].join("/");
function storage() {
  const objects = new Map();
  return {
    objects,
    async upload(path, bytes, options) {
      assert.equal(options.upsert, false);
      if (objects.has(path)) return { error: { statusCode: 409 } };
      objects.set(path, new Blob([bytes], { type: options.contentType }));
      return { data: { path }, error: null };
    },
    async download(path) {
      return objects.has(path) ? { data: objects.get(path), error: null } : { data: null, error: { statusCode: 404 } };
    },
    async remove(paths) { paths.forEach((p) => objects.delete(p)); return { data: [], error: null }; },
  };
}
async function fixture(operation = "upload") {
  const bytes = new TextEncoder().encode("Synthetic private document");
  const calls = [];
  const s = storage();
  const doc = { ...scope, operation, object_path: path, mime: "text/plain", byte_size: bytes.length,
    checksum: await sha256(bytes), status: operation === "upload" ? "reserved" : "active" };
  const completion = { command_id: id(7), idempotency_key: id(8), issued_at: "2026-09-28T00:00:00Z", expected_version: 1 };
  const metadata = { ...scope, operation, ...(operation === "upload" ? { completion } : {}) };
  const deps = {
    userId: id(6), storage: s,
    async userRpc(name, args) {
      calls.push({ name, args });
      return name === "projects_expense_evidence_ticket" ? { ticket_id: id(9) } : { command_id: args.p_command_id, entity: { id: id(5), version: 2 } };
    },
    async adminRpc(name, args) { calls.push({ name, args }); return name === "projects_expense_evidence_service_document" ? doc : { verified: true }; },
  };
  function request(changes = {}, content = bytes) {
    return new Request("https://synthetic.test/private-documents", { method: "POST",
      headers: { "content-type": "text/plain",
        "x-jentra-expense-request": Buffer.from(JSON.stringify({ ...metadata, ...changes })).toString("base64") },
      body: operation === "upload" ? content : null });
  }
  if (operation !== "upload") await s.upload(path, bytes, { upsert: false, contentType: "text/plain" });
  return { deps, request, calls, doc, bytes, metadata };
}
test("upload verifies stored bytes then completes the exact sealed command", async () => {
  const f = await fixture();
  const response = await handleDocument(f.request(), f.deps);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "private, no-store");
  assert.deepEqual(f.calls.map((x) => x.name), ["projects_expense_evidence_ticket", "projects_expense_evidence_service_document",
    "projects_expense_evidence_service_verify", "projects_expense_evidence_command"]);
  const args = f.calls.at(-1).args;
  assert.equal(args.p_command_id, id(7));
  assert.equal(args.p_idempotency_key, id(8));
  assert.deepEqual(args.p_payload, { action: "complete", id: id(5), project_id: id(4), expense_id: id(15) });
  assert.ok(!(await response.text()).includes(path));
});
test("duplicate upload only retries after reading and matching stored content", async () => {
  const f = await fixture();
  await f.deps.storage.upload(path, f.bytes, { upsert: false, contentType: "text/plain" });
  assert.equal((await handleDocument(f.request(), f.deps)).status, 200);
  f.deps.storage.objects.set(path, new Blob(["Different private bytes"]));
  assert.equal((await handleDocument(f.request(), f.deps)).status, 409);
});
test("malformed metadata, wrong scope and oversized streams have no activation", async () => {
  const f = await fixture();
  assert.equal((await handleDocument(f.request({ object_path: "guessed" }), f.deps)).status, 400);
  assert.equal(f.calls.length, 0);
  f.doc.project_id = id(99);
  assert.equal((await handleDocument(f.request(), f.deps)).status, 403);
  f.doc.project_id = id(4);
  assert.equal((await handleDocument(f.request({}, new Uint8Array(f.bytes.length + 1)), f.deps)).status, 413);
  assert.ok(!f.calls.some((x) => x.name === "projects_expense_evidence_command"));
});
test("download returns no URL and rechecks authorization after reading", async () => {
  const f = await fixture("download");
  const response = await handleDocument(f.request(), f.deps);
  assert.equal(response.status, 200);
  assert.deepEqual(new Uint8Array(await response.arrayBuffer()), f.bytes);
  assert.equal(f.calls.filter((x) => x.name === "projects_expense_evidence_ticket").length, 2);
  assert.equal(response.headers.get("content-disposition"), 'inline; filename="expense-evidence.txt"');
});
test("revocation during storage read discards all bytes and raw error values", async () => {
  const f = await fixture("download");
  let calls = 0;
  f.deps.userRpc = async () => { if (++calls > 1) throw { code: "42501", message: "PRIVATE_VALUE " + path }; return { ticket_id: id(9) }; };
  const response = await handleDocument(f.request(), f.deps);
  assert.equal(response.status, 403);
  assert.deepEqual(await response.json(), { code: "EXPENSE_EVIDENCE_DENIED" });
});
test("export passes its distinct operation, never infers export from download", async () => {
  const f = await fixture("export");
  const response = await handleDocument(f.request(), f.deps);
  assert.equal(response.status, 200);
  assert.equal(f.calls[0].args.p_operation, "export");
  assert.equal(response.headers.get("content-disposition"), 'attachment; filename="expense-evidence.txt"');
});
test("unknown storage failure is safe and leaves confirmation absent", async () => {
  const f = await fixture();
  f.deps.storage.upload = async () => ({ error: { statusCode: 500, message: "PRIVATE_VALUE " + path } });
  const response = await handleDocument(f.request(), f.deps);
  assert.equal(response.status, 503);
  assert.ok(!(await response.text()).includes("PRIVATE_VALUE"));
  assert.ok(!f.calls.some((x) => x.name === "projects_expense_evidence_command"));
});

test("expense privacy unit is checked independently of the project", async () => {
  const f = await fixture("download");
  f.doc.expense_id = id(90);
  const response = await handleDocument(f.request(), f.deps);
  assert.equal(response.status, 403);
  assert.deepEqual(await response.json(), { code: "EXPENSE_EVIDENCE_DENIED" });
  f.doc.expense_id = id(15);
  f.doc.object_path = [id(1), id(2), id(4), id(5)].join("/");
  assert.equal((await handleDocument(f.request(), f.deps)).status, 403);
});

test("unverified upload and revoked policy never activate evidence", async () => {
  const f = await fixture();
  f.deps.adminRpc = async (name) => {
    if (name.endsWith("service_document")) return f.doc;
    throw { code: "55000", message: "EXPENSE_RETENTION_WORKER_UNAVAILABLE" };
  };
  const response = await handleDocument(f.request(), f.deps);
  assert.equal(response.status, 409);
  assert.deepEqual(await response.json(), { code: "EXPENSE_RETENTION_WORKER_UNAVAILABLE" });
  assert.ok(!f.calls.some((x) => x.name === "projects_expense_evidence_command"));
});

test("caller cannot inject a storage path, URL, filename or raw completion payload", async () => {
  for (const changes of [{ object_path: path }, { url: "https://private.invalid" },
    { filename: "private receipt.pdf" }, { completion: { ...((await fixture()).metadata.completion), payload: {} } }]) {
    const f = await fixture();
    assert.equal((await handleDocument(f.request(changes), f.deps)).status, 400);
    assert.equal(f.calls.length, 0);
  }
});
const workerRequest = (body) => new Request("https://synthetic.test/private-purge", { method: "POST", body: JSON.stringify(body) });
test("readiness requires successful upload, readback and verified probe removal", async () => {
  const s = storage();
  const calls = [];
  const response = await handlePurge(workerRequest({ action: "probe" }), {
    artifactDigest: "a".repeat(64), storage: s, adminRpc: async (name, args) => { calls.push({ name, args }); return { ready: true }; },
  });
  assert.equal(response.status, 200);
  assert.equal(s.objects.size, 0);
  assert.deepEqual(calls.map((x) => x.name), ["projects_expense_evidence_worker_register"]);
  assert.match(calls[0].args.p_storage_probe_digest, /^[a-f0-9]{64}$/);
});
test("failed probe deletion never registers readiness", async () => {
  const s = storage(); let called = false;
  s.remove = async () => ({ error: { message: "Synthetic storage failure" } });
  const response = await handlePurge(workerRequest({ action: "probe" }), {
    artifactDigest: "a".repeat(64), storage: s, adminRpc: async () => { called = true; },
  });
  assert.equal(response.status, 503);
  assert.equal(called, false);
});
test("purge confirms only jobs whose objects were actually removed", async () => {
  const s = storage(); await s.upload(path, new Uint8Array([1]), { upsert: false, contentType: "text/plain" });
  const calls = [];
  const deps = { artifactDigest: "a".repeat(64), storage: s,
    async adminRpc(name, args) { calls.push({ name, args }); return name === "projects_expense_evidence_worker_claim" ?
      { items: [{ job_id: id(10), lease_id: id(11), object_paths: [path] }] } : { complete: true }; } };
  assert.deepEqual(await (await handlePurge(workerRequest({ action: "purge" }), deps)).json(), { claimed: 1, completed: 1, failed: 0 });
  assert.equal(calls.at(-1).name, "projects_expense_evidence_worker_complete");
  deps.storage.remove = async () => ({ error: { message: "PRIVATE_VALUE" } });
  calls.length = 0;
  const failed = await handlePurge(workerRequest({ action: "purge" }), deps);
  assert.equal(failed.status, 503);
  assert.ok(!calls.some((x) => x.name === "projects_expense_evidence_worker_complete"));
  assert.ok(!(await failed.text()).includes("PRIVATE_VALUE"));
});
test("worker rejects missing artifact and oversize jobs before side effects", async () => {
  let called = false;
  const deps = { artifactDigest: null, adminRpc: async () => { called = true; } };
  assert.equal((await handlePurge(workerRequest({ action: "probe" }), deps)).status, 503);
  deps.artifactDigest = "a".repeat(64);
  assert.equal((await handlePurge(workerRequest({ action: "purge", limit: 51 }), deps)).status, 400);
  assert.equal(called, false);
});
