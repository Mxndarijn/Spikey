# Moving the backend from Supabase to our own server (plan)

Status: **plan only.** Decided: fresh start, hosting on the user's Hetzner
Kubernetes cluster. Waiting on the other answers (open questions at the end). Nothing is built, deployed or created yet. Branch: `claude/server-backend-e4288c`,
cut from `next-features-3` at 6714cff.

Visual version, with the architecture and flow diagrams (old vs new), the
feature table with endpoints and risk, hosting costs and the rollout timeline:
<https://claude.ai/artifact/6KYxuzHJ5gEMQq6bxGNaUm> (source:
`docs/mockups/server_migration.html`). This file is the text copy; keep both in
step.

## 1. What the game uses Supabase for today

Every call from the phone goes through one class, `SupabaseClient`
(`services/supabase_client.gd`): a session (`ensure_session`) and
`call_db(name, body) -> {ok, code, data}`, which is `POST /rest/v1/rpc/<name>`.
The game never reads a table directly. All logic is in `security definer`
Postgres functions (`supabase/migrations/`, 18 files). Every table has RLS on
with no policies, so the public key can only call the granted functions.

### 1.1 Players and sign-in

| Today | What the server must do |
|---|---|
| `POST /auth/v1/signup` (anonymous), `/auth/v1/token?grant_type=refresh_token`, `grant_type=password` | Make an anonymous player and hand out a short access token plus a refresh token. Never make a new player because of a network error (the client already handles this: `SESSION_GONE` codes). |
| Edge Function `device-key` (`supabase/functions/device-key`): the 32-byte device key becomes the password of `<uid>@device.flapjaw.invalid` | Sign in with the device key (`user://device_key.json`, iOS Keychain), so a restored backup is the same player. Our own server can make the key the main credential: store only its hash, and sign in with it directly, no fake email. |
| `players` (name, flyer), `set_player`, `spikey_ensure_player`, name filter (`banned_words`, `spikey_name_allowed`, look-alike collapsing) | Same table, same name filter server-side. |

### 1.2 Runs, boards and the replay check

| Function | Checks the server runs |
|---|---|
| `submit_run(name, flyer, score, gameplay_version, seed, taps, played_at, loadout, season, coins, end_tick, revives)` | Signed in. `played_at` trusted only within 2 days back / 5 min ahead, else now. Taps array of at most 20000, revives at most 1. Loadout object at most 1 KB. Season -1..100, coins 0..100000, end tick 0..10M, else null. Stored `pending`. Board day = Amsterdam date (`spikey_board_zone`). |
| `get_board(board)`: `daily` (Today), `daily_run`, `alltime` | Best run per player, top 100, `ok` runs for everyone plus the caller's own `pending`, the caller's rank, player count, `resets_in_s`. Daily Run rows of others are `locked` until the day is over. Premium looks only when bought (`spikey_may_show`, `spikey_paid_loadout`). Plates, revived flag. |
| `get_run(run)` | The replay (seed, taps, revives, season, loadout) for Watch; never a rejected run; Daily Run runs locked until the reset. |
| Checker: `worker_pending_runs`, `worker_record_results` (service role), `.github/workflows/verify-runs.yml` + `server/verify_batch.gd` (`RunChecker`), woken by `spikey_wake_checker` (pg_net -> GitHub dispatch, token in `worker_settings`), every 10 min as a safety net | Replay every pending run with the sim. Same score, coins and end tick and a season in play around that day: `ok`. Different: `rejected` with a reason. Older gameplay version: `outdated`. Newer than the checker: stays `pending`. Today this takes about 2 minutes (a GitHub job starting Godot); on our own server it can be well under a second. |
| Queued runs (client): `user://pending_runs.json` in `SupabaseLeaderboard` | The client side stays. The server must keep the contract the queue relies on: 4xx (not 401) = bad data, dropped; 404 = "function unknown", so the run waits or is sent with fewer arguments (`NEWER_ARGS`); 401 = sign in again; anything else = try later. A run played offline counts for its own day if sent within 2 days. **Idempotency is missing today**: a run whose answer was lost is sent twice. The new server should take a client run id and ignore repeats. |

### 1.3 Daily Run

`get_daily_run`, `start_daily_try(name, flyer)`, `submit_daily_run(try, ...)`;
tables `daily_runs`, `daily_tries`, `daily_run_secret`, `daily_run_prizes`,
`daily_run_settled` (`20261113130000_daily_run.sql`).

