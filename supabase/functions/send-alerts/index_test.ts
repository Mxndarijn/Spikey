// deno test supabase/functions/send-alerts/   (tools/functions_test.ps1 runs it in Docker)
// Firebase, Google sign-in and the database are stand-ins: no network is used.
import {
  accessToken,
  type Env,
  handle,
  message,
  parseAccount,
  sendAlerts,
  tokenIsDead,
} from "./index.ts";

Deno.test("the service account key is read as JSON or as base64 of it", () => {
  const key = { project_id: "p", client_email: "e", private_key: "k\nk", token_uri: "t" };
  const text = JSON.stringify(key);
  eq(parseAccount(text), key, "plain JSON");
  eq(parseAccount(btoa(text) + "\n"), key, "base64, with the newline a shell adds");
});

function eq(got: unknown, want: unknown, what: string) {
  const a = JSON.stringify(got);
  const b = JSON.stringify(want);
  if (a !== b) throw new Error(`${what}: expected ${b}, got ${a}`);
}

function b64urlToBytes(text: string): ArrayBuffer {
  const raw = atob(text.replace(/-/g, "+").replace(/_/g, "/"));
  const buffer = new ArrayBuffer(raw.length);
  const out = new Uint8Array(buffer);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return buffer;
}

/** A throwaway service account with a real RSA key, made for this test run. */
async function testAccount() {
  const pair = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  let text = "";
  for (const b of der) text += String.fromCharCode(b);
  const lines = btoa(text).match(/.{1,64}/g)!.join("\n");
  return {
    publicKey: pair.publicKey,
    account: {
      project_id: "test-project",
      client_email: "sender@test-project.iam.gserviceaccount.com",
      private_key: `-----BEGIN PRIVATE KEY-----\n${lines}\n-----END PRIVATE KEY-----\n`,
      token_uri: "https://oauth2.example/token",
    },
  };
}

type Call = { url: string; body: string; headers: Record<string, string> };

/** A fetch that answers like Google, Firebase and the database would. */
function fakeFetch(pending: unknown[], fcm: (token: string) => Response) {
  const calls: Call[] = [];
  const fn = (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    const body = init?.body instanceof URLSearchParams
      ? init.body.toString()
      : String(init?.body ?? "");
    calls.push({ url, body, headers: (init?.headers ?? {}) as Record<string, string> });
    if (url.endsWith("/rpc/worker_pending_alerts")) return Promise.resolve(Response.json(pending));
    if (url.endsWith("/rpc/worker_mark_alerts")) return Promise.resolve(Response.json(1));
    if (url === "https://oauth2.example/token") {
      return Promise.resolve(Response.json({ access_token: "google-token" }));
    }
    if (url.includes("fcm.googleapis.com")) {
      return Promise.resolve(fcm(JSON.parse(body).message.token));
    }
    return Promise.resolve(new Response("unexpected " + url, { status: 500 }));
  };
  return { fn: fn as typeof fetch, calls };
}

function env(account: unknown): Env {
  return {
    supabaseUrl: "https://db.example",
    serviceRoleKey: "service-key",
    serviceAccount: JSON.stringify(account),
    alertsSecret: "open-sesame",
  };
}

const ALERTS = [
  { id: 1, token: "phone-a", platform: "android", title: "Kestrel took 1st with 96", body: "x" },
  { id: 2, token: "phone-gone", platform: "android", title: "t", body: "b" },
  { id: 3, token: "phone-busy", platform: "ios", title: "t", body: "b" },
];

Deno.test("the service account signs a token request Google can verify", async () => {
  const { account, publicKey } = await testAccount();
  const { fn, calls } = fakeFetch([], () => Response.json({}));
  eq(await accessToken(account, fn, 1_700_000_000), "google-token", "the access token");
  const assertion = new URLSearchParams(calls[0].body).get("assertion")!;
  const [header, claims, signature] = assertion.split(".");
  const ok = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    publicKey,
    b64urlToBytes(signature),
    new TextEncoder().encode(`${header}.${claims}`),
  );
  eq(ok, true, "the signature matches the key");
  const c = JSON.parse(new TextDecoder().decode(b64urlToBytes(claims)));
  eq(c.iss, account.client_email, "issued by the service account");
  eq(c.scope, "https://www.googleapis.com/auth/firebase.messaging", "for messaging only");
  eq(c.exp - c.iat, 600, "valid for ten minutes");
});

