const bucket = "jentra-organization-archives";
const fileBuckets = new Set(["jentra-attachments", "jentra-hr-private", "jentra-project-expense-private"]);
const uuid = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const checksum = /^[a-f0-9]{64}$/;
const maxArchive = 40 * 1024 * 1024;
const maxFileBytes = 20 * 1024 * 1024;
const encoder = new TextEncoder();
const cors = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, apikey, content-type, x-client-info",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-expose-headers": "content-disposition",
  "cache-control": "no-store",
};

function fail(code, status = 409) {
  throw Object.assign(new Error(code), { safeCode: code, status });
}

function json(value, status = 200) {
  return Response.json(value, { status, headers: cors });
}

function base64(bytes) {
  // Browser and Edge runtimes support btoa. Chunk on a multiple of three.
  const chunks = [];
  for (let i = 0; i < bytes.length; i += 24576) {
    chunks.push(btoa(String.fromCharCode(...bytes.subarray(i, i + 24576))));
  }
  return chunks.join("");
}

async function sha256(bytes) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2, "0")).join("");
}

function validateFiles(files, tenant) {
  if (!Array.isArray(files) || files.length > 500 || files.some(file =>
    !fileBuckets.has(file?.bucket) || typeof file.name !== "string" ||
    file.name.split("/", 1)[0]?.toLowerCase() !== tenant || file.name.split("/").some(
      part => !part || part === "." || part === ".."
    ))) {
    fail("ORGANIZATION_STORAGE_MANIFEST_INVALID");
  }
}

async function loadKey(value) {
  let raw;
  try { raw = Uint8Array.from(atob(value ?? ""), c => c.charCodeAt(0)); } catch { /* invalid key */ }
  if (raw?.byteLength !== 32) fail("ORGANIZATION_ARCHIVE_KEY_UNAVAILABLE", 503);
  return crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"]);
}

function additionalData(tenant, id) {
  return encoder.encode(`jentra-organization-archive-v1/${tenant}/${id}`);
}

async function seal(key, tenant, id, plain) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const body = new Uint8Array(await crypto.subtle.encrypt({
    name: "AES-GCM", iv, additionalData: additionalData(tenant, id),
  }, key, plain));
  const result = new Uint8Array(12 + body.length);
  result.set(iv);
  result.set(body, 12);
  return result;
}

async function unseal(key, tenant, id, encrypted) {
  try {
    return await crypto.subtle.decrypt({
      name: "AES-GCM", iv: encrypted.subarray(0, 12), additionalData: additionalData(tenant, id),
    }, key, encrypted.subarray(12));
  } catch {
    fail("ORGANIZATION_ARCHIVE_INTEGRITY_FAILED", 503);
  }
}

