const encode = bytes => btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
const jsonPart = value => encode(new TextEncoder().encode(JSON.stringify(value)));

// Server-only credentials are injected individually by the deployment owner.
// This module never reads a local Firebase key file or emits credential values.
export function createGoogleSender({ projectId, clientEmail, privateKey, fetch: http = globalThis.fetch,
  crypto = globalThis.crypto, clock = () => Date.now() }) {
  if (!/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(projectId ?? "") ||
      typeof clientEmail !== "string" || !/^[^\s@]+@[^\s@]+\.iam\.gserviceaccount\.com$/.test(clientEmail) ||
      typeof privateKey !== "string" || !privateKey.includes("PRIVATE KEY")) throw Error("PUSH_SERVER_CONFIG_REQUIRED");
  let cached, pending;
  async function accessToken() {
    if (cached && cached.expires > clock() + 60000) return cached.value;
    if (pending) return pending;
    pending = (async () => {
      const pem = privateKey.replaceAll("\\n", "\n").replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "");
      const key = await crypto.subtle.importKey("pkcs8", Uint8Array.from(atob(pem), c => c.charCodeAt(0)),
        { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
      const now = Math.floor(clock() / 1000);
      const unsigned = `${jsonPart({ alg: "RS256", typ: "JWT" })}.${jsonPart({ iss: clientEmail,
        scope: "https://www.googleapis.com/auth/firebase.messaging", aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600 })}`;
      const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned));
      const response = await http("https://oauth2.googleapis.com/token", { method: "POST", signal: AbortSignal.timeout(10000),
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${unsigned}.${encode(new Uint8Array(signature))}` }) });
      if (!response.ok) throw Error("PUSH_GOOGLE_AUTH_UNAVAILABLE");
      const data = await response.json();
      if (typeof data.access_token !== "string" || !data.access_token || !Number.isFinite(data.expires_in) ||
          data.expires_in < 1 || data.expires_in > 3600) throw Error("PUSH_GOOGLE_AUTH_UNAVAILABLE");
      cached = { value: data.access_token, expires: clock() + data.expires_in * 1000 };
      return cached.value;
    })();
    try { return await pending; } finally { pending = undefined; }
  }
  return async function send(payload) {
    const token = await accessToken();
    const response = await http(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
      method: "POST", signal: AbortSignal.timeout(10000),
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" }, body: JSON.stringify(payload),
    });
    if (response.status === 401) cached = undefined;
    return response;
  };
}
