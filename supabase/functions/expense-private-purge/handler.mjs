import { sha256 } from "../expense-private-documents/handler.mjs";
const headers = { "cache-control": "no-store", "x-content-type-options": "nosniff" };
const uuid = "[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}";
const privatePath = new RegExp("^" + Array(5).fill(uuid).join("/") + "$", "i");
const identity = new RegExp("^" + uuid + "$", "i");
function missing(result) {
  return !result.data && result.error &&
    ["404", "not_found", "NoSuchKey"].includes(String(result.error.statusCode ?? result.error.error));
}
export async function handlePurge(request, d) {
  try {
    if (request.method !== "POST" || !/^[a-f0-9]{64}$/.test(d.artifactDigest ?? "")) {
      return Response.json({ code: "EXPENSE_WORKER_CONFIGURATION_REQUIRED" }, { status: 503, headers });
    }
    const length = request.headers.get("content-length");
    if (length !== null && Number(length) > 1024) return Response.json({ code: "EXPENSE_WORKER_REQUEST_INVALID" }, { status: 400, headers });
    const reader = request.body?.getReader(); const chunks = []; let size = 0;
    if (reader) {
      try {
        while (true) {
          const { done, value } = await reader.read(); if (done) break;
          size += value.length;
          if (size > 1024) { await reader.cancel();
            return Response.json({ code: "EXPENSE_WORKER_REQUEST_INVALID" }, { status: 400, headers }); }
          chunks.push(...value);
        }
      } finally { reader.releaseLock(); }
    }
    const body = JSON.parse(new TextDecoder().decode(new Uint8Array(chunks)));
    if (!body || Array.isArray(body) || Object.keys(body).some((k) => !["action", "limit"].includes(k)) ||
      !["probe", "purge"].includes(body.action) || !Number.isInteger(body.limit ?? 50) ||
      (body.limit ?? 50) < 1 || (body.limit ?? 50) > 50) {
      return Response.json({ code: "EXPENSE_WORKER_REQUEST_INVALID" }, { status: 400, headers });
    }
    if (body.action === "probe") {
      const bytes = new TextEncoder().encode("jentra-w4-expense-probe:" + crypto.randomUUID());
      const path = "_worker-probe/" + crypto.randomUUID();
      const uploaded = await d.storage.upload(path, bytes, { upsert: false, contentType: "text/plain", cacheControl: "0" });
      if (uploaded.error) throw uploaded.error;
      let probeDigest;
      try {
        const stored = await d.storage.download(path);
        if (stored.error || !stored.data || stored.data.size !== bytes.length) throw new Error("Probe failed");
        probeDigest = await sha256(new Uint8Array(await stored.data.arrayBuffer()));
        if (probeDigest !== await sha256(bytes)) throw new Error("Probe failed");
      } finally {
        const removed = await d.storage.remove([path]); if (removed.error) throw removed.error;
      }
      if (!missing(await d.storage.download(path))) throw new Error("Probe deletion unverified");
      return Response.json(await d.adminRpc("projects_expense_evidence_worker_register", {
        p_artifact_digest: d.artifactDigest, p_storage_probe_digest: probeDigest,
      }), { headers });
    }
    const claim = await d.adminRpc("projects_expense_evidence_worker_claim", { p_limit: body.limit ?? 50 });
    if (!Array.isArray(claim.items) || claim.items.length > (body.limit ?? 50)) throw new Error("Claim invalid");
    let completed = 0, failed = 0;
    for (const job of claim.items) {
      try {
        if (!identity.test(job.job_id ?? "") || !identity.test(job.lease_id ?? "") ||
          !Array.isArray(job.object_paths) || job.object_paths.length !== 1 ||
          job.object_paths.some((p) => typeof p !== "string" || !privatePath.test(p))) {
          throw new Error("Claim invalid");
        }
        if (job.object_paths.length) {
          const removed = await d.storage.remove(job.object_paths); if (removed.error) throw removed.error;
          for (const path of job.object_paths) if (!missing(await d.storage.download(path))) throw new Error("Deletion unverified");
        }
        await d.adminRpc("projects_expense_evidence_worker_complete", { p_job_id: job.job_id, p_lease_id: job.lease_id });
        completed++;
      } catch { failed++; }
    }
    return Response.json({ claimed: claim.items.length, completed, failed }, { status: failed ? 503 : 200, headers });
  } catch {
    return Response.json({ code: "EXPENSE_WORKER_UNCERTAIN" }, { status: 503, headers });
  }
}
