const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const mime = new Set(["text/plain", "image/png", "image/jpeg", "application/pdf"]);
const maxBytes = 10 * 1024 * 1024;
const privateHeaders = { "cache-control": "private, no-store", pragma: "no-cache", "x-content-type-options": "nosniff" };
function fail(code, status = 400) {
  const error = new Error(code); error.safeCode = code; error.status = status; throw error;
}
function fields(value, allowed) {
  if (!value || Array.isArray(value) || typeof value !== "object" ||
    Object.keys(value).some((key) => !allowed.includes(key))) fail("HR_REQUEST_INVALID");
}
export async function sha256(bytes) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((x) => x.toString(16).padStart(2, "0")).join("");
}
async function boundedBytes(request, limit) {
  if (!request.body) fail("HR_DOCUMENT_BYTES_MISMATCH");
  const reader = request.body.getReader(); let size = 0; const chunks = [];
  try {
    while (true) {
      const { done, value } = await reader.read(); if (done) break;
      size += value.byteLength;
      if (size > limit) { await reader.cancel(); fail("HR_DOCUMENT_LIMIT", 413); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size); let cursor = 0;
  for (const chunk of chunks) { bytes.set(chunk, cursor); cursor += chunk.length; }
  return bytes;
}
function requestMetadata(request) {
  const header = request.headers.get("x-jentra-hr-request");
  if (!header || header.length > 8192) fail("HR_REQUEST_INVALID");
  let metadata;
  try {
    const encoded = Uint8Array.from(atob(header), (c) => c.charCodeAt(0));
    metadata = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(encoded));
  } catch { fail("HR_REQUEST_INVALID"); }
  const employee = metadata?.operation === "employee_download";
  fields(metadata, employee
    ? ["tenant_id", "legal_entity_id", "branch_id", "document_id", "document_version", "publication_version", "operation"]
    : ["tenant_id", "legal_entity_id", "branch_id", "employee_id", "document_id", "operation", "completion"]);
  for (const field of ["tenant_id", "legal_entity_id", "branch_id", "document_id", ...(employee ? [] : ["employee_id"])]) {
    if (!uuid.test(metadata[field] ?? "")) fail("HR_REQUEST_INVALID");
  }
  if (!["upload", "download", "export", "employee_download"].includes(metadata.operation)) fail("HR_REQUEST_INVALID");
  if (employee && (!Number.isSafeInteger(metadata.document_version) || metadata.document_version < 1 ||
    !Number.isSafeInteger(metadata.publication_version) || metadata.publication_version < 1)) fail("HR_REQUEST_INVALID");
  if (metadata.operation === "upload") {
    fields(metadata.completion, ["command_id", "idempotency_key", "client_timestamp", "expected_version"]);
    for (const field of ["command_id", "idempotency_key"]) if (!uuid.test(metadata.completion[field] ?? "")) fail("HR_REQUEST_INVALID");
    if (typeof metadata.completion.client_timestamp !== "string" || !metadata.completion.client_timestamp.endsWith("Z") ||
      !Number.isFinite(Date.parse(metadata.completion.client_timestamp)) ||
      !Number.isSafeInteger(metadata.completion.expected_version) || metadata.completion.expected_version < 1) fail("HR_REQUEST_INVALID");
  } else if (metadata.completion != null) fail("HR_REQUEST_INVALID");
  return metadata;
}
function scope(m) {
  return { p_tenant_id: m.tenant_id, p_legal_entity_id: m.legal_entity_id, p_branch_id: m.branch_id,
    p_employee_id: m.employee_id, p_document_id: m.document_id, p_operation: m.operation };
}
function documentTicket(m, d) {
  return m.operation === "employee_download"
    ? d.userRpc("employee_document_access_ticket", { p_tenant_id: m.tenant_id, p_legal_entity_id: m.legal_entity_id,
      p_branch_id: m.branch_id, p_document_id: m.document_id, p_document_version: m.document_version,
      p_publication_version: m.publication_version })
    : d.userRpc("people_hr_document_ticket", scope(m));
}
async function download(storage, path) {
  const { data, error } = await storage.download(path);
  if (error || !data) fail("HR_DOCUMENT_STORAGE_UNAVAILABLE", 503);
  if (data.size > maxBytes) fail("HR_DOCUMENT_BYTES_MISMATCH", 409);
  return new Uint8Array(await data.arrayBuffer());
}
function safeError(error) {
  if (error?.safeCode) return [error.safeCode, error.status];
  if (error?.code === "42501") return ["HR_DOCUMENT_DENIED", 403];
  if (error?.code === "40001") return ["VERSION_CONFLICT", 409];
  if (error?.code === "55000" && ["HR_RETENTION_WORKER_UNAVAILABLE", "HR_CONTENT_EXPIRED",
    "HR_UPLOAD_VERIFICATION_REQUIRED"].includes(error.message)) return [error.message, 409];
  if (error?.code === "22023") return ["HR_REQUEST_INVALID", 400];
  return ["HR_DOCUMENT_UNCERTAIN", 503];
}
export async function handleDocument(request, d) {
  try {
    if (request.method !== "POST") fail("HR_METHOD_INVALID", 405);
    if (!uuid.test(d.userId ?? "")) fail("AUTHENTICATION_REQUIRED", 401);
    const m = requestMetadata(request);
    const ticket = await documentTicket(m, d);
    const doc = { ...await d.adminRpc("people_hr_service_document", { p_ticket_id: ticket.ticket_id, p_user_id: d.userId }) };
    for (const [field, value] of Object.entries({
      tenant_id: m.tenant_id, legal_entity_id: m.legal_entity_id, branch_id: m.branch_id,
      ...(m.operation === "employee_download" ? { document_version: m.document_version, publication_version: m.publication_version } : { employee_id: m.employee_id }),
      document_id: m.document_id, operation: m.operation === "employee_download" ? "download" : m.operation,
    })) if (doc[field] !== value) fail("HR_DOCUMENT_DENIED", 403);
    if (!uuid.test(doc.employee_id ?? "")) fail("HR_DOCUMENT_DENIED", 403);
    if (m.operation === "employee_download" && (!Number.isSafeInteger(doc.publication_version) || doc.publication_version < 1)) {
      fail("HR_DOCUMENT_DENIED", 403);
    }
    const expectedPath = [m.tenant_id, m.legal_entity_id, doc.employee_id, m.document_id].join("/");
    if (doc.object_path !== expectedPath || !mime.has(doc.mime) || !Number.isSafeInteger(doc.byte_size) ||
      doc.byte_size < 1 || doc.byte_size > maxBytes || !/^[a-f0-9]{64}$/.test(doc.checksum)) fail("HR_DOCUMENT_DENIED", 403);
    if (m.operation === "upload") {
      if (request.headers.get("content-type")?.split(";")[0] !== doc.mime) fail("HR_DOCUMENT_BYTES_MISMATCH", 409);
      const bytes = await boundedBytes(request, doc.byte_size);
      if (bytes.length !== doc.byte_size || await sha256(bytes) !== doc.checksum) fail("HR_DOCUMENT_BYTES_MISMATCH", 409);
      if (doc.status === "reserved") {
        const { error } = await d.storage.upload(doc.object_path, bytes, { upsert: false, contentType: doc.mime, cacheControl: "0" });
        // Only an explicit duplicate-object response permits verified retry.
        if (error && !["409", "Duplicate", "ResourceAlreadyExists"].includes(String(error.statusCode ?? error.error))) {
          fail("HR_DOCUMENT_STORAGE_UNAVAILABLE", 503);
        }
      }
      const stored = await download(d.storage, doc.object_path);
      if (stored.length !== doc.byte_size || await sha256(stored) !== doc.checksum) fail("HR_DOCUMENT_BYTES_MISMATCH", 409);
      await d.adminRpc("people_hr_service_verify_upload", {
        p_ticket_id: ticket.ticket_id, p_user_id: d.userId, p_checksum: doc.checksum, p_byte_size: doc.byte_size,
      });
      const completed = await d.userRpc("people_hr_command", {
        p_tenant_id: m.tenant_id, p_legal_entity_id: m.legal_entity_id, p_branch_id: m.branch_id,
        p_command_id: m.completion.command_id, p_idempotency_key: m.completion.idempotency_key,
        p_client_timestamp: m.completion.client_timestamp, p_expected_version: m.completion.expected_version,
        p_payload: { action: "document_complete", id: m.document_id, employee_id: m.employee_id },
      });
      return Response.json(completed, { headers: privateHeaders });
    }
    const bytes = await download(d.storage, doc.object_path);
    if (bytes.length !== doc.byte_size || await sha256(bytes) !== doc.checksum) fail("HR_DOCUMENT_BYTES_MISMATCH", 409);
    // Recheck both current user and service authority after the storage read.
    // Consume this second ticket as well, then compare its exact descriptor so
    // publication withdrawal/republication or document replacement discards
    // previously read bytes instead of leaving an unused authorization ticket.
    const freshTicket = await documentTicket(m, d);
    const fresh = await d.adminRpc("people_hr_service_document", { p_ticket_id: freshTicket.ticket_id, p_user_id: d.userId });
    for (const field of ["tenant_id", "legal_entity_id", "branch_id", "employee_id", "document_id", "operation", "object_path", "mime", "byte_size", "checksum",
      ...(m.operation === "employee_download" ? ["document_version", "publication_version"] : [])]) {
      if (fresh[field] !== doc[field]) fail("HR_DOCUMENT_DENIED", 403);
    }
    const extension = ({ "text/plain": "txt", "image/png": "png", "image/jpeg": "jpg", "application/pdf": "pdf" })[doc.mime];
    return new Response(bytes, { headers: {
      ...privateHeaders, "content-type": "application/octet-stream", "x-jentra-hr-mime": doc.mime,
      "content-length": String(bytes.length),
      "content-disposition": (["export", "employee_download"].includes(m.operation) ? "attachment" : "inline") + '; filename="hr-document.' + extension + '"',
    } });
  } catch (error) {
    const [code, status] = safeError(error);
    // No raw error, storage path or caller value is reflected.
    return Response.json({ code }, { status, headers: privateHeaders });
  }
}
