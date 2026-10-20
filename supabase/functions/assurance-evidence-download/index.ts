import { withSupabase } from "npm:@supabase/server@1.8.0";
import { bucket, handleDownload } from "./handler.mjs";

export default {
  fetch: withSupabase({ auth: "user" }, async (request, context) =>
    handleDownload(request, {
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
    }),
  ),
};
