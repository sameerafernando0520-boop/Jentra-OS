import { withSupabase } from "npm:@supabase/server@1.8.0";
import { handleOrganizationLifecycle } from "./handler.mjs";

function unavailable() {
  return Object.assign(new Error("ORGANIZATION_STORAGE_UNAVAILABLE"), { status: 503 });
}

async function readBounded(url: string, limit: number) {
  const response = await fetch(url, { redirect: "error", signal: AbortSignal.timeout(15000) });
  if (!response.ok || !response.body) throw unavailable();
  const tooLarge = () => Object.assign(new Error("ORGANIZATION_ARCHIVE_TOO_LARGE"), { status: 413 });
  if (Number(response.headers.get("content-length") ?? 0) > limit) {
    await response.body.cancel();
    throw tooLarge();
  }
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    for (;;) {
      const chunk = await reader.read();
      if (chunk.done) break;
      size += chunk.value.length;
      if (size > limit) throw tooLarge();
      chunks.push(chunk.value);
    }
  } finally {
    await reader.cancel().catch(() => {});
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return { bytes, contentType: response.headers.get("content-type") ?? "application/octet-stream" };
}

const authenticated = withSupabase({ auth: "user" }, async (request, context) =>
  handleOrganizationLifecycle(request, {
    archiveKey: Deno.env.get("JENTRA_ORGANIZATION_ARCHIVE_KEY"),
    purgeEnabled: Deno.env.get("JENTRA_ORGANIZATION_PURGE_ENABLED") === "true",
    authorize: async () => {
      const { data, error } = await context.supabase.schema("api").rpc("platform_organization_lifecycle_authorize");
      if (error) throw error;
      return data;
    },
    rpc: async (name: string, args: Record<string, unknown>) => {
      const { data, error } = await context.supabaseAdmin.schema("api").rpc(name, args);
      if (error) throw error;
      return data;
    },
    read: async (bucket: string, path: string, limit: number) => {
      const { data, error } = await context.supabaseAdmin.storage.from(bucket).createSignedUrl(path, 30);
      if (error || !data) throw unavailable();
      return readBounded(data.signedUrl, limit);
    },
    write: async (bucket: string, path: string, bytes: Uint8Array) => {
      const { error } = await context.supabaseAdmin.storage.from(bucket).upload(path, new Blob([new Uint8Array(bytes)]), {
        contentType: "application/octet-stream", cacheControl: "0", upsert: false,
      });
      if (error) throw unavailable();
    },
    remove: async (bucket: string, names: string[]) => {
      const { error } = await context.supabaseAdmin.storage.from(bucket).remove(names);
      if (error) throw unavailable();
    },
    deleteIdentity: async (userId: string) => {
      const { error } = await context.supabaseAdmin.auth.admin.deleteUser(userId);
      if (error && error.status !== 404) {
        throw Object.assign(new Error("ORGANIZATION_IDENTITY_CLEANUP_PENDING"), { status: 503 });
      }
    },
  }),
);

export default {
  fetch: (request: Request) => request.method === "OPTIONS"
    ? handleOrganizationLifecycle(request, {})
    : authenticated(request),
};
