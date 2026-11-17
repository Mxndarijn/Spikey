# Moving the backend from Supabase to our own server

Status: **done.** Every build from v0.1.2 (gameplay v25) talks to our own
server; Supabase is retired. Its client (`SupabaseClient`), Edge Functions,
workflows and `supabase/` folder are gone; the migrations moved unchanged to
`backend/migrations/` and their SQL tests to `backend/sql_tests/`. This file is
kept as the plan and the record of how the move was made: the names below
(`services/supabase_client.gd`, `supabase/...`, the Supabase workflows) are as
they were then. How to run the server today: docs/DEPLOY.md.

Visual version, with the architecture and flow diagrams (old vs new), the
feature table with endpoints and risk, hosting costs and the rollout timeline:
<https://claude.ai/artifact/6KYxuzHJ5gEMQq6bxGNaUm> (source:
`docs/mockups/server_migration.html`). This file is the text copy; keep both in
step. The Move to a new phone plan: <https://claude.ai/artifact/VWL3jnUqwuM1tTWU8HynT5>
(`docs/ACCOUNT_TRANSFER.md`).

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
| Queued runs (client): `user://pending_runs.json` in `OnlineLeaderboard` | The client side stays. The server must keep the contract the queue relies on: 4xx (not 401) = bad data, dropped; 404 = "function unknown", so the run waits or is sent with fewer arguments (`NEWER_ARGS`); 401 = sign in again; anything else = try later. A run played offline counts for its own day if sent within 2 days. **Idempotency is missing today**: a run whose answer was lost is sent twice. The new server should take a client run id and ignore repeats. |

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

- Rename `OnlineLeaderboard` -> `OnlineLeaderboard`, `OnlineWallet` ->
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

**Where it runs (decided)**: the game's own Hetzner VM, apart from the user's
other application, running **k3s** as a one-node cluster managed with kubectl.
Everything is in the namespace `flapjaw`. k3s ships the **Traefik** ingress
controller; the one add-on is **cert-manager** with a Let's Encrypt
ClusterIssuer (HTTP-01). The API host stays a placeholder,
`api.<your-domain>`, until the user picks one.

Manifests (in the repo under `deploy/`, see 3b; every deploy goes through
`tools/deploy.ps1`, run by the user; no session deploys):

- Namespace `flapjaw`.
- Deployment `server`: the Rust server and verifier, 1 replica to start,
  readiness and liveness on `/v1/ping`.
- CronJob `godot-check`: headless Godot that re-checks runs the Rust check
  rejected, every 10 minutes, exiting at once when nothing waits.
- Service (ClusterIP) and Ingress: host `api.<your-domain>`, class `traefik`,
  annotation `cert-manager.io/cluster-issuer: letsencrypt`; the ClusterIssuer.
- Secret made by Kustomize's `secretGenerator` from a git-ignored
  `.env.<env>`. A checked-in `.env.example` lists every key (database password, token
  signing key, Daily Run secret, Firebase service account, backup bucket keys).
- StatefulSet `postgres`: Postgres 16, one pod, its volume on k3s local-path
  storage or a Hetzner volume.
- CronJob `backup`: nightly `pg_dump`, gzipped, to Hetzner Object Storage,
  14 days kept.
- NetworkPolicy: only the ingress reaches the server, only the server reaches
  Postgres.

**Postgres, not MySQL** (the other application's MySQL doesn't matter now the
game is apart): today's 18 migrations run as they are on Postgres (`jsonb` for
taps, loadouts and saves, `timestamptz ... at time zone 'Europe/Amsterdam'` for
the board day, partial indexes for pending runs and unclaimed prizes);
`tools/db_test.ps1` already runs on `postgres:16-alpine`; sqlx supports
Postgres best (compile-time checked queries, `jsonb` to `serde_json`). MySQL
would mean rewriting every table and query. **Decided**: Postgres inside
Kubernetes as a plain StatefulSet, one pod, tuned small for the 2 GB VM, with
a nightly `pg_dump` CronJob (where the dumps go is not decided yet, see
Backups). **Upgrade path at
4 GB**: CloudNativePG, an operator with built-in continuous backups to object
storage and point-in-time restore (failover once there is a second node); on
2 GB it would cost memory the VM doesn't have.

