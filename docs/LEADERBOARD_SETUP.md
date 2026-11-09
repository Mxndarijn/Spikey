# Leaderboards for friends (Supabase free plan)

The game shows two boards: **Daily** (best run per player today, resets at
midnight Amsterdam time) and **All-time** (best run per player ever). They live
in a free Supabase project. Nothing here costs money and no card is needed.

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
   To use another time zone for the daily reset, replace `Europe/Amsterdam`
   in the migration before it is applied (three places). Later database changes
   go in a new file in `supabase/migrations/`; never edit one that already ran.
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
- After every real run (never practice) it sends the score, coins, season, seed and taps to
  `submit_run`. If the phone is offline, runs wait in `user://pending_runs.json`
  and go out with the next run or board load. A run played offline still counts
  for the day it was played if it is sent within two days.
- The leaderboard name (asked the first time you open Leaderboards) is sent with
  every run and when you change it.

## Verification

`.github/workflows/verify-runs.yml` runs every 10 minutes. It fetches runs that
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

## Looking at the data

Table Editor -> `players` and `runs` (`status` and `reason` show what the
checker decided). To remove a player and their runs, delete
their row in `players`. To start the boards over, run `truncate public.runs;`
in the SQL Editor.
