// Sends the queued Board alerts (lost prize spots on the daily board) to
// phones through Firebase Cloud Messaging.
//
// The database decides who gets an alert and what it says
// (supabase/migrations/20261110110000_push_alerts.sql). This function only
// carries the outbox to Firebase and reports back what was sent. The database
// calls it right after it queued an alert; calling it with nothing queued is
// harmless.
//
// Secrets (set by .github/workflows/supabase-functions.yml):
//   FIREBASE_SERVICE_ACCOUNT  the service account key file from Firebase, as JSON
//                             text or that text in base64
//   ALERTS_SECRET             what callers must send as "Authorization: Bearer ..."
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase itself.
// No dependencies: everything here is fetch and Web Crypto.

export type Env = {
  supabaseUrl: string;
  serviceRoleKey: string;
  serviceAccount: string;
  alertsSecret: string;
};

type Alert = { id: number; token: string; platform: string; title: string; body: string };
type Result = { id: number; status: "sent" | "failed"; forget_token?: boolean };
type Fetch = typeof fetch;

const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const BATCH = 100;
/** The Android notification channel the game creates for these. */
export const CHANNEL = "board_alerts";

function base64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let text = "";
  for (const b of bytes) text += String.fromCharCode(b);
  return btoa(text).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): ArrayBuffer {
  const body = pem.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "");
  const raw = atob(body);
  const buffer = new ArrayBuffer(raw.length);
  const out = new Uint8Array(buffer);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return buffer;
}

/**
 * The service account key: the JSON text itself, or that text in base64 (how
 * the deploy workflow stores it, so its quotes and line breaks survive).
 */
export function parseAccount(
  text: string,
): { project_id: string; client_email: string; private_key: string; token_uri: string } {
  const trimmed = text.trim();
  return JSON.parse(trimmed.startsWith("{") ? trimmed : atob(trimmed));
}

/** A short-lived Google access token for the service account. */
export async function accessToken(
  account: { client_email: string; private_key: string; token_uri: string },
  fetchFn: Fetch,
  nowSeconds: number,
): Promise<string> {
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64url(JSON.stringify({
    iss: account.client_email,
    scope: SCOPE,
    aud: account.token_uri,
    iat: nowSeconds,
    exp: nowSeconds + 600,
  }));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(account.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  const assertion = `${header}.${claims}.${base64url(new Uint8Array(signature))}`;
  const res = await fetchFn(account.token_uri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!res.ok) throw new Error(`Google refused the service account (${res.status})`);
  const data = await res.json();
  if (!data.access_token) throw new Error("Google sent no access token");
  return data.access_token as string;
}

/** What Firebase is asked to deliver for one alert. */
export function message(alert: Alert): unknown {
  return {
    message: {
      token: alert.token,
      notification: { title: alert.title, body: alert.body },
      data: { kind: "board_alert" },
      android: { priority: "HIGH", notification: { channel_id: CHANNEL } },
      apns: { payload: { aps: { sound: "default" } } },
    },
  };
}

/** True when Firebase says this phone's token is gone for good. */
export function tokenIsDead(status: number, body: unknown): boolean {
  if (status === 404) return true;
  const details = (body as { error?: { details?: { errorCode?: string }[] } })?.error?.details;
  return Array.isArray(details) && details.some((d) => d?.errorCode === "UNREGISTERED");
}

async function rpc(env: Env, fetchFn: Fetch, name: string, args: unknown): Promise<unknown> {
  const res = await fetchFn(`${env.supabaseUrl}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: env.serviceRoleKey,
      Authorization: `Bearer ${env.serviceRoleKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(args),
  });
  if (!res.ok) throw new Error(`${name} failed (${res.status})`);
  return await res.json();
}

/** Sends everything queued. Returns how many were sent and how many failed. */
export async function sendAlerts(
  env: Env,
  fetchFn: Fetch = fetch,
  nowSeconds: number = Math.floor(Date.now() / 1000),
): Promise<{ sent: number; failed: number }> {
  const pending = await rpc(env, fetchFn, "worker_pending_alerts", { p_limit: BATCH }) as Alert[];
  if (!Array.isArray(pending) || pending.length === 0) return { sent: 0, failed: 0 };
  const account = parseAccount(env.serviceAccount);
  const token = await accessToken(account, fetchFn, nowSeconds);
  const url = `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`;
  const results: Result[] = [];
  for (const alert of pending) {
    try {
      const res = await fetchFn(url, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify(message(alert)),
      });
      if (res.ok) {
        results.push({ id: alert.id, status: "sent" });
        continue;
      }
      const body = await res.json().catch(() => null);
      const result: Result = { id: alert.id, status: "failed" };
      if (tokenIsDead(res.status, body)) result.forget_token = true;
      results.push(result);
    } catch (_) {
      results.push({ id: alert.id, status: "failed" });
    }
  }
  await rpc(env, fetchFn, "worker_mark_alerts", { p_results: results });
  const sent = results.filter((r) => r.status === "sent").length;
  return { sent, failed: results.length - sent };
}

/** The HTTP entry: only callers that know the secret may trigger a send. */
export async function handle(req: Request, env: Env, fetchFn: Fetch = fetch): Promise<Response> {
  const json = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { "Content-Type": "application/json" },
    });
  if (req.method !== "POST") return json(405, { error: "POST only" });
  if (!env.alertsSecret || !env.serviceAccount) return json(503, { error: "not set up" });
  if (req.headers.get("Authorization") !== `Bearer ${env.alertsSecret}`) {
    return json(401, { error: "wrong secret" });
  }
  try {
    return json(200, await sendAlerts(env, fetchFn));
  } catch (e) {
    return json(500, { error: e instanceof Error ? e.message : "failed" });
  }
}

if (import.meta.main) {
  Deno.serve((req) =>
    handle(req, {
      supabaseUrl: Deno.env.get("SUPABASE_URL") ?? "",
      serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      serviceAccount: Deno.env.get("FIREBASE_SERVICE_ACCOUNT") ?? "",
      alertsSecret: Deno.env.get("ALERTS_SECRET") ?? "",
    })
  );
}
