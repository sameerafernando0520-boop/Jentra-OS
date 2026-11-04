import test from "node:test";
import assert from "node:assert/strict";

import { createHash } from "node:crypto";
import { boundedChunks, handleVerify } from "../assurance-evidence-verify/handler.mjs";

const id = (n) => "00000000-0000-4000-8000-" + String(n).padStart(12, "0");
const scope = { tenant_id: id(1), legal_entity_id: id(2), branch_id: id(3), engagement_id: id(4), evidence_id: id(5) };
const path = ["assurance", id(1), id(4), id(5)].join("/");
const hex = (bytes) => createHash("sha256").update(bytes).digest("hex");
async function hashStream(stream, limit) {
  const hash = createHash("sha256"); let size = 0;
  for await (const chunk of boundedChunks(stream, limit)) { size += chunk.byteLength; hash.update(chunk); }
  return { sha256: hash.digest("hex"), size };
}

function fixture({ stored = "Signed bank confirmation", claimed = stored, recorded = null } = {}) {
  const calls = [];
  const objects = new Map([[path, new Blob([stored])]]);
  const claimedBytes = new TextEncoder().encode(claimed);
  const deps = {
    userId: id(6), hashStream,
    storage: { async download(p) { calls.push({ name: "download", p });
      return objects.has(p) ? { data: objects.get(p), error: null } : { data: null, error: { statusCode: 404 } }; } },
    async userRpc(name, args) {
      calls.push({ name, args });
      return recorded ? { evidence_id: id(5), ticket_id: null, verification: recorded }
        : { evidence_id: id(5), ticket_id: id(9), expires_at: "2026-10-19T00:05:00Z", verification: null };
    },
    async adminRpc(name, args) {
      calls.push({ name, args });
      if (name === "assurance_evidence_service_target") {
        return { evidence_id: id(5), bucket: "jentra-assurance-evidence", object_path: path,
          sha256: hex(claimedBytes), byte_size: claimedBytes.length, verified: false };
      }
      return { evidence_id: id(5), outcome: args.p_observed_sha256 === hex(claimedBytes) ? "verified" : "mismatch",
        observed_sha256: args.p_observed_sha256, observed_byte_size: args.p_observed_byte_size,
        verified_at: "2026-10-19T00:00:01Z", verifier: "assurance-evidence-verify/v1", internal: "not forwarded" };
    },
  };
  const request = (body = scope, type = "application/json") => new Request("https://synthetic.test/verify",
    { method: "POST", headers: { "content-type": type }, body: JSON.stringify(body) });
  return { deps, calls, objects, request };
}

test("hashes the stored object and records what it actually contains", async () => {
  const f = fixture();
  const response = await handleVerify(f.request(), f.deps);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "private, no-store");
  const body = await response.json();
  assert.equal(body.outcome, "verified");
  assert.equal(body.internal, undefined);
  assert.deepEqual(f.calls.map((c) => c.name), ["assurance_evidence_verification_ticket",
    "assurance_evidence_service_target", "download", "assurance_evidence_service_verify"]);
  const recorded = f.calls.at(-1).args;
  assert.equal(recorded.p_ticket_id, id(9));
  assert.equal(recorded.p_user_id, id(6));
  assert.equal(recorded.p_observed_byte_size, 24);
  assert.equal(recorded.p_observed_sha256, hex(new TextEncoder().encode("Signed bank confirmation")));
});

test("different stored bytes are reported to the database, which records a mismatch", async () => {
  const f = fixture({ stored: "Tampered bank letter!!!!", claimed: "Signed bank confirmation" });
  const response = await handleVerify(f.request(), f.deps);
  assert.equal(response.status, 200);
  assert.equal((await response.json()).outcome, "mismatch");
  assert.equal(f.calls.at(-1).args.p_observed_sha256, hex(new TextEncoder().encode("Tampered bank letter!!!!")));
});

test("a recorded outcome is returned without reading storage again", async () => {
  const recorded = { evidence_id: id(5), outcome: "verified", observed_sha256: "a".repeat(64), observed_byte_size: 3,
    verified_at: "2026-10-19T00:00:01Z", verifier: "assurance-evidence-verify/v1" };
  const f = fixture({ recorded });
  const response = await handleVerify(f.request(), f.deps);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), recorded);
  assert.deepEqual(f.calls.map((c) => c.name), ["assurance_evidence_verification_ticket"]);
});

test("malformed requests never reach the database", async () => {
  const f = fixture();
  for (const request of [
    f.request({ ...scope, object_path: "guessed" }),
    f.request({ ...scope, evidence_id: "not-a-uuid" }),
    f.request(scope, "text/plain"),
    new Request("https://synthetic.test/verify", { method: "GET" }),
  ]) {
    assert.ok([400, 405].includes((await handleVerify(request, f.deps)).status));
  }
  assert.equal(f.calls.length, 0);
  assert.equal((await handleVerify(f.request(), { ...f.deps, userId: undefined })).status, 401);
});

test("a target outside the generated path is refused before any read", async () => {
  const f = fixture();
  const admin = f.deps.adminRpc;
  f.deps.adminRpc = async (name, args) => ({ ...(await admin(name, args)), object_path: "assurance/elsewhere" });
  const response = await handleVerify(f.request(), f.deps);
  assert.equal(response.status, 403);
  assert.ok(!f.calls.some((c) => c.name === "download"));
});