Deno.test("a message carries the alert's words and the game's channel", () => {
  const m = message(ALERTS[0]) as {
    message: {
      token: string;
      notification: { title: string };
      android: { notification: { channel_id: string } };
    };
  };
  eq(m.message.token, "phone-a", "to the phone");
  eq(m.message.notification.title, "Kestrel took 1st with 96", "the title");
  eq(m.message.android.notification.channel_id, "board_alerts", "the channel");
});

Deno.test("only a gone token is forgotten", () => {
  eq(tokenIsDead(404, null), true, "404");
  eq(tokenIsDead(400, { error: { details: [{ errorCode: "UNREGISTERED" }] } }), true, "unregistered");
  eq(tokenIsDead(400, { error: { details: [{ errorCode: "INVALID_ARGUMENT" }] } }), false, "bad payload");
  eq(tokenIsDead(503, null), false, "Firebase is down");
});

Deno.test("sends what is queued and reports each result", async () => {
  const { account } = await testAccount();
  const { fn, calls } = fakeFetch(ALERTS, (token) => {
    if (token === "phone-gone") {
      return Response.json({ error: { details: [{ errorCode: "UNREGISTERED" }] } }, { status: 404 });
    }
    if (token === "phone-busy") return new Response("try later", { status: 503 });
    return Response.json({ name: "projects/test-project/messages/1" });
  });
  eq(await sendAlerts(env(account), fn, 1_700_000_000), { sent: 1, failed: 2 }, "the count");
  const sends = calls.filter((c) => c.url.includes("fcm.googleapis.com"));
  eq(sends.length, 3, "one request per alert");
  eq(
    sends[0].url,
    "https://fcm.googleapis.com/v1/projects/test-project/messages:send",
    "to this project",
  );
  eq(sends[0].headers.Authorization, "Bearer google-token", "with Google's token");
  const mark = calls.find((c) => c.url.endsWith("/rpc/worker_mark_alerts"))!;
  eq(mark.headers.apikey, "service-key", "the database is asked with the service key");
  eq(JSON.parse(mark.body), {
    p_results: [
      { id: 1, status: "sent" },
      { id: 2, status: "failed", forget_token: true },
      { id: 3, status: "failed" },
    ],
  }, "what the database hears");
});

Deno.test("nothing queued: Google and Firebase are not bothered", async () => {
  const { account } = await testAccount();
  const { fn, calls } = fakeFetch([], () => Response.json({}));
  eq(await sendAlerts(env(account), fn), { sent: 0, failed: 0 }, "nothing sent");
  eq(calls.length, 1, "only the outbox was read");
});

Deno.test("only callers with the secret may trigger a send", async () => {
  const { account } = await testAccount();
  const { fn, calls } = fakeFetch([], () => Response.json({}));
  const post = (auth?: string) =>
    new Request("https://fn.example/send-alerts", {
      method: "POST",
      headers: auth ? { Authorization: auth } : {},
    });
  eq((await handle(post(), env(account), fn)).status, 401, "no secret");
  eq((await handle(post("Bearer wrong"), env(account), fn)).status, 401, "wrong secret");
  eq(calls.length, 0, "a refused caller reads nothing");
  eq((await handle(post("Bearer open-sesame"), env(account), fn)).status, 200, "the right secret");
  const get = new Request("https://fn.example/send-alerts");
  eq((await handle(get, env(account), fn)).status, 405, "GET");
  const unset = { ...env(account), alertsSecret: "" };
  eq((await handle(post("Bearer "), unset, fn)).status, 503, "no secret set up: closed, not open");
});
