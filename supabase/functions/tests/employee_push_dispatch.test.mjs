import test from "node:test";
import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { handleDispatch, fcmMessage, classifyFcm, genericNotification, channelId } from "../employee-push-dispatch/handler.mjs";
import { createGoogleSender } from "../employee-push-dispatch/google.mjs";

const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const secret = "synthetic-scheduler-secret-32-characters";
const fid = "synthetic-fid-for-tests-only";
function fixture() {
  const calls = [], sent = [];
  const lease = { delivery_id: id(1), lease_id: id(2) };
  const target = { ...lease, notification_id: id(3), token: fid,
    body: "PRIVATE_HR_SENTINEL", employee_id: id(4), title: "PRIVATE_TITLE_SENTINEL" };
  return { calls, sent, lease, target, request: (body = "{}", authorization = `Bearer ${secret}`) =>
    new Request("https://synthetic.test/push", { method: "POST", headers: { authorization }, body }),
    deps: { secret,
      async rpc(name, args) { calls.push({ name, args });
        if (name === "employee_push_claim") return [lease];
        if (name === "employee_push_target") return target;
        if (name === "employee_push_finish") return true;
        throw Error("unexpected RPC");
      },
      async send(payload) { sent.push(payload); return Response.json({ name: "synthetic-message" }); },
    } };
}

test("only the scheduler secret can start a dispatch; no user payload controls its scope", async () => {
  const f = fixture();
  for (const auth of ["", "Bearer user-jwt", `Bearer ${secret}x`]) {
    assert.equal((await handleDispatch(f.request("{}", auth), f.deps)).status, 401);
  }
  assert.equal((await handleDispatch(f.request('{"tenant_id":"guessed"}'), f.deps)).status, 400);
  assert.equal(f.calls.length, 0);
  assert.equal(f.sent.length, 0);
});

test("generic fid payload excludes HR content and worker responses never expose targets", async () => {
  const f = fixture();
  const response = await handleDispatch(f.request(), f.deps);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.deepEqual(f.sent, [{ message: { fid, notification: genericNotification,
    data: { kind: "employee_update", event_id: id(3) },
    android: { priority: "normal", ttl: "300s", collapse_key: "jentra_employee_update",
      notification: { channel_id: channelId, tag: id(3) } } } }]);
  const text = await response.text();
  assert.equal(text.includes(fid), false);
  assert.equal(JSON.stringify(f.sent).includes("PRIVATE_"), false);
  assert.equal("token" in f.sent[0].message, false);
  assert.deepEqual(JSON.parse(text), { claimed: 1, sent: 1, retried: 0, retired: 0, skipped: 0, uncertain: 0 });
  assert.deepEqual(f.calls.map(c => c.name), ["employee_push_claim", "employee_push_target", "employee_push_finish"]);
});

test("revocation/session expiry between claim and target suppresses external delivery", async () => {
  const f = fixture();
  const rpc = f.deps.rpc;
  f.deps.rpc = (name, args) => name === "employee_push_target" ? null : rpc(name, args);
  const result = await (await handleDispatch(f.request(), f.deps)).json();
  assert.equal(result.skipped, 1);
  assert.equal(f.sent.length, 0);
  assert.equal(f.calls.some(c => c.name === "employee_push_finish"), false);
});

test("a mismatched lease is never sent and stale acknowledgement is uncertainty", async () => {
  const f = fixture();
  f.target.lease_id = id(99);
  const response = await handleDispatch(f.request(), f.deps);
  assert.equal((await response.json()).retried, 1);
  assert.equal(f.sent.length, 0);
  assert.equal(f.calls.at(-1).args.p_outcome, "retry");
  const g = fixture();
  const rpc = g.deps.rpc;
  g.deps.rpc = (name, args) => name === "employee_push_finish" ? false : rpc(name, args);
  const result = await (await handleDispatch(g.request(), g.deps)).json();
  assert.equal(result.sent, 0);
  assert.equal(result.uncertain, 1);
});