test("missing objects and denials map to safe codes without raw values", async () => {
  const f = fixture();
  f.objects.clear();
  let response = await handleVerify(f.request(), f.deps);
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { code: "ASSURANCE_EVIDENCE_STORAGE_UNAVAILABLE" });
  f.deps.adminRpc = async () => { throw { code: "55000", message: "ASSURANCE_EVIDENCE_OBJECT_MISSING" }; };
  response = await handleVerify(f.request(), f.deps);
  assert.equal(response.status, 409);
  f.deps.userRpc = async () => { throw { code: "42501", message: "PRIVATE_VALUE " + path }; };
  response = await handleVerify(f.request(), f.deps);
  assert.equal(response.status, 403);
  const text = await response.text();
  assert.ok(!text.includes(path) && !text.includes("PRIVATE_VALUE"));
});

test("the bounded reader refuses objects past the evidence limit", async () => {
  const stream = new Blob([new Uint8Array(8)]).stream();
  await assert.rejects(hashStream(stream, 4), /ASSURANCE_EVIDENCE_LIMIT/);
});

test("request metadata is bounded in bytes and oversized chunked streams are cancelled", async () => {
  const encoder = new TextEncoder();
  const multibyte = encoder.encode(JSON.stringify({ ...scope, extra: "é".repeat(400) }));
  assert.ok(multibyte.byteLength > 1024 && new TextDecoder().decode(multibyte).length < 1024);
  for (const chunks of [
    [new Uint8Array(1025), new Uint8Array(4096)],
    [new Uint8Array(512), new Uint8Array(512), new Uint8Array(1), new Uint8Array(4096)],
    [multibyte, new Uint8Array(4096)],
  ]) {
    const f = fixture(); let cancelled = false;
    const stream = new ReadableStream({
      pull(controller) { const chunk = chunks.shift(); if (chunk) controller.enqueue(chunk); else controller.close(); },
      cancel() { cancelled = true; },
    }, { highWaterMark: 0 });
    const request = new Request("https://synthetic.test/verify", { method: "POST",
      headers: { "content-type": "application/json", "content-length": "1" }, body: stream, duplex: "half" });
    const response = await handleVerify(request, f.deps);
    assert.equal(response.status, 400);
    assert.deepEqual(await response.json(), { code: "ASSURANCE_REQUEST_INVALID" });
    assert.equal(cancelled, true);
    assert.equal(f.calls.length, 0);
  }
});

test("invalid UTF-8 cannot be hidden by a later duplicate JSON field", async () => {
  const f = fixture(), encoder = new TextEncoder();
  const prefix = encoder.encode('{"tenant_id":"'), suffix = encoder.encode('",' + JSON.stringify(scope).slice(1));
  const bytes = new Uint8Array(prefix.length + 1 + suffix.length);
  bytes.set(prefix); bytes[prefix.length] = 0xff; bytes.set(suffix, prefix.length + 1);
  const response = await handleVerify(new Request("https://synthetic.test/verify", { method: "POST",
    headers: { "content-type": "application/json" }, body: bytes }), f.deps);
  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), { code: "ASSURANCE_REQUEST_INVALID" });
  assert.equal(f.calls.length, 0);
});

test("aborted unfinished metadata cancels promptly even if source cancellation never settles", { timeout: 1000 }, async () => {
  const f = fixture(), abort = new AbortController(); let cancelled = false;
  const stream = new ReadableStream({
    pull() { return new Promise(() => {}); },
    cancel() { cancelled = true; return new Promise(() => {}); },
  }, { highWaterMark: 0 });
  const request = new Request("https://synthetic.test/verify", { method: "POST",
    headers: { "content-type": "application/json" }, body: stream, duplex: "half", signal: abort.signal });
  const pending = handleVerify(request, f.deps);
  queueMicrotask(() => abort.abort(Error("PRIVATE_ABORT_DETAIL")));
  const response = await pending;
  assert.equal(response.status, 400);
  assert.equal(cancelled, true);
  assert.deepEqual(await response.json(), { code: "ASSURANCE_REQUEST_INVALID" });
  assert.equal(f.calls.length, 0);
});

test("declared oversized metadata is refused without reading and valid chunked metadata keeps the RPC contract", async () => {
  const f = fixture(); let pulls = 0, cancelled = false;
  const oversized = new ReadableStream({
    pull(controller) { pulls++; controller.close(); }, cancel() { cancelled = true; },
  }, { highWaterMark: 0 });
  const response = await handleVerify(new Request("https://synthetic.test/verify", { method: "POST",
    headers: { "content-type": "application/json", "content-length": "1025" }, body: oversized, duplex: "half" }), f.deps);
  assert.equal(response.status, 400);
  assert.equal(pulls, 0); assert.equal(cancelled, true); assert.equal(f.calls.length, 0);
  const encoded = new TextEncoder().encode(JSON.stringify(scope)), chunks = [encoded.slice(0, 50), encoded.slice(50)];
  const valid = new ReadableStream({
    pull(controller) { const chunk = chunks.shift(); if (chunk) controller.enqueue(chunk); else controller.close(); },
  }, { highWaterMark: 0 });
  assert.equal((await handleVerify(new Request("https://synthetic.test/verify", { method: "POST",
    headers: { "content-type": "application/json" }, body: valid, duplex: "half" }), f.deps)).status, 200);
  assert.equal(f.calls[0].name, "assurance_evidence_verification_ticket");
});