- The day's seed is md5(server secret + day); the secret never leaves the
  server, and the seed only comes with a try, so nobody plays tomorrow early.
- Tries 1 to 3 (`DailyRunRules.TRIES_PER_DAY`); a try counts once started.
- `submit_daily_run`: once per try, the try must be the caller's, not too old,
  the day's seed and season, no revives. Counts for the day the try started.
- Day numbers from 2026-11-14 (`spikey_daily_run_epoch`), season from
  `spikey_season_of` (must match `SeasonCalendar`).

### 1.4 Diamonds, prizes, earn status, score ladder

`get_wallet`, `claim_prizes`, `spend_diamonds(amount, reason, ref, request_id)`,
`get_earn_status`; tables `wallets`, `diamond_ledger`, `daily_prizes`,
`bonus_prizes`, `settled_days`, `spend_requests`, `run_carry`, `played_days`,
`ladder_marks`.

- Diamonds live only on the server; every change is a ledger row
  (`spikey_change_diamonds`), never below 0.
- Spending: amount 1..10000, known reason, a request id so a retry never
  spends twice (`spend_requests`).
- Prizes are settled lazily (`spikey_settle_days`, `spikey_settle_daily_runs`)
  inside `get_wallet`, `claim_prizes` and `get_earn_status`: top 10 of each
  finished day for Today and Daily Run (3, 2, 2, then 1).
- Bonuses (`spikey_award_bonuses`): best-score milestones 25/50/75/100, the
  ladder every 50 from 150 to 1000 (3 each, no back-pay below `ladder_marks`),
  7-day streak from `played_days`. Only checked (`ok`) runs count.
- `spikey_reset_boards()` (admin only) empties runs but keeps `run_carry` and
  `played_days`.

### 1.5 The save on the server and paid items

`sync_profile(data, base)` (`profiles`, `premium_items`):

- Save at most 64 KB; kept only when based on the newest revision, else
  `conflict` with the newest copy (the client merges, `Profile.merge_cloud`).
- Every answer lists the premium items bought with diamonds (`paid`).
- Gold is checked, not enforced: `gold_excess` = save gold minus the most the
  player could have earned (`spikey_gold_ceiling`).

### 1.6 Push alerts

`register_push(token, platform, utc_offset)`, `set_push_enabled`,
`send_test_push`; tables `push_devices`, `spot_alerts`, `spot_state`;
`spikey_check_spots` after each checker batch decides who lost a prize spot;
the Edge Function `send-alerts` carries the outbox to Firebase Cloud Messaging
(needs the Firebase service account), woken through pg_net
(`worker_set_push`, `20261110120000_wake_sender.sql`).

### 1.7 Ops around it

- `ping` and `.github/workflows/supabase-keepalive.yml` (the free plan pauses).
- `.github/workflows/supabase-db.yml` applies migrations,
  `supabase-functions.yml` deploys the two Edge Functions.
- `tools/db_test.ps1`: a throwaway `postgres:16-alpine` container, stubs for
  Supabase's `auth` schema (`supabase/tests/00_stubs.sql`), every migration,
  then `supabase/tests/NN_test_*.sql`. CI: `supabase-db.yml`.
- Config: `services/supabase_config.json` (url + anon key), written by the
  phone build workflows from the `SUPABASE_URL` / `SUPABASE_ANON_KEY` secrets.

Not on Supabase, and staying where they are: ads (AdMob), the store (no
billing yet; when it comes, receipt checks belong on the server too), push
delivery itself (Firebase), `RunStore` (local `user://runs.json`).

## 2. The client interface

The service classes (`LeaderboardService`, `WalletService`, `PushService`,
`ProfileSync`) are already the game-facing interface, and `game/` only knows
them, except `AppServices` and `main.gd`, which build them from
`SupabaseClient`. Every Supabase class talks to the server only through
`ensure_session()` and `call_db(name, body)`. So the cut is one level down:

```
BackendClient (services/backend_client.gd, new, abstract)
    signal session_checked(ok)
    restore()                      # session + device key from user://
    ensure_session() -> bool
    call_db(op: String, body: Dictionary) -> {ok, code, data}
    is_signed_in() / player_id()
  SupabaseClient   (today's class, extends BackendClient, unchanged behaviour)
  FlapjawClient    (new: POST <url>/v1/<op>, Bearer token, device-key sign-in)
```

- Rename `SupabaseLeaderboard` -> `OnlineLeaderboard`, `SupabaseWallet` ->
  `OnlineWallet` (or keep the names) and type them against `BackendClient`.
