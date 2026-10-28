const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const headers = { "cache-control": "no-store", "x-content-type-options": "nosniff" };
export const channelId = "jentra_employee_updates";
export const genericNotification = Object.freeze({ title: "Jentra Employee", body: "You have an update. Open the app to view it." });

// Deliberately excludes notification body/title/employee/tenant from the database.
// A tap merely opens the app; the app must re-authorize its current HR subject.
export function fcmMessage(target) {
  if (!uuid.test(target?.notification_id ?? "") || typeof target?.token !== "string" ||
      target.token.length < 20 || target.token.length > 4096 || /[\s\x00-\x1f\x7f]/.test(target.token)) throw Error("PUSH_TARGET_INVALID");
  return { message: {
    fid: target.token,
    notification: { ...genericNotification },
    data: { kind: "employee_update", event_id: target.notification_id },
    android: { priority: "normal", ttl: "300s", collapse_key: "jentra_employee_update",
      notification: { channel_id: channelId, tag: target.notification_id } },
  } };
}

function authorized(request, secret) {
  if (typeof secret !== "string" || secret.length < 32) return false;
  const expected = `Bearer ${secret}`;
  const received = request.headers.get("authorization") ?? "";
  let difference = expected.length ^ received.length;
  for (let i = 0; i < expected.length; i++) difference |= expected.charCodeAt(i) ^ (received.charCodeAt(i) || 0);
  return difference === 0;
}

export async function classifyFcm(response) {
  if (response.ok) return "sent";
  // Only an explicit FCM UNREGISTERED code retires an installation. Auth errors,
  // project/sender mismatches and generic INVALID_ARGUMENT never erase bindings.
  let body;
  try { body = await response.json(); } catch { /* no raw response is retained */ }
  const unregistered = body?.error?.details?.some?.(d =>
    d?.["@type"] === "type.googleapis.com/google.firebase.fcm.v1.FcmError" && d.errorCode === "UNREGISTERED");
  if (unregistered) return "invalid_token";
  if (response.status === 429 || response.status >= 500 || response.status === 401 || response.status === 403) return "retry";
  return "permanent";
}

async function boundedBody(request) {
  if (!request.body) return "";
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 32) { await reader.cancel(); throw Error("PUSH_REQUEST_INVALID"); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  return new TextDecoder().decode(Uint8Array.from(chunks.flatMap(chunk => [...chunk])));
}

/** Only a scheduler holding a separate server secret may invoke this endpoint.
 * rpc is a service-role adapter. Claim returns IDs, target rechecks the binding
 * immediately before each external request, and finish enforces lease identity.
 */
export async function handleDispatch(request, d) {
  if (request.method !== "POST") return Response.json({ code: "PUSH_METHOD_INVALID" }, { status: 405, headers });
  if (!authorized(request, d.secret)) return Response.json({ code: "PUSH_WORKER_DENIED" }, { status: 401, headers });
  if ((request.headers.get("content-length") ?? "0") !== "0" && Number(request.headers.get("content-length")) > 32) {
    return Response.json({ code: "PUSH_REQUEST_INVALID" }, { status: 400, headers });
  }
  try {
    let body;
    try { body = await boundedBody(request); }
    catch { return Response.json({ code: "PUSH_REQUEST_INVALID" }, { status: 400, headers }); }
    if (body.trim() !== "" && body.trim() !== "{}") return Response.json({ code: "PUSH_REQUEST_INVALID" }, { status: 400, headers });
    const claimed = await d.rpc("employee_push_claim", { p_limit: 20 });
    if (!Array.isArray(claimed) || claimed.length > 20) throw Error("PUSH_CLAIM_INVALID");
    const result = { claimed: claimed.length, sent: 0, retried: 0, retired: 0, skipped: 0, uncertain: 0 };
    for (const lease of claimed) {
      if (!uuid.test(lease?.delivery_id ?? "") || !uuid.test(lease?.lease_id ?? "")) throw Error("PUSH_LEASE_INVALID");
      const args = { p_delivery_id: lease.delivery_id, p_lease_id: lease.lease_id };
      let outcome;
      try {
        const target = await d.rpc("employee_push_target", args);
        if (!target) { result.skipped++; continue; }
        if (target.delivery_id !== lease.delivery_id || target.lease_id !== lease.lease_id) throw Error("PUSH_TARGET_MISMATCH");
        outcome = await classifyFcm(await d.send(fcmMessage(target)));
      } catch { outcome = "retry"; }
      // External delivery and DB acknowledgement cannot be one transaction.
      // Failed/stale finish is uncertainty; never report it as a confirmed send.
      try {
        const accepted = await d.rpc("employee_push_finish", { ...args, p_outcome: outcome });
        if (accepted !== true) { result.uncertain++; continue; }
        if (outcome === "sent") result.sent++;
        else if (outcome === "retry") result.retried++;
        else result.retired++;
      } catch { result.uncertain++; }
    }
    return Response.json(result, { headers });
  } catch {
    // No target, credential, raw RPC/Google error or private response escapes.
    return Response.json({ code: "PUSH_DISPATCH_UNAVAILABLE" }, { status: 503, headers });
  }
}
