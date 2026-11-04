import { createClient } from "npm:@supabase/supabase-js@2.76.1";
import { handleWorkspaceStaff } from "./handler.mjs";

// Candidate only. Every creation RPC runs with the caller's JWT. The service
// credential is used exclusively for Auth Admin creation and private resolution.
Deno.serve(async (request: Request) => {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const publicKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url?.startsWith("https://") || !serviceKey || !publicKey) {
    return new Response(JSON.stringify({ code: "STAFF_SERVICE_UNAVAILABLE" }), {
      status: 503, headers: { "content-type": "application/json", "cache-control": "no-store" },
    });
  }
  const auth = { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false };
  const admin = createClient(url, serviceKey, { auth });
  const caller = createClient(url, publicKey, {
    auth, global: { headers: { Authorization: request.headers.get("authorization") ?? "" } },
  });
  const passwordAuth = createClient(url, publicKey, { auth });
  const rpc = async (name: string, args: Record<string, unknown>) => {
    const { data, error } = await caller.schema("api").rpc(name, args);
    if (error) throw error;
    return data;
  };
  return handleWorkspaceStaff(request, {
    authenticate: async () => {
      const { data, error } = await caller.auth.getUser();
      return error ? null : data.user?.id;
    },
    reserve: (args: Record<string, unknown>) => rpc("workspace_staff_reserve", args),
    complete: (args: Record<string, unknown>) => rpc("workspace_staff_complete", args),
    createUser: async (attributes: Parameters<typeof admin.auth.admin.createUser>[0]) => {
      const { data, error } = await admin.auth.admin.createUser(attributes);
      if (error) throw error;
      return data.user;
    },
    loginTarget: async (username: string) => {
      const { data, error } = await admin.schema("api").rpc("workspace_staff_login_target", { p_username: username });
      if (error) throw error;
      return data;
    },
    signIn: async (email: string, password: string) => {
      const { data, error } = await passwordAuth.auth.signInWithPassword({ email, password });
      if (error) throw error;
      return data.session;
    },
  });
});