**Backups (recommended, not decided)**: object storage, because the copy lives off the VM
and survives losing the VM, its disk or the namespace. A Hetzner volume is
cheaper but sits next to the database; fine as a second, local copy.

Rough monthly cost (estimates, not quotes): the VM EUR 4 to 8 (2 GB by
default, 4 GB a little more), an optional volume about EUR 1, Object Storage
about EUR 5, a domain about EUR 1 (EUR 10 a year). Total about EUR 10 to 15.

**VM size (default 2 GB)**: fits with a memory limit on every pod, the Godot
check as an on-demand CronJob, Postgres tuned small and swap as a safety net.
4 GB is the comfortable option (staging beside prod, no tuning to watch); the
price gap is small. x86 types only (ARM needs arm64 builds of the server and
Godot). Estimates, measured in rollout step 3:

| On the VM | Steady | Limit | Notes |
|---|---|---|---|
| Linux, sshd, containerd | 180 MB | - | Ubuntu minimal |
| k3s server and kubelet | 550 MB | - | SQLite datastore, metrics-server off |
| CoreDNS, local-path | 50 MB | 170 MB | k3s defaults |
| Traefik | 70 MB | 128 MB | built into k3s |
| cert-manager (3 pods) | 90 MB | 160 MB | |
| Postgres 16 | 200 MB | 384 MB | `shared_buffers=128MB`, `max_connections=20`, `work_mem=4MB`, `maintenance_work_mem=64MB`, `effective_cache_size=512MB` |
| Rust API and verifier | 50 MB | 192 MB | pool of at most 10 connections |
| Godot check (CronJob) | 0 | 384 MB | about 250 MB only while running, every 10 min, exits when nothing waits |
| Backup (CronJob) | 0 | 128 MB | about 40 MB at night, timed away from the Godot check |
| **Total** | **about 1190 MB** | | peak about 1440 MB; about 600 MB left plus swap |

Swap: a 2 GB swap file from cloud-init, `vm.swappiness=10`, kubelet
`fail-swap-on=false`. Every container has a memory request and limit (the
deploy script refuses a manifest without). Staging on 2 GB runs only while
testing and is scaled to 0 after.

## 3b. Infrastructure as code

The VM and everything on it are described in the repo, so the game is always
deployed the same way and can be rebuilt from nothing.

```
repo (your PC)                                 Hetzner
  infra/hetzner  --tofu apply-->  Hetzner API --> VM + firewall + volume + DNS
  (OpenTofu + cloud-init)                          cloud-init: k3s + swap
  tofu state -------------------> Hetzner bucket
  tools/deploy.ps1 --1 build + push (tag = git sha)--> container registry
                   --2 kubectl apply -k deploy/overlays/prod--> k3s (pulls image)
                   --3 rollout status, 4 smoke test--> api.<domain>/v1/ping
  deploy/ (Kustomize) + server/ + .env.prod (git-ignored) feed the script
  k3s --nightly pg_dump--> Hetzner Object Storage
```

1. **The VM: OpenTofu** (`infra/hetzner/`, `hcloud` provider): the server
   (type, image, location), a firewall (80 and 443 open; SSH and the
   Kubernetes API only from the user's IP), the Postgres volume and the DNS
   record (Hetzner DNS, or wherever the domain lives). `cloud-init.yaml`
   installs k3s (metrics-server off, swap allowed) and makes the swap file; it
   holds no secrets. State in a Hetzner bucket (S3 backend), so losing the PC
   loses nothing; a local git-ignored state file also works.
2. **On the cluster: Kustomize** (`deploy/`): `base/` holds the namespace, the
   server Deployment, the Godot check and backup CronJobs, Service, Ingress,
   the Postgres StatefulSet, NetworkPolicy, and cert-manager (its release
   manifest at a pinned version) with the ClusterIssuer. `overlays/staging`
   and `overlays/prod` set namespace, host, sizes and image tag. Images are
   pinned to the git sha, never `latest`.
3. **One deploy script**, `tools/deploy.ps1 -Env prod`: refuse a dirty tree,
   build and push the image tagged with the git sha, set the tag in the
   overlay, run database migrations as a Job, `kubectl apply -k
   deploy/overlays/prod`, wait for `kubectl rollout status`, smoke test
   (`/v1/ping` answers that sha and the gameplay version). `-Rollback`
   redeploys the previous sha; `-Sha <sha>` deploys any earlier one.
   Migrations are forward only and work with the previous server version, so a
   rollback never undoes one.
4. **Secrets as env files**: `.env.staging` and `.env.prod`, git-ignored, made
   into Secrets by Kustomize's `secretGenerator` (a hash in the name, so a
   changed secret restarts its pods). `.env.example` lists every key.