- The new server keeps **the same operation names, argument names and JSON
  answers** as the SQL functions, and the same status-code meanings (404 =
  unknown op, 401 = sign in again, other 4xx = bad data). Then the services and
  their tests do not change at all; only the transport does.
- One config file, `services/backend_config.json`:
  `{"kind": "supabase" | "flapjaw", "url": ..., "anon_key": ...}`.
  The old `supabase_config.json` keeps working (read as kind `supabase`).
  `AppServices.make_leaderboard` picks the client by kind.
- Tests: a contract test runs the same request/answer fixtures through both
  clients against a fake HTTP host, so the two can't drift while both exist.

This is a small refactor that can land first, with no server at all and no
behaviour change.

## 3. Server stack

| Option | For | Against |
|---|---|---|
| **A. Rust (axum + sqlx) + Postgres** (recommended) | Links `tools/fastsim-rs/sim` as a crate, so a run is checked inside the request in microseconds. One small static binary, low memory, typed end to end. sqlx checks SQL against the schema at build time. | A second production language next to GDScript; Rust compile times. |
| B. TypeScript (Node/Deno, Hono or Fastify) + Postgres | Fast to write; the two Edge Functions are already TypeScript. | The replay check must shell out to Godot or to the Rust binary. |
| C. Go + Postgres | Simple to run, quick builds. | Same as B for the replay check; no code shared with anything here. |
| D. Keep Postgres functions, put a thin HTTP layer in front (PostgREST-like) | Least rewriting: the SQL moves as it is. | Keeps the logic in plpgsql, the part that is hardest to test and refactor; auth still to write. |

**Recommendation: A**, keeping the schema and much of the SQL. Postgres stays
the database, the tables carry over one to one, and the rules that are pure
queries (boards, settling days) can stay SQL called from Rust; the request
checks move into typed handlers. Jobs that pg_net and GitHub run today (wake
the checker, settle, send push alerts) become background tasks in the same
process; the FCM sender is ported from `send-alerts/index.ts`.

**Where it runs (decided)**: one extra Hetzner VM joined to the user's
existing Kubernetes cluster (managed with kubectl), in its own namespace
`flapjaw`. The node is labelled and tainted for the game (`flapjaw=true`,
`dedicated=flapjaw:NoSchedule`); every game pod has the matching nodeSelector
and toleration, so the game and the other application never share a machine.
The cluster's existing ingress controller and certificates are reused.

Manifests (in the repo, for example `deploy/k8s/` with Kustomize, applied by
the user with `kubectl apply -k`; no session deploys):

- Namespace `flapjaw`, with a ResourceQuota.
- Deployment `server`: the Rust server and verifier, 1 replica to start,
  readiness and liveness on `/v1/ping`.
- Deployment `godot-worker`: headless Godot that re-checks rejected runs.
- Service (ClusterIP) and Ingress: one host on the cluster's ingress class,
  TLS from its certificate setup.
- Secret: database password, token signing key, Daily Run secret, Firebase
  service account.
- Postgres (below), its volume on the Hetzner CSI driver; a CronJob for a
  nightly `pg_dump` to object storage unless an operator backs up itself.
- NetworkPolicy: only the ingress reaches the server, only the server reaches
  Postgres.

Postgres options:

| Option | For | Against |
|---|---|---|
| **Plain StatefulSet** (recommended at this size) | Simplest; a pg_dump CronJob covers backups | No automatic failover; restore by hand |
| CloudNativePG operator | Backups, point-in-time restore, failover built in | An operator to run, unless the cluster has one already (then use it) |
| The other application's Postgres, a new database | No new database pods | Ties the game to that database and its maintenance |
| Managed Postgres outside the cluster | Someone else runs it | Another provider and bill, latency, about EUR 15+ a month |

Rough monthly cost (estimates, not quotes): the VM EUR 5 to 10 (2 vCPU /
4 GB is plenty), a 10 to 20 GB volume about EUR 1, object storage for backups
EUR 0 to 5. Total about EUR 6 to 16. Ingress, certificates and the domain come
from the existing setup.

The repo gets `server/` as a Cargo workspace member (next to the GDScript
verifier that is there now) or `backend/`, the manifests, and a local dev
setup that runs fully offline; the existing `tools/db_test.ps1` pattern
(throwaway Postgres container) carries over for its tests.

## 4. The replay check on the server

Today: GitHub job, headless Godot, `RunChecker` -> `Replay.verify()`, the
GDScript sim, which is the one source of truth.

