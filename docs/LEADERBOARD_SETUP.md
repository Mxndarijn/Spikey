# Leaderboards for friends (Supabase free plan)

The game shows three boards: **Today** (best run per player today, each run on
its own seed, resets at midnight Amsterdam time; its id is still `daily`),
**Daily Run** (best try per player on today's one map, see below) and
**All-time** (best run per player ever). They live in a free Supabase project.
Nothing here costs money and no card is needed.

Without the config file below, the game shows made-up sample boards instead.

Runs are **verified**: a GitHub job replays every new run with the game's own
code and only runs that match their score show on the boards (see
"Verification" below).

## One-time setup (about 10 minutes)

1. Create a free account at <https://supabase.com> and a new project. Pick a
   region close to you (for example Frankfurt) and any database password.
2. **Turn on anonymous sign-ins**: Authentication -> Sign In / Providers ->
   "Allow anonymous sign-ins" on. Each phone becomes a player without typing
   an email or password.
3. **Create the tables** (automatic): the GitHub workflow
   `.github/workflows/supabase-db.yml` applies everything in
   `supabase/migrations/` whenever that folder changes on `main` (or run it by
   hand: Actions -> Supabase database -> Run workflow). It needs one GitHub
   secret, `SUPABASE_DB_URL`:
   - In Supabase press **Connect** (top of the project page) and copy the
     **Session pooler** connection string, the one with
     `pooler.supabase.com:5432`. Not "Direct connection": GitHub's machines have
     no IPv6 and can't reach it.
   - Replace `[YOUR-PASSWORD]` with the database password, **percent-encoded**:
     `@` -> `%40`, `:` -> `%3A`, `/` -> `%2F`, `#` -> `%23`, `?` -> `%3F`,
     `%` -> `%25`, space -> `%20`. Letters and digits stay as they are.
   - Add it in GitHub: Settings -> Secrets and variables -> Actions -> New
     repository secret, name `SUPABASE_DB_URL`.

   Instead of the URL you can set `SUPABASE_ACCESS_TOKEN` (Account -> Access
   Tokens), `SUPABASE_PROJECT_REF` (the id in the project URL) and
   `SUPABASE_DB_PASSWORD` (no encoding needed). Or paste the migration file
   into the SQL Editor by hand; running it twice is safe.
   Both daily boards (Today and Daily Run) reset on one clock,
   `spikey_board_zone()` in `20261113130000_daily_run.sql` (`Europe/Amsterdam`).
   To move it, replace that one function in a new migration. Later database
   changes go in a new file in `supabase/migrations/`; never edit one that
   already ran.
4. **Copy the address and the public key**: Project Settings -> API (or
   "Data API" / "API Keys"). You need the Project URL and the public
   `anon` key (newer projects call it the "publishable" key). Never use the
   `service_role` / secret key in the game.
5. **For builds on your PC**: copy `services/supabase_config.example.json` to
   `services/supabase_config.json` and fill in both values. This file is in
   `.gitignore`, so it stays on your machine.
6. **For the GitHub phone builds** (the APK on Discord and TestFlight): in the
   GitHub repository go to Settings -> Secrets and variables -> Actions ->
   New repository secret, and add `SUPABASE_URL` and `SUPABASE_ANON_KEY` with
   the same two values. The Android and iOS workflows write the config file
   from them; without them a build shows sample boards.

The public key is meant to ship inside apps, so it being readable in the APK is
expected. The database only lets the game call the functions in `supabase/migrations/`.

## Keeping it awake

A free project pauses after 7 days with no requests. With the two GitHub
secrets set, `.github/workflows/supabase-keepalive.yml` pings it twice a week.
If it pauses anyway, open the project in the Supabase dashboard and press
Restore; scores are kept.

## How it works

- `services/supabase_leaderboard.gd` signs the phone in anonymously once and
  keeps the session in `user://supabase_session.json`.
- **Same player after a reinstall.** Each player also gets a device key: 32
  random bytes in `user://device_key.json`. The Edge Function
  `supabase/functions/device-key` turns it into the password of an address only
  that player has (`<player id>@device.flapjaw.invalid`, which never gets
  mail). The refresh token changes every hour, so the one in a phone backup is
  usually dead; the key never changes. On Android, Auto Backup is on
  (`user_data_backup/allow` in `export_presets.cfg`) and restores user:// on a
  reinstall or a new phone with the same Google account, so the game signs in
  with the key and is the same player. Order: refresh token, then the key, and
  only if the server says both are no good a new player. No answer at all
  (offline) never makes a new player. iOS deletes app files with the app, so
  there the key is also kept in the Keychain, which survives an uninstall (and
  moves to a new iPhone with an encrypted backup): a generic password, service
  `flapjaw`, account `device_key`, readable after the first unlock. The game
  reads the file first and the Keychain when the file is gone, and puts back
  whichever copy is missing. The Keychain code is an engine module
  (`tools/engine/modules/flapjaw_keychain`, singleton `FlapjawKeychain`) built
  into the small iOS engine (`.github/workflows/engine.yml`), so only release
  builds from CI have it; a build with Godot's stock template keeps the key in
  the file only.
  The function is deployed by `.github/workflows/supabase-functions.yml`, which
  needs the GitHub secrets `SUPABASE_ACCESS_TOKEN` and `SUPABASE_PROJECT_REF`.
  Until it is deployed, phones play on as anonymous players and try again at
  the next sign-in.
- **The save on the server.** `services/profile_sync.gd` sends the save
  (owned and worn items, gold, best score, rooms, settings; not diamonds or
  this phone's own switches, see `Profile.LOCAL_KEYS`) to `sync_profile` after
  it changed, and once at start. The server keeps it only when it was based on
  the newest copy. Otherwise it sends the newest copy back and the game merges
  the two (`Profile.merge_cloud`): items, rooms and best scores join, gold is
  the server's plus what this phone earned or spent since, and a phone that
  never synced (a reinstall) takes the old look and settings back.
- **Premium items count only when the server sold them**
  (`supabase/migrations/20261110160000_paid_items.sql`). Gold and owned items
  live in the save, which a player could edit. What other players see comes
  from the server, though: a run's loadout and the flyer on the boards keep a
  premium item (one with a diamond price) only when `diamond_ledger` shows it
  was bought with diamonds; otherwise the default look shows. Every
  `sync_profile` answer lists the bought items and the game grants them, so
  they come back on a reinstall. The list of premium items is the table
  `premium_items`; a new premium item needs a migration that adds it
  (`tests/unit/test_paid_items.gd` fails until it does).
- **Gold is checked, not enforced.** On every save the server compares the
  gold with the most the player could have earned (gold of runs that weren't
  rejected, plus diamonds turned into gold) and keeps how far it goes over in
  `profiles.gold_excess`. Nothing is capped: runs sent before runs carried
  gold, or still waiting on a phone, can make an honest save go over. To look:
  `select player_id, gold_excess from profiles where gold_excess > 0;`.
- After every real run (never practice) it sends the score, coins, season, seed and taps to
  `submit_run`. If the phone is offline, runs wait in `user://pending_runs.json`
  and go out with the next run or board load. A run played offline still counts
  for the day it was played if it is sent within two days.
- The leaderboard name (asked the first time you open Leaderboards) is sent with
  every run and when you change it.

## Verification

`.github/workflows/verify-runs.yml` starts when a run arrives (see "Checking
right away" below) and every 10 minutes as a safety net. It fetches runs that
wait to be checked, replays them headless with `server/verify_batch.gd`, and
marks each one:

- `ok`: the replay gives the same score, coins and end tick. Shown to everyone.
- `rejected`: it doesn't (a fake or broken run). Never shown; `reason` says why.
- `outdated`: played on an older gameplay version than `main`. Never shown.
- `pending`: not checked yet. Shown only to the player who sent it.

It uses the same `SUPABASE_DB_URL` secret as the database workflow; nothing else
to set up. The repository is public, so its runs are free. GitHub sometimes
starts scheduled runs late, and turns the schedule off after 60 days without a
commit: turn it back on under Actions -> Verify leaderboard runs. You can also
start it by hand there.

After a gameplay change (a new `GAMEPLAY_VERSION` on `main`), runs from phones
on the older app become `outdated` until those phones update.

### Checking right away

On the schedule alone a new score can take 10 to 30 minutes to show for other
players. With one more secret the database starts the checker the moment a run
arrives (`supabase/migrations/20261109210000_wake_checker.sql`), and a score
shows after about two minutes:

1. GitHub -> your profile picture -> Settings -> Developer settings -> Personal
   access tokens -> **Fine-grained tokens** -> Generate new token.
   Repository access: only this repository. Permissions: **Actions: Read and
   write**, nothing else. Pick the longest expiry you are comfortable with.
2. Add it to the repository as the secret `VERIFY_DISPATCH_TOKEN` (Settings ->
   Secrets and variables -> Actions).
3. Start the checker once by hand (Actions -> Verify leaderboard runs -> Run
   workflow). Each time it runs it stores the token in the database (table
   `worker_settings`, which the game can't read).

When the token expires the boards keep working on the schedule; make a new
token and replace the secret. To turn the wake-up off, delete the secret.

## Looking at the data

Table Editor -> `players` and `runs` (`status` and `reason` show what the
checker decided). To remove a player and their runs, delete
their row in `players`.

To start the boards over, run `select public.spikey_reset_boards();` in the SQL
Editor (version 23 did this once, `20261113120000_reset_boards.sql`). It deletes
every run, so both boards are empty, but first settles finished days and writes
earned milestones and streak diamonds, and keeps what other rules read from old
runs: each player's best checked score and gold earned (`run_carry`, for the Earn
screen and `gold_excess`) and the days they played (`played_days`, for streaks).
Wallets, prizes and saves are not touched. Don't use `truncate public.runs`: it
skips all of that, so streaks break and honest saves look like too much gold.

## Daily Run

One map a day, the same for every player (`20261113130000_daily_run.sql`,
client: `meta/daily_run_rules.gd`, `game/app/daily_run_flow.gd`).

- **The map**: the first call of a day makes its `daily_runs` row: the day's
  number (No. 1 is 2026-11-14), a seed from md5(server secret + day) and the
  day's season (`spikey_season_of`, the same calendar as `SeasonCalendar`). The
  secret lives in `daily_run_secret` and never leaves the database, so nobody
  can play tomorrow's map early. The seed comes only with a try.
- **Tries**: `start_daily_try` hands out tries 1 to 3 (`spikey_daily_run_tries`,
  `DailyRunRules.TRIES_PER_DAY`); a try counts once it started. The run goes
  back with `submit_daily_run` (once per try; the day's seed and season or it is
  refused; no revives) and is checked by the same checker as any run. It counts
  for the day the try started, even when it arrives after midnight.
- **The board**: `get_board('daily_run')`, best try per player today. Other
  players' replays stay locked until the day is over (`locked` rows, `get_run`).
  Today and All-time show endless runs only. Daily Run runs still count, like
  any checked run, for the best-score milestones, the 7-day streak and the gold
  ceiling.
- **Prizes**: the top 10 of a finished day win `spikey_daily_run_prize` (the
  same tiers as Today: 3, 2, 2, then 1; `Economy.DAILY_RUN_PRIZES` holds the
  same table). With both boards the game pays 28 diamonds a day. They are paid
  the same lazy way as Today's (`spikey_settle_days`, inside `get_wallet`,
  `claim_prizes` and `get_earn_status`), show in the wallet with
  `"board": "daily_run"` and are claimed with the rest (ledger reason
  `daily_run_prize`).

Database tests: `supabase/tests/80_test_daily_run.sql` (`tools/db_test.ps1`,
needs Docker).
