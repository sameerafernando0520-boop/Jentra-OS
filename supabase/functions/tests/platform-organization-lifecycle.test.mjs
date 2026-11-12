import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { test } from "node:test";
import { handleOrganizationLifecycle } from "../platform-organization-lifecycle/handler.mjs";

const tenant = "10000000-0000-4000-8000-000000000001";
const other = "10000000-0000-4000-8000-000000000002";
const actor = "10000000-0000-4000-8000-000000000003";
const user = "10000000-0000-4000-8000-000000000004";
const files = [{ bucket: "jentra-attachments", name: tenant + "/ledger.txt", size: "3" }];
const data = '{"finance.transactions":[{"amount_minor":123456789123456789}]}';
const fileBytes = Uint8Array.of(0, 1, 2);
const hash = value => createHash("sha256").update(value).digest("hex");

function fixture(overrides = {}) {
  let receipt, saved;
  const calls = [];
  const deps = {
    authorize: async () => actor,
    archiveKey: Buffer.alloc(32, 42).toString("base64"),
    purgeEnabled: true,
    read: async (bucket, path) => ({
      bytes: bucket === "jentra-organization-archives" ? saved : fileBytes,
      contentType: "text/plain",
    }),
    write: async (_, path, bytes) => {
      calls.push(["write", path]);
      saved = bytes;
    },
    remove: async (bucket, names) => calls.push(["remove", bucket, names]),
    deleteIdentity: async id => calls.push(["deleteIdentity", id]),
    rpc: async (name, args) => {
      calls.push([name, args]);
      switch (name) {
        case "platform_organization_archive_snapshot":
          return { files, database_json: data, database_sha256: hash(data), lock_id: tenant };
        case "platform_organization_backup_commit":
          assert.equal(args.p_archive_sha256, hash(saved));
          receipt = { bytes: saved.length, archive_sha256: hash(saved), sha256: args.p_download_sha256 };
          return { backup_id: args.p_backup_id };
        case "platform_organization_backup_lookup":
          if (args.p_tenant_id !== tenant) throw Error("ORGANIZATION_ARCHIVE_NOT_FOUND");
          return receipt;
        case "platform_organization_purge_begin":
          if (args.p_confirmation_slug !== "first-org") throw Error("ORGANIZATION_CONFIRMATION_MISMATCH");
          return { files };
        case "platform_organization_purge_finish": return { deleted: true };
        case "platform_organization_purge_identity_queue": return [user];
        case "platform_organization_purge_identity_done": return null;
        default: throw Error("unexpected RPC");
      }
    },
    ...overrides,
  };
  const post = (action, rest = {}) => handleOrganizationLifecycle(new Request("https://example.invalid", {
    method: "POST", body: JSON.stringify({ action, tenant_id: tenant, ...rest }),
  }), deps);
  return { deps, post, calls, tamper: () => { saved[0] ^= 1; } };
}

test("a member cannot request a backup; no elevated calls run", async () => {
  const { post, calls } = fixture({ authorize: async () => { throw Error("permission denied"); } });
  assert.equal((await post("backup")).status, 403);
  assert.deepEqual(calls, []);
});

test("archives contain exact database numerics and attachment bytes", async () => {
  const { post } = fixture();
  const backup = await post("backup");
  assert.equal(backup.status, 200);
  const { backup_id } = await backup.json();
  const response = await post("download", { backup_id });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-type"), "application/octet-stream");
  assert.match(response.headers.get("content-disposition"), /attachment/);
  const raw = await response.text();
  assert.ok(raw.includes(data));
  const exported = JSON.parse(raw);
  assert.deepEqual(exported.files, [{ bucket: files[0].bucket, name: files[0].name,
    mime_type: "text/plain", sha256: hash(fileBytes), data_base64: "AAEC" }]);
  assert.equal((await post("download", { backup_id, tenant_id: other })).status, 409);
});

test("a tampered archive stops deletion before any Storage or identity changes", async () => {
  const { post, calls, tamper } = fixture();
  const { backup_id } = await (await post("backup")).json();
  tamper();
  const res = await post("purge", { backup_id, confirmation_slug: "first-org" });
  assert.equal(res.status, 503);
  assert.deepEqual(await res.json(), { error: "ORGANIZATION_ARCHIVE_INTEGRITY_FAILED" });
  assert.ok(calls.every(([name]) => !["platform_organization_purge_begin", "remove", "deleteIdentity"].includes(name)));
});

test("revocation during download prevents release of the archive", async () => {
  const { post, deps } = fixture();
  const { backup_id } = await (await post("backup")).json();
  let calls = 0;
  deps.authorize = async () => calls++ === 0 ? actor : null;
  const response = await post("download", { backup_id });
  assert.equal(response.status, 403);
  assert.deepEqual(await response.json(), { error: "OPERATOR_ACCESS_REQUIRED" });
});

test("purge confirms the slug, removes only manifest files and retires Auth after DB deletion", async () => {
  const { post, calls } = fixture();
  const { backup_id } = await (await post("backup")).json();
  assert.equal((await post("purge", { backup_id, confirmation_slug: "wrong-org" })).status, 409);
  assert.ok(calls.every(([name]) => name !== "remove"));
  const response = await post("purge", { backup_id, confirmation_slug: "first-org" });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { deleted: true });
  assert.deepEqual(calls.find(([name]) => name === "remove"), ["remove", files[0].bucket, [files[0].name]]);
  assert.ok(calls.findIndex(([name]) => name === "platform_organization_purge_finish") <
    calls.findIndex(([name]) => name === "deleteIdentity"));
});

test("a cross-organization manifest never reaches Storage deletion", async () => {
  const { post, deps, calls } = fixture();
  const rpc = deps.rpc;
  deps.rpc = async (name, args) => name === "platform_organization_purge_begin" ?
    { files: [{ ...files[0], name: other + "/ledger.txt" }] } : rpc(name, args);
  const { backup_id } = await (await post("backup")).json();
  assert.equal((await post("purge", { backup_id, confirmation_slug: "first-org" })).status, 409);
  assert.ok(calls.every(([name]) => name !== "remove"));
});

test("after a Storage error the request stops; the same backup can resume", async () => {
  const { post, deps, calls } = fixture();
  const remove = deps.remove;
  deps.remove = async () => { throw Error("ORGANIZATION_STORAGE_UNAVAILABLE"); };
  const { backup_id } = await (await post("backup")).json();
  assert.equal((await post("purge", { backup_id, confirmation_slug: "first-org" })).status, 503);
  assert.ok(calls.every(([name]) => name !== "platform_organization_purge_finish"));
  deps.remove = remove;
  assert.equal((await post("purge", { backup_id, confirmation_slug: "first-org" })).status, 200);
});

test('backup staging cleanup distinguishes a rejection from a lost response', async () => {
  for (const rejected of [true, false]) {
    const { post, deps, calls } = fixture();
    const rpc = deps.rpc;
    deps.rpc = async (name, args) => {
      if (name !== 'platform_organization_backup_commit') return rpc(name, args);
      if (!rejected) throw Error('connection closed');
      throw Object.assign(Error('ORGANIZATION_ARCHIVE_STALE'), { code: '55000' });
    };
    assert.equal((await post('backup')).status, rejected ? 409 : 503);
    const stagedPath = calls.find(([name]) => name === 'write')[1];
    assert.deepEqual(calls.filter(([name]) => name === 'remove'),
      rejected ? [['remove', 'jentra-organization-archives', [stagedPath]]] : []);
  }
});