5. **GitOps (Argo CD, Flux) later, not now**: for one VM and one person it
   costs a few hundred MB of the 2 GB and one more thing to upgrade; the script
   already makes every deploy the same. Worth it with more environments,
   people, or deploys from CI.

**Rebuilding from scratch if the VM dies**: (1) `tofu apply`, about 5 minutes,
then copy the kubeconfig; (2) `tools/deploy.ps1 -Env prod`, the same sha as
before, with a new Let's Encrypt certificate; (3) `tools/restore.ps1 -Env prod`
scales the server to 0, loads the newest dump from the bucket, scales back up;
(4) the smoke test and a board load. At most a day of runs is lost (since the
last dump). Rehearsed once on staging before the cutover.

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

## 5. Data (decided: fresh start, phones reset once)

No player data carries over. The new server starts empty, with its own Daily
Run secret. Nothing is copied from Supabase and no session reads its data.

**The one-time reset on the phones**: the new build's config names its server
(`server_id`); the save remembers the server it last used. On the first launch
where they differ, the phone resets once, before signing in (a crash halfway
runs it again next launch).

- Cleared: gold, owned and worn cosmetics, best scores, rooms reached, earn,
  streak and ladder state, cached diamonds and prizes, today's Daily Run state,
  `user://pending_runs.json`, the old session and device key (file and iOS
  Keychain), Your runs (`user://runs.json`).
- Kept: this phone's settings (music, sounds, haptics, reduced flashing,
  color-blind spikes, large buttons) and the leaderboard name.
- Shown once on Home: "Fresh start. Flapjaw has a new server, so scores,
  coins and items start over." with a Play button.

## 6. Rollout

No data to copy, no freeze. Supabase keeps running untouched until it is
switched off, so it is the rollback the whole way. No GitHub checker fallback.

1. **BackendClient interface, update prompt, one-time reset** (no server): a
   minimum-version answer the game shows as "please update" (today's builds
   have none) and the reset, switched off until the cutover build. Check
   passes. Rollback: revert the commits.
2. **Server skeleton, local**: auth with device key, `ping`, `submit_run`,
   `get_board`, `get_run`, `set_player`, the Rust checker. Contract fixtures
   pass against both the SQL (`tools/db_test.ps1`) and the new server.
3. **The rest, local**: Daily Run, wallet, prizes, earn status and ladder,
   profiles, push; `supabase/tests/*.sql` cases ported; the OpenTofu files,
   `deploy/` overlays and `tools/deploy.ps1`, checked with `tofu validate` and a
   server-side dry run; memory measured on a test VM.
4. **On the VM** (the user fills `.env.staging` and `.env.prod`, runs `tofu
   apply` and `tools/deploy.ps1`, with a step-by-step guide, and rehearses the
   rebuild once on staging): debug builds point at the new server, release
   builds stay on Supabase. Rollback: `tools/deploy.ps1 -Rollback`; `tofu
   destroy` removes it all.
5. **Cutover**: a release build on the new server with the reset on, forced
   update. Old builds keep talking to Supabase until it is switched off, so
   friends are told to update. Rollback: ship a build with the Supabase config.
6. **Retire, later**: the user pauses or deletes the Supabase project; a later
   change removes the Supabase client, migrations, Edge Functions and workflows,
   `verify-runs.yml` with them.

Then, as its own branch: **Move to a new phone** (`docs/ACCOUNT_TRANSFER.md`).

## 7. Decisions and open questions

