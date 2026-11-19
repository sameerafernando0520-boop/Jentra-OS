import { createClient } from "npm:@supabase/supabase-js@2.76.1";
import { fault, handleSubscriptionHandover, handoverKey } from "./handler.mjs";

Deno.serve(async (request) => {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const secret = Deno.env.get("JENTRA_SUBSCRIPTION_HANDOVER_SECRET") ?? "";
  if (!url || !serviceKey || secret.length < 32 || secret.length > 256) {
    return new Response(null, { status: 503 });
  }

  const sender = Deno.env.get("JENTRA_IDENTITY_MAIL_FROM");
  const apiKey = Deno.env.get("JENTRA_IDENTITY_RESEND_API_KEY");
  const key = await handoverKey(Deno.env.get("JENTRA_SUBSCRIPTION_HANDOVER_KEY"));
  const client = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, detectSessionInUrl: false, persistSession: false },
  });

  return handleSubscriptionHandover(request, {
    secret,
    key,
    mailReady: Boolean(sender && apiKey),
    log: (code: string) => console.error(code),
    rpc: async (name: string, args: Record<string, unknown>) => {
      const { data, error } = await client.schema("api").rpc(name, args);
      if (error) throw fault("job_unavailable");
      return data;
    },
    createUser: async (email: string, password: string, metadata: Record<string, unknown>) => {
      const { data, error } = await client.auth.admin.createUser({
        email, password, email_confirm: true, app_metadata: metadata,
      });
      if (error?.code === "email_exists" || error?.code === "user_already_exists") {
        throw fault("username_unavailable", false);
      }
      if (error || !data.user) throw fault("identity_unavailable");
      return data.user.id;
    },
    setPassword: async (id: string, password: string, metadata: Record<string, unknown>) => {
      const { error } = await client.auth.admin.updateUserById(id, { password, app_metadata: metadata });
      if (error) throw fault("identity_unavailable");
    },
    sendMail: async (message: { to: string; subject: string; text: string }, idempotencyKey: string) => {
      let response: Response;
      try {
        response = await fetch("https://api.resend.com/emails", {
          method: "POST",
          redirect: "error",
          signal: AbortSignal.timeout(10000),
          headers: {
            Authorization: "Bearer " + apiKey,
            "content-type": "application/json",
            "Idempotency-Key": idempotencyKey,
          },
          body: JSON.stringify({ ...message, from: sender, to: [message.to] }),
        });
      } catch {
        throw fault("mail_unavailable");
      }
      if (!response.ok) {
        await response.body?.cancel();
        if (response.status === 429 || response.status === 409 || response.status >= 500) {
          throw fault("mail_unavailable");
        }
        throw fault("mail_rejected", false);
      }
      const data = await response.json();
      if (typeof data?.id !== "string" || !data.id || data.id.length > 200) throw fault("mail_unavailable");
      return data.id;
    },
  });
});
