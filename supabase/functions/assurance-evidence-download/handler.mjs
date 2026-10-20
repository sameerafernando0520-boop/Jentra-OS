// Gives a reviewer a short-lived link to evidence bytes that the service has
// already hashed. The caller's own session mints a one-use ticket; the service
// key redeems it, and the database refuses unless the stored object is still
// the verified version. The device hashes the bytes again before saving.
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const digest = /^[a-f0-9]{64}$/;
export const bucket = "jentra-assurance-evidence";
export const maxBytes = 104857600;
export const signedSeconds = 60;
const privateHeaders = { "cache-control": "private, no-store", pragma: "no-cache", "x-content-type-options": "nosniff" };
const scopeFields = ["tenant_id", "legal_entity_id", "branch_id", "engagement_id", "evidence_id"];

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

function safeError(error) {
  if (error?.safeCode) return [error.safeCode, error.status];
  if (error?.code === "42501") return ["ASSURANCE_EVIDENCE_DENIED", 403];
  if (error?.code === "P0002") return ["ASSURANCE_EVIDENCE_NOT_FOUND", 404];
  if (error?.code === "55000" && error.message === "ASSURANCE_EVIDENCE_UNVERIFIED") return [error.message, 409];
  if (error?.code === "22023") return ["ASSURANCE_REQUEST_INVALID", 400];
  return ["ASSURANCE_EVIDENCE_UNCERTAIN", 503];
}

/**
 * d.userRpc / d.adminRpc call `api` functions with the caller's and the
 * service's credentials; d.storage is the service client's bucket handle.
 */
export async function handleDownload(request, d) {
  try {
    if (request.method !== "POST") fail("ASSURANCE_METHOD_INVALID", 405);
    if (!uuid.test(d.userId ?? "")) fail("AUTHENTICATION_REQUIRED", 401);
    const m = await requestScope(request);
    const ticket = await d.userRpc("assurance_evidence_download_ticket", {
      p_tenant_id: m.tenant_id, p_legal_entity_id: m.legal_entity_id, p_branch_id: m.branch_id,
      p_engagement_id: m.engagement_id, p_evidence_id: m.evidence_id,
    });
    if (ticket?.evidence_id !== m.evidence_id || !uuid.test(ticket.ticket_id ?? "")) {
      fail("ASSURANCE_EVIDENCE_UNCERTAIN", 503);
    }
    const target = await d.adminRpc("assurance_evidence_service_download", {
      p_ticket_id: ticket.ticket_id, p_user_id: d.userId,
    });
    const path = ["assurance", m.tenant_id, m.engagement_id, m.evidence_id].join("/");
    if (target?.evidence_id !== m.evidence_id || target.bucket !== bucket || target.object_path !== path ||
      !digest.test(target.sha256 ?? "") || !Number.isSafeInteger(target.byte_size) ||
      target.byte_size < 1 || target.byte_size > maxBytes) fail("ASSURANCE_EVIDENCE_DENIED", 403);
    const { data, error } = await d.storage.createSignedUrl(path, signedSeconds);
    const url = data?.signedUrl;
    if (error || typeof url !== "string" || !url.startsWith("https://")) {
      fail("ASSURANCE_EVIDENCE_STORAGE_UNAVAILABLE", 503);
    }
    return Response.json({ evidence_id: m.evidence_id, url, expires_in: signedSeconds,
      sha256: target.sha256, byte_size: target.byte_size }, { headers: privateHeaders });
  } catch (error) {
    const [code, status] = safeError(error);
    // No raw error, storage path or caller value is reflected.
    return Response.json({ code }, { status, headers: privateHeaders });
  }
}