export async function handleOrganizationLifecycle(request, dependencies) {
  if (request.method === "OPTIONS") return new Response(null, { headers: cors });
  if (request.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405);
  try {
    let actor;
    try { actor = await dependencies.authorize(); } catch { fail("OPERATOR_ACCESS_REQUIRED", 403); }
    if (!uuid.test(actor ?? "")) fail("OPERATOR_ACCESS_REQUIRED", 403);
    const reauthorize = async () => {
      let current;
      try { current = await dependencies.authorize(); } catch { fail("OPERATOR_ACCESS_REQUIRED", 403); }
      if (current !== actor) fail("OPERATOR_ACCESS_REQUIRED", 403);
    };
    if (Number(request.headers.get("content-length") ?? 0) > 4096) fail("ORGANIZATION_REQUEST_INVALID", 400);
    const raw = await request.text();
    if (raw.length > 4096) fail("ORGANIZATION_REQUEST_INVALID", 400);
    let body;
    try { body = JSON.parse(raw); } catch { fail("ORGANIZATION_REQUEST_INVALID", 400); }
    const tenant = body?.tenant_id;
    const id = body?.backup_id;
    const action = body?.action;
    if (typeof tenant !== "string" || !uuid.test(tenant) ||
        !["backup", "download", "purge", "finish_cleanup"].includes(action) ||
        (action !== "backup" && (typeof id !== "string" || !uuid.test(id))) ||
        (action === "purge" && (typeof body.confirmation_slug !== "string" ||
          !/^[a-z0-9][a-z0-9-]{2,62}$/.test(body.confirmation_slug)))) {
      fail("ORGANIZATION_REQUEST_INVALID", 400);
    }
    const rpc = (name, args = {}) => dependencies.rpc(name, { p_tenant_id: tenant, ...args });
    const finishIdentityCleanup = async () => {
      const users = await rpc("platform_organization_purge_identity_queue", { p_backup_id: id });
      if (!Array.isArray(users) || users.some(user => !uuid.test(user))) {
        fail("ORGANIZATION_IDENTITY_CLEANUP_PENDING", 503);
      }
      for (const userId of users) {
        await dependencies.deleteIdentity(userId);
        await dependencies.rpc("platform_organization_purge_identity_done", {
          p_backup_id: id, p_user_id: userId,
        });
      }
      return json({ deleted: true });
    };
    if (action === "finish_cleanup") return await finishIdentityCleanup();
    const key = await loadKey(dependencies.archiveKey);

    if (action === "backup") {
      const snapshot = await rpc("platform_organization_archive_snapshot");
      validateFiles(snapshot.files, tenant);
      if (typeof snapshot.database_json !== "string" || !checksum.test(snapshot.database_sha256) ||
        await sha256(encoder.encode(snapshot.database_json)) !== snapshot.database_sha256) {
        fail("ORGANIZATION_ARCHIVE_INTEGRITY_FAILED", 503);
      }
      let remaining = maxFileBytes;
      const files = [];
      for (const file of snapshot.files) {
        const expected = file.size == null ? null : Number(file.size);
        if (expected !== null && (!Number.isSafeInteger(expected) || expected < 0 || expected > remaining)) {
          fail("ORGANIZATION_ARCHIVE_TOO_LARGE", 413);
        }
        const loaded = await dependencies.read(file.bucket, file.name, remaining);
        if (expected !== null && expected !== loaded.bytes.length) fail("ORGANIZATION_ARCHIVE_STALE");
        remaining -= loaded.bytes.length;
        if (remaining < 0) fail("ORGANIZATION_ARCHIVE_TOO_LARGE", 413);
        files.push({
          bucket: file.bucket, name: file.name, mime_type: loaded.contentType,
          sha256: await sha256(loaded.bytes), data_base64: base64(loaded.bytes),
        });
      }
      const backupId = crypto.randomUUID();
      const heading = JSON.stringify({
        format: "jentra-organization-archive-v1", tenant_id: tenant, backup_id: backupId,
        organization_status_before_lock: snapshot.previous_status,
        created_at: new Date().toISOString(), database_sha256: snapshot.database_sha256,
      });
      // Insert the canonical PostgreSQL JSON directly, preserving numerics
      // which JavaScript would otherwise round while parsing.
      const plain = encoder.encode(heading.slice(0, -1) + ',"database":' + snapshot.database_json +
        ',"files":' + JSON.stringify(files) + "}");
      if (plain.length + 28 > maxArchive) fail("ORGANIZATION_ARCHIVE_TOO_LARGE", 413);
      const encrypted = await seal(key, tenant, backupId, plain);
      const archiveHash = await sha256(encrypted);
      const path = backupId + ".bin";
      await reauthorize();
      await dependencies.write(bucket, path, encrypted);
      try {
        return json(await rpc("platform_organization_backup_commit", {
          p_backup_id: backupId, p_lock_id: snapshot.lock_id, p_actor_id: actor,
          p_database_sha256: snapshot.database_sha256, p_archive_sha256: archiveHash,
          p_download_sha256: await sha256(plain),
          p_archive_bytes: encrypted.length, p_files: snapshot.files,
        }));
      } catch (error) {
        // A lost response can leave a valid receipt. Remove the object only
        // after a definite SQL rejection of the backup transaction.
        if (['55000', '54000'].includes(error?.code) &&
            /^ORGANIZATION_[A-Z_]+$/.test(error?.message ?? '')) {
          try { await dependencies.remove(bucket, [path]); } catch { /* keep the original error */ }
        }
        throw error;
      }
    }

    const receipt = await rpc("platform_organization_backup_lookup", { p_backup_id: id });
    const { bytes: encrypted } = await dependencies.read(bucket, id + ".bin", maxArchive);
    if (encrypted.length !== receipt.bytes || await sha256(encrypted) !== receipt.archive_sha256) {
      fail("ORGANIZATION_ARCHIVE_INTEGRITY_FAILED", 503);
    }
    const plain = await unseal(key, tenant, id, encrypted);
    if (await sha256(plain) !== receipt.sha256) fail("ORGANIZATION_ARCHIVE_INTEGRITY_FAILED", 503);
    await reauthorize();
    if (action === "download") {
      return new Response(plain, {
        headers: { ...cors, "content-type": "application/octet-stream",
          "content-disposition": `attachment; filename="jentra-organization-${id}.json"` },
      });
    }
    if (receipt.deleted) return await finishIdentityCleanup();
    if (!dependencies.purgeEnabled) fail("ORGANIZATION_PURGE_DISABLED", 503);

    const proof = await rpc("platform_organization_purge_begin", {
      p_backup_id: id, p_actor_id: actor, p_confirmation_slug: body.confirmation_slug,
    });
    validateFiles(proof.files, tenant);
    for (const fileBucket of fileBuckets) {
      const names = proof.files.filter(file => file.bucket === fileBucket).map(file => file.name);
      for (let i = 0; i < names.length; i += 100) {
        await dependencies.remove(fileBucket, names.slice(i, i + 100));
      }
    }
    await rpc("platform_organization_purge_finish", { p_backup_id: id, p_actor_id: actor });
    return await finishIdentityCleanup();
  } catch (error) {
    const upstream = typeof error?.message === "string" && /^ORGANIZATION_[A-Z_]+$/.test(error.message)
      ? error.message : "ORGANIZATION_LIFECYCLE_UNAVAILABLE";
    return json({ error: error?.safeCode ?? upstream }, error?.status ?? (upstream.endsWith("UNAVAILABLE") ? 503 : 409));
  }
}
