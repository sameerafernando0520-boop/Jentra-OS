import { withSupabase } from "npm:@supabase/server@1.8.0";
import { crypto as streamingCrypto } from "@std/crypto";
import { boundedChunks, bucket, handleVerify } from "./handler.mjs";

// Streams the object through SHA-256 instead of buffering up to 100 MiB.
async function hashStream(stream: ReadableStream<Uint8Array>, limit: number) {
  let size = 0;
  async function* counted() {
    for await (const chunk of boundedChunks(stream, limit)) { size += chunk.byteLength; yield chunk; }
  }
  const digest = await streamingCrypto.subtle.digest("SHA-256", counted());
  const sha256 = [...new Uint8Array(digest)].map((x) => x.toString(16).padStart(2, "0")).join("");
  return { sha256, size };
}

export default {
  fetch: withSupabase({ auth: "user" }, async (request, context) =>
    handleVerify(request, {
      userId: context.userClaims?.id,
      userRpc: async (name: string, args: Record<string, unknown>) => {
        const { data, error } = await context.supabase.schema("api").rpc(name, args);
        if (error) throw error; return data;
      },
      adminRpc: async (name: string, args: Record<string, unknown>) => {
        const { data, error } = await context.supabaseAdmin.schema("api").rpc(name, args);
        if (error) throw error; return data;
      },
      storage: context.supabaseAdmin.storage.from(bucket),
      hashStream,
    }),
  ),
};
