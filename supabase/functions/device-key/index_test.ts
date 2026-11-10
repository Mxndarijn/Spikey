// deno test supabase/functions/device-key/   (tools/functions_test.ps1 runs it in Docker)
// Supabase Auth is a stand-in: no network is used.
import { deviceEmail, type Env, handle } from "./index.ts";

const ENV: Env = { supabaseUrl: "https://p.supabase.co/", anonKey: "anon", serviceRoleKey: "srk" };
const ID = "11111111-2222-4333-8444-555555555555";
const KEY = "Fj-" + "ab12".repeat(16);

function eq(got: unknown, want: unknown, what: string) {
  const a = JSON.stringify(got);
  const b = JSON.stringify(want);
  if (a !== b) throw new Error(`${what}: expected ${b}, got ${a}`);
}

type Call = { url: string; method: string; headers: Record<string, string>; body: unknown };

/** Supabase Auth: `user` answers /auth/v1/user (null: the token is not valid). */
function fakeAuth(user: Record<string, unknown> | null, adminOk = true) {
  const calls: Call[] = [];
  const fetchFn = (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    const headers = Object.fromEntries(new Headers(init?.headers).entries());
    const body = init?.body ? JSON.parse(String(init.body)) : null;
    calls.push({ url, method: init?.method ?? "GET", headers, body });
    if (url.endsWith("/auth/v1/user")) {
      return Promise.resolve(
        user ? new Response(JSON.stringify(user)) : new Response("{}", { status: 401 }),
      );
    }
    return Promise.resolve(new Response("{}", { status: adminOk ? 200 : 422 }));
  };
  return { calls, fetchFn: fetchFn as typeof fetch };
}

function request(body: unknown, token = "player-token"): Request {
  return new Request("https://f/device-key", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });
}

Deno.test("sets the key as the password of the caller's own device address", async () => {
  const auth = fakeAuth({ id: ID, email: "" });
  const res = await handle(request({ key: KEY }), ENV, auth.fetchFn);
  eq(res.status, 200, "status");
  eq(await res.json(), { email: deviceEmail(ID) }, "answer");
  eq(auth.calls.length, 2, "asks who calls, then saves");
  eq(auth.calls[0].headers["authorization"], "Bearer player-token", "the caller's own token");
  eq(auth.calls[1].url, `https://p.supabase.co/auth/v1/admin/users/${ID}`, "only that player");
  eq(auth.calls[1].method, "PUT", "method");
  eq(auth.calls[1].headers["authorization"], "Bearer srk", "admin call");
  eq(
    auth.calls[1].body,
    { email: `${ID}@device.flapjaw.invalid`, password: KEY, email_confirm: true },
    "address and key, no mail sent",
  );
});

Deno.test("a player that already has its device address gets the new key", async () => {
  const auth = fakeAuth({ id: ID, email: deviceEmail(ID) });
  eq((await handle(request({ key: KEY }), ENV, auth.fetchFn)).status, 200, "status");
});

Deno.test("a player with a real address is left alone", async () => {
  const auth = fakeAuth({ id: ID, email: "someone@example.com" });
  eq((await handle(request({ key: KEY }), ENV, auth.fetchFn)).status, 409, "status");
  eq(auth.calls.length, 1, "nothing saved");
});

Deno.test("refuses without a valid sign-in or key", async () => {
  const nobody = fakeAuth(null);
  eq((await handle(request({ key: KEY }), ENV, nobody.fetchFn)).status, 401, "bad token");
  eq(nobody.calls.length, 1, "nothing saved");
  const auth = fakeAuth({ id: ID });
  for (const key of ["", "short", "Fj-" + "AB12".repeat(16), KEY + "0", 42]) {
    eq((await handle(request({ key }), ENV, auth.fetchFn)).status, 400, `key ${key}`);
  }
  eq(auth.calls.length, 0, "a bad key never reaches Auth");
  const bare = new Request("https://f", { method: "POST", body: JSON.stringify({ key: KEY }) });
  eq((await handle(bare, ENV, auth.fetchFn)).status, 401, "no Authorization header");
  const get = new Request("https://f", { method: "GET" });
  eq((await handle(get, ENV, auth.fetchFn)).status, 405, "POST only");
  eq((await handle(request({ key: KEY }), { ...ENV, serviceRoleKey: "" })).status, 503, "setup");
});

Deno.test("reports when Auth refuses to save", async () => {
  const auth = fakeAuth({ id: ID }, false);
  eq((await handle(request({ key: KEY }), ENV, auth.fetchFn)).status, 502, "status");
});
