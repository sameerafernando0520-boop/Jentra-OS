import test from "node:test";
import assert from "node:assert/strict";
import { handleDownload, signedSeconds } from "../assurance-evidence-download/handler.mjs";

const id = (n) => "00000000-0000-4000-8000-" + String(n).padStart(12, "0");
const scope = { tenant_id: id(1), legal_entity_id: id(2), branch_id: id(3), engagement_id: id(4), evidence_id: id(5) };
const path = ["assurance", id(1), id(4), id(5)].join("/");
const digest = "b".repeat(64);

function fixture() {
  const calls = [];
  const deps = {
    userId: id(6),
    storage: {
      async createSignedUrl(p, seconds) {
        calls.push({ name: "sign", p, seconds });
        return { data: { signedUrl: "https://project.supabase.co/storage/v1/object/sign/x?token=t" }, error: null };
      },
    },
    async userRpc(name, args) {
      calls.push({ name, args });
      return { evidence_id: id(5), ticket_id: id(9), expires_at: "2026-10-20T00:05:00Z" };
    },
    async adminRpc(name, args) {
      calls.push({ name, args });
      return { evidence_id: id(5), bucket: "jentra-assurance-evidence", object_path: path,
        sha256: digest, byte_size: 21, internal: "not forwarded" };
    },
  };
  const request = (body = scope, type = "application/json") => new Request("https://synthetic.test/download",
    { method: "POST", headers: { "content-type": type }, body: JSON.stringify(body) });
  return { deps, calls, request };
}

test("redeems a ticket and returns a short-lived URL with the recorded digest", async () => {
  const f = fixture();
  const response = await handleDownload(f.request(), f.deps);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "private, no-store");
  assert.deepEqual(await response.json(), {
    evidence_id: id(5), url: "https://project.supabase.co/storage/v1/object/sign/x?token=t",
    expires_in: signedSeconds, sha256: digest, byte_size: 21,
  });
  assert.equal(signedSeconds, 60);
  assert.deepEqual(f.calls.map((c) => c.name),
    ["assurance_evidence_download_ticket", "assurance_evidence_service_download", "sign"]);
  assert.deepEqual(f.calls[0].args, { p_tenant_id: id(1), p_legal_entity_id: id(2), p_branch_id: id(3),
    p_engagement_id: id(4), p_evidence_id: id(5) });
  assert.deepEqual(f.calls[1].args, { p_ticket_id: id(9), p_user_id: id(6) });
  assert.deepEqual(f.calls[2], { name: "sign", p: path, seconds: 60 });
});

test("malformed requests never reach the database", async () => {
  const f = fixture();
  for (const request of [
    f.request({ ...scope, object_path: "guessed" }),
    f.request({ ...scope, evidence_id: "not-a-uuid" }),
    f.request(scope, "text/plain"),
    new Request("https://synthetic.test/download", { method: "GET" }),
  ]) {
    assert.ok([400, 405].includes((await handleDownload(request, f.deps)).status));
  }
  assert.equal(f.calls.length, 0);
  assert.equal((await handleDownload(f.request(), { ...f.deps, userId: undefined })).status, 401);
});

test("a target outside the generated path is never signed", async () => {
  const f = fixture();
  const admin = f.deps.adminRpc;
  f.deps.adminRpc = async (name, args) => ({ ...(await admin(name, args)), object_path: "assurance/elsewhere" });
  assert.equal((await handleDownload(f.request(), f.deps)).status, 403);
  assert.ok(!f.calls.some((c) => c.name === "sign"));
});

test("a signed URL that is not https is refused", async () => {
  const f = fixture();
  f.deps.storage.createSignedUrl = async () => ({ data: { signedUrl: "http://plain.test/x" }, error: null });
  assert.equal((await handleDownload(f.request(), f.deps)).status, 503);
});

test("refusals map to safe codes without raw values", async () => {
  const f = fixture();
  f.deps.userRpc = async () => { throw { code: "55000", message: "ASSURANCE_EVIDENCE_UNVERIFIED" }; };
  let response = await handleDownload(f.request(), f.deps);
  assert.equal(response.status, 409);
  assert.deepEqual(await response.json(), { code: "ASSURANCE_EVIDENCE_UNVERIFIED" });
  f.deps.userRpc = async () => { throw { code: "P0002", message: "ASSURANCE_EVIDENCE_NOT_FOUND" }; };
  assert.equal((await handleDownload(f.request(), f.deps)).status, 404);
  f.deps.userRpc = async () => { throw { code: "42501", message: "PRIVATE_VALUE " + path }; };
  response = await handleDownload(f.request(), f.deps);
  assert.equal(response.status, 403);
  const text = await response.text();
  assert.ok(!text.includes(path) && !text.includes("PRIVATE_VALUE"));
  const g = fixture();
  g.deps.storage.createSignedUrl = async () => ({ data: null, error: { statusCode: 500 } });
  assert.equal((await handleDownload(g.request(), g.deps)).status, 503);
});