test("only explicit FCM UNREGISTERED retires a binding", async () => {
  const invalid = Response.json({ error: { details: [{ "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError", errorCode: "UNREGISTERED" }] } }, { status: 404 });
  assert.equal(await classifyFcm(invalid), "invalid_token");
  assert.equal(await classifyFcm(Response.json({ error: { status: "INVALID_ARGUMENT" } }, { status: 400 })), "permanent");
  for (const status of [401, 403, 429, 500, 503]) assert.equal(await classifyFcm(Response.json({}, { status })), "retry");
});

test("network errors request bounded retry and acknowledgement errors do not redispatch", async () => {
  const f = fixture();
  f.deps.send = async () => { throw Error("PRIVATE_FID_AND_CREDENTIAL_SENTINEL"); };
  const response = await handleDispatch(f.request(), f.deps);
  assert.equal((await response.json()).retried, 1);
  assert.equal(f.calls.at(-1).args.p_outcome, "retry");
  const g = fixture();
  const rpc = g.deps.rpc;
  g.deps.rpc = (name, args) => {
    if (name === "employee_push_finish") throw Error("PRIVATE_DATABASE_SENTINEL");
    return rpc(name, args);
  };
  const text = await (await handleDispatch(g.request(), g.deps)).text();
  assert.equal(JSON.parse(text).uncertain, 1);
  assert.equal(text.includes("PRIVATE_"), false);
  assert.equal(g.sent.length, 1);
});

test("chunked oversized bodies and oversized/invalid batches are refused", async () => {
  const f = fixture();
  assert.equal((await handleDispatch(f.request(" ".repeat(33)), f.deps)).status, 400);
  assert.equal(f.calls.length, 0);
  f.deps.rpc = async () => Array(21).fill(f.lease);
  assert.equal((await handleDispatch(f.request(), f.deps)).status, 503);
  assert.equal(f.sent.length, 0);
  for (const token of ["short", "bad\n".repeat(20), "x".repeat(4097)]) {
    assert.throws(() => fcmMessage({ notification_id: id(3), token }), /PUSH_TARGET_INVALID/);
  }
});

test("OAuth JWT uses a synthetic key, correct scope/audience and cached access token", async () => {
  const keys = await webcrypto.subtle.generateKey({ name: "RSASSA-PKCS1-v1_5", modulusLength: 2048,
    publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" }, true, ["sign", "verify"]);
  const pkcs8 = await webcrypto.subtle.exportKey("pkcs8", keys.privateKey);
  const pem = `-----BEGIN PRIVATE KEY-----\n${Buffer.from(pkcs8).toString("base64")}\n-----END PRIVATE KEY-----`;
  let oauth = 0, messages = 0;
  const send = createGoogleSender({ projectId: "synthetic-project", clientEmail: "sender@synthetic-project.iam.gserviceaccount.com",
    privateKey: pem, crypto: webcrypto, clock: () => 1700000000000,
    fetch: async (url, options) => {
      if (url === "https://oauth2.googleapis.com/token") {
        oauth++;
        const assertion = options.body.get("assertion");
        const [header, body, signature] = assertion.split(".");
        const claims = JSON.parse(Buffer.from(body, "base64url").toString());
        assert.equal(claims.scope, "https://www.googleapis.com/auth/firebase.messaging");
        assert.equal(claims.aud, url);
        assert.equal(claims.exp - claims.iat, 3600);
        assert.equal(await webcrypto.subtle.verify("RSASSA-PKCS1-v1_5", keys.publicKey,
          Buffer.from(signature, "base64url"), new TextEncoder().encode(`${header}.${body}`)), true);
        return Response.json({ access_token: "synthetic-access-token", expires_in: 3600 });
      }
      assert.equal(url, "https://fcm.googleapis.com/v1/projects/synthetic-project/messages:send");
      messages++;
      return Response.json({ name: "synthetic-message" });
    } });
  await Promise.all([send(fcmMessage({ token: fid, notification_id: id(3) })), send(fcmMessage({ token: fid, notification_id: id(3) }))]);
  assert.equal(oauth, 1);
  assert.equal(messages, 2);
});

test("sender config rejects arbitrary endpoints/project paths without revealing values", () => {
  assert.throws(() => createGoogleSender({ projectId: "../outside", clientEmail: "private", privateKey: "private" }), /^Error: PUSH_SERVER_CONFIG_REQUIRED$/);
});
