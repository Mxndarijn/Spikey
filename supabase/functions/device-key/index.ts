// Gives a phone's player a sign-in that outlives a reinstall: a long random
// device key, which becomes the password of a made-up address only this
// player has ("<player id>@device.flapjaw.invalid"; .invalid never receives
// mail, so nothing is ever sent to it).
//
// Why: an anonymous player can only come back with its refresh token, and
// Supabase replaces that token every hour. A phone backup (Android Auto
// Backup) is up to a day old, so the token in it is dead. The device key
// never changes, so a restored backup can still sign in with it
// (services/supabase_client.gd, docs/LEADERBOARD_SETUP.md).
//
// The game calls this signed in, with {"key": "Fj-<64 hex>"}. The function
// looks up who is calling from their own access token and sets the address
// and key on that player only, through the admin API. A player that already
// has a real address (a future "link account") is left alone.
//
// SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are provided
// by Supabase itself. No dependencies: everything here is fetch.

export type Env = {
  supabaseUrl: string;
  anonKey: string;
  serviceRoleKey: string;
};

type Fetch = typeof fetch;

export const DOMAIN = "device.flapjaw.invalid";
/**
 * "Fj-" and 64 hex characters (32 random bytes): an upper and a lower case
 * letter, a digit and a symbol, so a project with strict password rules
 * takes it too, and short enough for bcrypt's 72 bytes.
 */
export const KEY = /^Fj-[0-9a-f]{64}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export function deviceEmail(playerId: string): string {
  return `${playerId}@${DOMAIN}`;
}

export async function handle(req: Request, env: Env, fetchFn: Fetch = fetch): Promise<Response> {
  const json = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { "Content-Type": "application/json" },
    });
  if (req.method !== "POST") return json(405, { error: "POST only" });
  if (!env.supabaseUrl || !env.serviceRoleKey) return json(503, { error: "not set up" });
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json(401, { error: "not signed in" });
  let key = "";
  try {
    const body = await req.json();
    key = typeof body?.key === "string" ? body.key : "";
  } catch {
    return json(400, { error: "bad body" });
  }
  if (!KEY.test(key)) return json(400, { error: "bad key" });
  const base = env.supabaseUrl.replace(/\/+$/, "");
  try {
    // Who is calling: the player this access token belongs to.
    const who = await fetchFn(`${base}/auth/v1/user`, {
      headers: { Authorization: auth, apikey: env.anonKey || env.serviceRoleKey },
    });
    if (!who.ok) return json(401, { error: "not signed in" });
    const user = await who.json();
    const id = typeof user?.id === "string" ? user.id : "";
    if (!UUID.test(id)) return json(401, { error: "not signed in" });
    const email = deviceEmail(id);
    if (typeof user.email === "string" && user.email !== "" && user.email !== email) {
      return json(409, { error: "has its own sign-in" });
    }
    const res = await fetchFn(`${base}/auth/v1/admin/users/${id}`, {
      method: "PUT",
      headers: {
        apikey: env.serviceRoleKey,
        Authorization: `Bearer ${env.serviceRoleKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ email, password: key, email_confirm: true }),
    });
    if (!res.ok) return json(502, { error: "could not save the key", status: res.status });
    return json(200, { email });
  } catch (e) {
    return json(500, { error: e instanceof Error ? e.message : "failed" });
  }
}

if (import.meta.main) {
  Deno.serve((req) =>
    handle(req, {
      supabaseUrl: Deno.env.get("SUPABASE_URL") ?? "",
      anonKey: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    })
  );
}
