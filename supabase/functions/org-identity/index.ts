import { createClient } from "npm:@supabase/supabase-js@2.76.1";
import { handleOrganizationIdentity } from "./handler.mjs";

function fault(code: string) {
  return Object.assign(new Error(code), { code });
}

Deno.serve((request) => {
  const url = Deno.env.get("SUPABASE_URL");
  const publicKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !publicKey || !serviceKey) {
    return new Response(JSON.stringify({ error: "identity_unavailable" }), {
      status: 503,
      headers: { "content-type": "application/json", "cache-control": "no-store" },
    });
  }
  const apiKey = Deno.env.get("JENTRA_IDENTITY_RESEND_API_KEY");
  const sender = Deno.env.get("JENTRA_IDENTITY_MAIL_FROM");
  const secret = Deno.env.get("JENTRA_IDENTITY_CODE_SECRET");
  const auth = { autoRefreshToken: false, detectSessionInUrl: false, persistSession: false };
  const token = /^Bearer (\S+)$/i.exec(request.headers.get("authorization") ?? "")?.[1];
  const admin = createClient(url, serviceKey, { auth });
  const caller = createClient(url, publicKey, {
    auth, global: { headers: token ? { Authorization: `Bearer ${token}` } : {} },
  });

  async function rpc(client: typeof admin, name: string, args: Record<string, unknown> = {}) {
    const { data, error } = await client.schema("api").rpc(name, args);
    if (error?.code === "42501") throw fault("forbidden");
    if (error?.code === "22023" || error?.code === "22P02") throw fault("invalid_input");
    if (error?.code === "23505") throw fault("username_unavailable");
    if (error) throw fault("identity_unavailable");
    return data;
  }

  async function updatePassword(id: string, password: string, metadata?: Record<string, unknown>) {
    const { error } = await admin.auth.admin.updateUserById(id, {
      password, ...(metadata ? { app_metadata: metadata } : {}),
    });
    if (error?.code === "weak_password") throw fault("weak_password");
    if (error) throw fault("identity_unavailable");
  }

  const runtime = globalThis as typeof globalThis & {
    EdgeRuntime?: { waitUntil: (job: Promise<unknown>) => void };
  };
  return handleOrganizationIdentity(request, {
    log: (code: string) => console.error(code),
    codeSecret: secret && new TextEncoder().encode(secret).length >= 32 ? secret : null,
    ownerVerifyUrl: Deno.env.get("JENTRA_SYSTEM_OWNER_VERIFY_URL"),
    staffVerifyUrl: Deno.env.get("JENTRA_STAFF_VERIFY_URL"),
    mailReady: Boolean(apiKey && sender),
    background: (job: Promise<unknown>) => runtime.EdgeRuntime?.waitUntil(job),
    authenticate: async () => {
      if (!token) return null;
      const { data, error } = await caller.auth.getUser(token);
      return error ? null : data.user;
    },
    profile: () => rpc(caller, "organization_identity_profile"),
    operatorProfile: () => rpc(caller, "platform_operator_identity_profile"),
    operatorAssigned: async () => (await rpc(caller, "platform_organization_assignment")) === true,
    isOperator: async () => (await rpc(caller, "platform_organization_access")) === true,
    staffCanProvision: async (tenantId: string) =>
      (await rpc(caller, "organization_staff_can_provision", { p_tenant_id: tenantId })) === true,
    adminRpc: (name: string, args: Record<string, unknown>) => rpc(admin, name, args),
    callerRpc: (name: string, args: Record<string, unknown>) => rpc(caller, name, args),
    consumeReset: (args: Record<string, unknown>) => rpc(admin, "managed_staff_consume_password_reset", args),
    authorizeChange: (args: Record<string, unknown>) => rpc(admin, "subscription_authorize_password_change", args),
    createUser: async (email: string, password: string, tenantId: string, department?: string, name?: string) => {
      const { data, error } = await admin.auth.admin.createUser({
        email, password, email_confirm: true,
        app_metadata: {
          managed_org_admin: true,
          provisioned_tenant_id: tenantId,
          ...(department ? { department_account: department } : {}),
        },
        ...(name ? { user_metadata: { display_name: name } } : {}),
      });
      if (error?.code === "email_exists" || error?.code === "user_already_exists") throw fault("username_unavailable");
      if (error?.code === "weak_password") throw fault("weak_password");
      if (error || !data.user) throw fault("identity_unavailable");
      return data.user.id;
    },
    createStaffUser: async (email: string, password: string, metadata: Record<string, unknown>, name: string) => {
      const { data, error } = await admin.auth.admin.createUser({
        email, password, email_confirm: true, app_metadata: metadata,
        user_metadata: { display_name: name },
      });
      if (error || !data.user) throw fault("identity_unavailable");
      return data.user.id;
    },
    updateStaffPassword: updatePassword,
    deleteUser: async (id: string) => {
      const { error } = await admin.auth.admin.deleteUser(id);
      if (error) throw fault("identity_unavailable");
    },
    checkPassword: async (actor: { id: string; email: string }, password: string) => {
      const probe = createClient(url, publicKey, { auth });
      const { data, error } = await probe.auth.signInWithPassword({ email: actor.email, password });
      if (error || !data.session) return false;
      await admin.auth.admin.signOut(data.session.access_token, "local");
      return data.user?.id === actor.id;
    },
    setPassword: (id: string, password: string, generation?: string | null, resetToken?: string | null) =>
      updatePassword(id, password, generation
        ? { jentra_handover_generation: generation }
        : resetToken ? { jentra_subscription_reset_token: resetToken } : undefined),
    setOperatorPassword: (id: string, password: string, token: string) =>
      updatePassword(id, password, { jentra_operator_password_token: token }),
    sendMail: async (email: string, subject: string, text: string, idempotencyKey?: string) => {
      if (!apiKey || !sender) throw fault("delivery_unavailable");
      const result = await fetch("https://api.resend.com/emails", {
        method: "POST",
        redirect: "error",
        signal: AbortSignal.timeout(10000),
        headers: {
          Authorization: `Bearer ${apiKey}`, "content-type": "application/json",
          ...(idempotencyKey ? { "Idempotency-Key": idempotencyKey } : {}),
        },
        body: JSON.stringify({ from: sender, to: [email], subject, text }),
      });
      if (!result.ok) {
        await result.body?.cancel();
        throw fault("delivery_unavailable");
      }
      await result.body?.cancel();
    },
  });
});