Decided: Rust; fresh start with a one-time phone reset; the game's own Hetzner
VM with k3s, Traefik, cert-manager and Let's Encrypt; Postgres in
Kubernetes as a StatefulSet; Secrets from
git-ignored `.env.<env>` files; Kustomize with kubectl, all of it as code
(OpenTofu, Kustomize, one deploy script); a 2 GB VM by default; no GitHub checker fallback; the
Amsterdam midnight reset stays.

Open:

1. **Go-ahead**: may work start on rollout step 1, then the server?
2. **Backups**: is a Hetzner Object Storage bucket (about EUR 5 a month) fine
   for the nightly dumps? Recommended, not decided.
3. **The reset**: clear Your runs too, keep sound and accessibility settings
   and the name?
4. **Container registry**: GitHub Container Registry (free, public images like
   the repo, which holds no secrets), or a private registry?
5. **VM size**: 2 GB as planned, or 4 GB for staging beside prod?
6. **Host name**: which domain for the API (placeholder `api.<your-domain>`)?
7. **Move to a new phone**: approve the transfer-code-first plan
   (`docs/ACCOUNT_TRANSFER.md`)?

## What was built

Defaults for the open questions (each changes in one place): a 2 GB VM
(`server_type` in `infra/hetzner/variables.tf`), GitHub Container Registry
(`REGISTRY` in `deploy/.env.example`), backups to Hetzner Object Storage
(`BACKUP_S3_*`, any S3-compatible bucket), the API host as `API_HOST`, the
fresh start clearing Your runs and keeping settings and the name
(`BackendReset`), a 24-hour single-use transfer code (`transfer::VALID_HOURS`),
no Apple or Google sign-in.

- **Client** (`services/`): `BackendClient` with `SupabaseClient` (unchanged)
  and `FlapjawClient`, picked by `services/backend_config.json` (else the old
  `supabase_config.json`). `OnlineLeaderboard` and `OnlineWallet` are the
  renamed Supabase classes. 426 shows "Update Flapjaw", `account_moved`
  "Moved to another phone", the one-time reset "Fresh start" (`NoticePopup`,
  `BackendEvents`).
- **Server** (`backend/`, Rust, axum, sqlx). It keeps the game's rules where
  they were tested: it applies every Supabase migration as it is, behind
  small platform stand-ins (`backend/migrations/0001_platform.sql`: the roles,
  `auth.users`, `auth.uid()` from `request.jwt.claim.sub`, `net.http_post`
  only written down), and runs each SQL function as the signed-in player. So
  the plan's "port the SQL to typed handlers" became "call the same SQL from
  typed routes"; the answers are the same by construction. Around it: device
  key sign-in with hashed, rotating tokens (`auth.rs`), the replay check with
  the Rust sim and Godot confirming rejections (`verify.rs`,
  `deploy/godot-check/`), the FCM sender (`push.rs`), transfer codes with rate
  limits (`transfer.rs`, `limits.rs`) and `get_my_runs` for Your runs.
  Migrations run when the server starts (an advisory lock keeps it to one),
  not as a separate Job. Tests: `tools/backend_test.ps1` (unit, and with
  Docker integration tests against a throwaway Postgres), a step of
  `tools/check.ps1`.
- **Infrastructure** (`infra/hetzner/`, `deploy/`, `tools/deploy.ps1`,
  `tools/restore.ps1`): as in "Infrastructure as code" above, except DNS,
  which stays a manual record (the address is a `tofu output`), and staging,
  which shares the VM in its own namespace.
- **Move to a new phone** (docs/ACCOUNT_TRANSFER.md): Settings > Account.
  The moved player's synced settings come along with the save.

Checked on this PC, offline: `tofu validate` (OpenTofu 1.13, the hcloud
provider; `.terraform.lock.hcl` is checked in), both overlays with
`tools/deploy.ps1 -Check` and kubeconform (13 valid objects each), both images
built locally, and the pipeline in throwaway containers: the server migrated
a fresh Postgres, signed a player up, took an honest and a tampered run,
marked the honest one `ok` at once and queued the other; the godot-check image
then rejected it ("score mismatch"). Not done: anything at Hetzner, a push, a
real deploy.
