// Verifies the bytes a request owner uploaded for a submitted assurance
// evidence item: reads the stored object with the service key, hashes every
// byte and records the observed digest and size. The database decides the
// outcome and refuses acceptance until it is `verified`.
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const digest = /^[a-f0-9]{64}$/;
export const bucket = "jentra-assurance-evidence";
export const maxBytes = 104857600;
const privateHeaders = { "cache-control": "private, no-store", pragma: "no-cache", "x-content-type-options": "nosniff" };
const scopeFields = ["tenant_id", "legal_entity_id", "branch_id", "engagement_id", "evidence_id"];
const verificationFields = ["evidence_id", "outcome", "observed_sha256", "observed_byte_size", "verified_at", "verifier"];

function fail(code, status = 400) {
  const error = new Error(code); error.safeCode = code; error.status = status; throw error;
}

async function requestScope(request) {
  if ((request.headers.get("content-type") ?? "").split(";")[0] !== "application/json") fail("ASSURANCE_REQUEST_INVALID");
  const text = await request.text();
  if (text.length > 1024) fail("ASSURANCE_REQUEST_INVALID");
  let body;
  try { body = JSON.parse(text); } catch { fail("ASSURANCE_REQUEST_INVALID"); }
  if (!body || Array.isArray(body) || typeof body !== "object" ||
    Object.keys(body).length !== scopeFields.length ||
    scopeFields.some((field) => typeof body[field] !== "string" || !uuid.test(body[field]))) {
    fail("ASSURANCE_REQUEST_INVALID");
  }
  return body;
}

// Only the fields the client contract reads, after checking their shape.
function verification(v, evidenceId) {
  if (!v || typeof v !== "object" || v.evidence_id !== evidenceId || !["verified", "mismatch"].includes(v.outcome) ||
    !digest.test(v.observed_sha256 ?? "") || !Number.isSafeInteger(v.observed_byte_size) ||
    typeof v.verified_at !== "string" || v.verifier !== "assurance-evidence-verify/v1") {
    fail("ASSURANCE_EVIDENCE_UNCERTAIN", 503);
  }
  return Object.fromEntries(verificationFields.map((field) => [field, v[field]]));
}

function safeError(error) {
  if (error?.safeCode) return [error.safeCode, error.status];
  if (error?.code === "42501") return ["ASSURANCE_EVIDENCE_DENIED", 403];
  if (error?.code === "P0002") return ["ASSURANCE_EVIDENCE_NOT_FOUND", 404];
  if (error?.code === "55000" && error.message === "ASSURANCE_EVIDENCE_OBJECT_MISSING") return [error.message, 409];
  if (error?.code === "22023") return ["ASSURANCE_REQUEST_INVALID", 400];
  return ["ASSURANCE_EVIDENCE_UNCERTAIN", 503];
}

/**
 * d.userRpc / d.adminRpc call `api` functions with the caller's and the
 * service's credentials; d.storage is the service client's bucket handle;
 * d.hashStream(stream, limit) returns { sha256, size } over every byte.
 */
export async function handleVerify(request, d) {
  try {
    if (request.method !== "POST") fail("ASSURANCE_METHOD_INVALID", 405);
    if (!uuid.test(d.userId ?? "")) fail("AUTHENTICATION_REQUIRED", 401);
    const m = await requestScope(request);
    // The human's own session proves current authority and mints a one-use ticket.
    const ticket = await d.userRpc("assurance_evidence_verification_ticket", {
      p_tenant_id: m.tenant_id, p_legal_entity_id: m.legal_entity_id, p_branch_id: m.branch_id,
      p_engagement_id: m.engagement_id, p_evidence_id: m.evidence_id,
    });
    if (ticket?.evidence_id !== m.evidence_id) fail("ASSURANCE_EVIDENCE_UNCERTAIN", 503);
    if (ticket.ticket_id == null) {
      return Response.json(verification(ticket.verification, m.evidence_id), { headers: privateHeaders });
    }
    if (!uuid.test(ticket.ticket_id)) fail("ASSURANCE_EVIDENCE_UNCERTAIN", 503);
    const target = await d.adminRpc("assurance_evidence_service_target", { p_ticket_id: ticket.ticket_id, p_user_id: d.userId });
    const path = ["assurance", m.tenant_id, m.engagement_id, m.evidence_id].join("/");
    if (target?.evidence_id !== m.evidence_id || target.bucket !== bucket || target.object_path !== path ||
      !digest.test(target.sha256 ?? "") || !Number.isSafeInteger(target.byte_size) ||
      target.byte_size < 1 || target.byte_size > maxBytes) fail("ASSURANCE_EVIDENCE_DENIED", 403);
    const { data, error } = await d.storage.download(path);
    if (error || !data) fail("ASSURANCE_EVIDENCE_STORAGE_UNAVAILABLE", 503);
    // Hash everything that is stored, whatever its claimed size: a larger or
    // smaller object is a recorded mismatch, not a silent truncation.
    const observed = await d.hashStream(data.stream(), maxBytes);
    if (!digest.test(observed?.sha256 ?? "") || !Number.isSafeInteger(observed.size)) fail("ASSURANCE_EVIDENCE_UNCERTAIN", 503);
    const recorded = await d.adminRpc("assurance_evidence_service_verify", {
      p_ticket_id: ticket.ticket_id, p_user_id: d.userId,
      p_observed_sha256: observed.sha256, p_observed_byte_size: observed.size,
    });
    return Response.json(verification(recorded, m.evidence_id), { headers: privateHeaders });
  } catch (error) {
    const [code, status] = safeError(error);
    // No raw error, storage path or caller value is reflected.
    return Response.json({ code }, { status, headers: privateHeaders });
  }
}

// Shared bounded reader: counts bytes and refuses more than `limit`.
export async function* boundedChunks(stream, limit) {
  const reader = stream.getReader(); let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read(); if (done) return;
      size += value.byteLength;
      if (size > limit) { await reader.cancel(); fail("ASSURANCE_EVIDENCE_LIMIT", 413); }
      yield value;
    }
  } finally { reader.releaseLock(); }
}
