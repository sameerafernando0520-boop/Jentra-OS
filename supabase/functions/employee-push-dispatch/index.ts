import { handleDispatch } from "./handler.mjs";
import { createGoogleSender } from "./google.mjs";

// Candidate only: no deployment/scheduler activation in this source change.
// Gateway JWT verification is replaced only at approved deployment by the
// separate scheduler secret below. No user JWT can authorize a dispatch tick.
Deno.serve(async (request: Request) => {
  try {
    const secret = Deno.env.get("EMPLOYEE_PUSH_DISPATCH_SECRET");
    // Build credentials only after rejecting a non-scheduler caller.
    if (!secret || secret.length < 32 || request.headers.get("authorization") !== `Bearer ${secret}`) {
      return Response.json({ code: "PUSH_WORKER_DENIED" }, { status: 401, headers: { "cache-control": "no-store" } });
    }
    const url = Deno.env.get("SUPABASE_URL");
    const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url?.startsWith("https://") || !key) throw Error("PUSH_SERVER_CONFIG_REQUIRED");
    const send = createGoogleSender({ projectId: Deno.env.get("EMPLOYEE_PUSH_FIREBASE_PROJECT_ID"),
      clientEmail: Deno.env.get("EMPLOYEE_PUSH_GOOGLE_CLIENT_EMAIL"), privateKey: Deno.env.get("EMPLOYEE_PUSH_GOOGLE_PRIVATE_KEY") });
    return await handleDispatch(request, {
      secret, send,
      rpc: async (name: string, args: Record<string, unknown>) => {
        if (!["employee_push_claim", "employee_push_target", "employee_push_finish"].includes(name)) throw Error("PUSH_RPC_INVALID");
        const response = await fetch(`${url}/rest/v1/rpc/${name}`, { method: "POST", signal: AbortSignal.timeout(10000),
          headers: { apikey: key, authorization: `Bearer ${key}`, "content-type": "application/json", "content-profile": "api" }, body: JSON.stringify(args) });
        if (!response.ok) throw Error("PUSH_RPC_UNAVAILABLE");
        return await response.json();
      },
    });
  } catch {
    return Response.json({ code: "PUSH_DISPATCH_UNAVAILABLE" }, { status: 503, headers: { "cache-control": "no-store" } });
  }
});
