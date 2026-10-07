import { withSupabase } from "npm:@supabase/server@1.8.0";
import { handlePurge } from "./handler.mjs";
export default {
  fetch: withSupabase({ auth: "secret" }, async (request, context) =>
    handlePurge(request, {
      artifactDigest: Deno.env.get("JENTRA_EXPENSE_WORKER_ARTIFACT_SHA256"),
      adminRpc: async (name: string, args: Record<string, unknown>) => {
        const { data, error } = await context.supabaseAdmin.schema("api").rpc(name, args);
        if (error) throw error; return data;
      },
      storage: context.supabaseAdmin.storage.from("jentra-project-expense-private"),
    }),
  ),
};