Plan:

1. **Rust first**: the server links `fastsim-rs/sim` and replays each run when
   it arrives (a background queue, so a slow run never blocks the request).
   The check already enforces that the Rust copy matches GDScript (parity
   step), so on the same gameplay version the answer should be identical.
2. **Godot has the last word on rejections**: a run the Rust check rejects is
   not final until headless Godot (`server/verify_batch.gd`, the same as today)
   agrees, in a small worker container next to the server. Rejections are rare,
   so this costs almost nothing and a parity slip can never hide an honest
   score. Disagreements are logged as parity bugs.
3. **Old versions**: the server must check every gameplay version still
   allowed, not only the newest. The Rust sim makes this easy: build one verifier
   per allowed version (a frozen copy of the crate per version, `sim_g24`,
   `sim_g25`, ...) and dispatch on `gameplay_version`, the plan in
   ARCHITECTURE.md "Gameplay versions", done in Rust instead of in `sim/versions/`.
4. Today's `ok` / `rejected` / `outdated` / `pending` rules and reasons stay
   the same, so the boards behave as now, only faster.

Later anti-cheat that becomes easier on our own server: server-issued one-time
seeds for endless runs (as the Daily Run does already), rate limits per player
and IP, plausibility checks (tap speed, timing variance, jumps above history)
into a review queue, Play Integrity / App Attest tokens checked on sign-in.

## 5. Data (decided: fresh start)

No player data carries over. The new server starts empty: new players, empty
boards, no diamonds or prizes. Nothing is copied from Supabase and no session
reads its data. The new server gets its own Daily Run secret.

Still to decide: phones keep their local save (gold, owned items, best score,
settings), and the first `sync_profile` would upload it to the new server.
Keep those saves, or reset them with the new build (question 8)?

## 6. Rollout

With no data to copy there is no freeze. Supabase keeps running untouched
until it is switched off, so it is the rollback the whole way.

1. **BackendClient interface and an update prompt** (no server): Supabase stays
   the only backend; plus a minimum-version answer the game shows as "please
   update", since today's builds have no such prompt. Check passes.
   Rollback: revert the commits.
2. **Server skeleton, local**: auth with device key, `ping`, `submit_run`,
   `get_board`, `get_run`, `set_player`, the Rust checker. Contract fixtures
   pass against both the SQL (`tools/db_test.ps1`) and the new server.
3. **The rest, local**: Daily Run, wallet, prizes, earn status and ladder,
   profiles, push; `supabase/tests/*.sql` cases ported as server tests; the
   Kubernetes manifests, checked with a dry run.
4. **On the cluster** (the user adds the node and applies the manifests):
   debug builds point at the new server for playtests, release builds stay on
   Supabase. Rollback: `kubectl delete namespace flapjaw`.
5. **Cutover**: a release build with the new server in its config, forced
   update. Everyone starts fresh. Old builds keep talking to Supabase until it
   is switched off, so friends are told to update; builds from step 1 on get
   the prompt. Rollback: ship a build with the Supabase config again.
6. **Retire, later**: once no old builds call it (a few weeks), the user pauses
   or deletes the Supabase project; a later change removes the Supabase client,
   migrations, Edge Functions and workflows.

## 7. Open questions for the user

Decided: fresh start, no data carried over (Q3); a new node in the user's
Hetzner Kubernetes cluster (Q1).

1. **Language**: Rust (recommended, shares the sim), TypeScript, Go, or
   something else?
2. **Ingress and certificates**: which ingress controller and class
   (ingress-nginx, Traefik, ...)? cert-manager, and which ClusterIssuer? Which
   host name for the game's API?
3. **Postgres**: does the cluster already run Postgres or an operator such as
   CloudNativePG? If not, is a plain StatefulSet with a nightly dump fine?
   Where do backups go?
4. **Secrets and backups**: who holds the secrets (database, token key, Daily
   Run secret, Firebase key)? Plain Secrets made by hand, or Sealed Secrets,
   SOPS or External Secrets? Who keeps the backups?
5. **Applying manifests**: Kustomize with `kubectl apply -k`, or Helm or a
   GitOps tool like the other application?
6. **Fallback checker**: keep the GitHub + Godot checker until Supabase is
   switched off?
7. **Board clock**: keep the Amsterdam midnight reset for both daily boards?
8. **How far the fresh start goes**: keep the phones' local saves (gold,
   items, best score, settings), or reset them too?
