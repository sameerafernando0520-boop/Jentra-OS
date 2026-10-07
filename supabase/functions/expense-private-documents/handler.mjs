const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const mime = new Set(["text/plain", "image/png", "image/jpeg", "application/pdf"]);
const maxBytes = 10 * 1024 * 1024;
const privateHeaders = { "cache-control": "private, no-store", pragma: "no-cache", "x-content-type-options": "nosniff" };
function fail(code, status = 400) {
  const error = new Error(code); error.safeCode = code; error.status = status; throw error;
}
function fields(value, allowed) {
  if (!value || Array.isArray(value) || typeof value !== "object" ||
    Object.keys(value).some((key) => !allowed.includes(key))) fail("EXPENSE_REQUEST_INVALID");
}
export async function sha256(bytes) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((x) => x.toString(16).padStart(2, "0")).join("");
}
async function boundedBytes(request, limit) {
  if (!request.body) fail("EXPENSE_EVIDENCE_BYTES_MISMATCH");
  const reader = request.body.getReader(); let size = 0; const chunks = [];
  try {
    while (true) {
      const { done, value } = await reader.read(); if (done) break;
      size += value.byteLength;
      if (size > limit) { await reader.cancel(); fail("EXPENSE_EVIDENCE_LIMIT", 413); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size); let cursor = 0;
  for (const chunk of chunks) { bytes.set(chunk, cursor); cursor += chunk.length; }
  return bytes;
}
function requestMetadata(request) {
  const header = request.headers.get("x-jentra-expense-request");
  if (!header || header.length > 8192) fail("EXPENSE_REQUEST_INVALID");
  let metadata;
  try {
    const encoded = Uint8Array.from(atob(header), (c) => c.charCodeAt(0));
    metadata = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(encoded));
  } catch { fail("EXPENSE_REQUEST_INVALID"); }
  fields(metadata, ["tenant_id", "legal_entity_id", "branch_id", "project_id", "expense_id", "document_id", "operation", "completion"]);
  for (const field of ["tenant_id", "legal_entity_id", "branch_id", "project_id", "expense_id", "document_id"]) {
    if (!uuid.test(metadata[field] ?? "")) fail("EXPENSE_REQUEST_INVALID");
  }
  if (!["upload", "download", "export"].includes(metadata.operation)) fail("EXPENSE_REQUEST_INVALID");
  if (metadata.operation === "upload") {
    fields(metadata.completion, ["command_id", "idempotency_key", "issued_at", "expected_version"]);
    for (const field of ["command_id", "idempotency_key"]) if (!uuid.test(metadata.completion[field] ?? "")) fail("EXPENSE_REQUEST_INVALID");
    if (typeof metadata.completion.issued_at !== "string" || !metadata.completion.issued_at.endsWith("Z") ||
      !Number.isFinite(Date.parse(metadata.completion.issued_at)) ||
      !Number.isSafeInteger(metadata.completion.expected_version) || metadata.completion.expected_version < 1) fail("EXPENSE_REQUEST_INVALID");
  } else if (metadata.completion != null) fail("EXPENSE_REQUEST_INVALID");
  return metadata;
}
function scope(m) {
  return { p_tenant_id: m.tenant_id, p_legal_entity_id: m.legal_entity_id, p_branch_id: m.branch_id,
    p_project_id: m.project_id, p_expense_id: m.expense_id, p_document_id: m.document_id, p_operation: m.operation };
}
async function download(storage, path) {
  const { data, error } = await storage.download(path);
  if (error || !data) fail("EXPENSE_EVIDENCE_STORAGE_UNAVAILABLE", 503);
  if (data.size > maxBytes) fail("EXPENSE_EVIDENCE_BYTES_MISMATCH", 409);
  return new Uint8Array(await data.arrayBuffer());
}
function safeError(error) {
  if (error?.safeCode) return [error.safeCode, error.status];
  if (error?.code === "42501") return ["EXPENSE_EVIDENCE_DENIED", 403];
  if (error?.code === "40001") return ["VERSION_CONFLICT", 409];
  if (error?.code === "55000" && ["EXPENSE_RETENTION_WORKER_UNAVAILABLE", "EXPENSE_RETENTION_POLICY_REQUIRED",
    "EXPENSE_EVIDENCE_CONTENT_UNAVAILABLE", "EXPENSE_EVIDENCE_VERIFICATION_REQUIRED"].includes(error.message)) return [error.message, 409];
  if (error?.code === "22023") return ["EXPENSE_REQUEST_INVALID", 400];
  return ["EXPENSE_EVIDENCE_UNCERTAIN", 503];
}
export async function handleDocument(request, d) {
  try {
    if (request.method !== "POST") fail("EXPENSE_METHOD_INVALID", 405);
    if (!uuid.test(d.userId ?? "")) fail("AUTHENTICATION_REQUIRED", 401);
    const m = requestMetadata(request);
    const ticket = await d.userRpc("projects_expense_evidence_ticket", scope(m));
    const doc = await d.adminRpc("projects_expense_evidence_service_document", { p_ticket_id: ticket.ticket_id, p_user_id: d.userId });
    for (const [field, value] of Object.entries({
      tenant_id: m.tenant_id, legal_entity_id: m.legal_entity_id, branch_id: m.branch_id,
      project_id: m.project_id, expense_id: m.expense_id, document_id: m.document_id, operation: m.operation,
    })) if (doc[field] !== value) fail("EXPENSE_EVIDENCE_DENIED", 403);
    const expectedPath = [m.tenant_id, m.legal_entity_id, m.project_id, m.expense_id, m.document_id].join("/");
    if (doc.object_path !== expectedPath || !mime.has(doc.mime) || !Number.isSafeInteger(doc.byte_size) ||
      doc.byte_size < 1 || doc.byte_size > maxBytes || !/^[a-f0-9]{64}$/.test(doc.checksum)) fail("EXPENSE_EVIDENCE_DENIED", 403);
    if (m.operation === "upload") {
      if (request.headers.get("content-type")?.split(";")[0] !== doc.mime) fail("EXPENSE_EVIDENCE_BYTES_MISMATCH", 409);
      const bytes = await boundedBytes(request, doc.byte_size);
      if (bytes.length !== doc.byte_size || await sha256(bytes) !== doc.checksum) fail("EXPENSE_EVIDENCE_BYTES_MISMATCH", 409);
      if (doc.status === "reserved") {
        const { error } = await d.storage.upload(doc.object_path, bytes, { upsert: false, contentType: doc.mime, cacheControl: "0" });
        // Only an explicit duplicate-object response permits verified retry.
        if (error && !["409", "Duplicate", "ResourceAlreadyExists"].includes(String(error.statusCode ?? error.error))) {
          fail("EXPENSE_EVIDENCE_STORAGE_UNAVAILABLE", 503);
        }
      }
      const stored = await download(d.storage, doc.object_path);
      if (stored.length !== doc.byte_size || await sha256(stored) !== doc.checksum) fail("EXPENSE_EVIDENCE_BYTES_MISMATCH", 409);
      await d.adminRpc("projects_expense_evidence_service_verify", {
        p_ticket_id: ticket.ticket_id, p_user_id: d.userId, p_checksum: doc.checksum, p_byte_size: doc.byte_size,
      });
      const completed = await d.userRpc("projects_expense_evidence_command", {
        p_tenant_id: m.tenant_id, p_legal_entity_id: m.legal_entity_id, p_branch_id: m.branch_id,
        p_command_id: m.completion.command_id, p_idempotency_key: m.completion.idempotency_key,
        p_issued_at: m.completion.issued_at, p_expected_version: m.completion.expected_version,
        p_payload: { action: "complete", id: m.document_id, project_id: m.project_id, expense_id: m.expense_id },
      });
      return Response.json(completed, { headers: privateHeaders });
    }
    const bytes = await download(d.storage, doc.object_path);
    if (bytes.length !== doc.byte_size || await sha256(bytes) !== doc.checksum) fail("EXPENSE_EVIDENCE_BYTES_MISMATCH", 409);
    // Recheck current user authority after the potentially slow storage read.
    await d.userRpc("projects_expense_evidence_ticket", scope(m));
    const extension = ({ "text/plain": "txt", "image/png": "png", "image/jpeg": "jpg", "application/pdf": "pdf" })[doc.mime];
    return new Response(bytes, { headers: {
      ...privateHeaders, "content-type": "application/octet-stream", "x-jentra-expense-mime": doc.mime,
      "content-length": String(bytes.length),
      "content-disposition": (m.operation === "export" ? "attachment" : "inline") + '; filename="expense-evidence.' + extension + '"',
    } });
  } catch (error) {
    const [code, status] = safeError(error);
    // No raw error, storage path or caller value is reflected.
    return Response.json({ code }, { status, headers: privateHeaders });
  }
}
