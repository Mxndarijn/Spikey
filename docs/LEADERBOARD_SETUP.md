# Leaderboards for friends

The game shows three boards: **Today** (best run per player today, each run on
its own seed, resets at midnight Amsterdam time; its id is still `daily`),
**Daily Run** (best try per player on today's one map, see below) and
**All-time** (best run per player ever). They live on our own game server
(`backend/`, set up and deployed with docs/DEPLOY.md). Builds made without the
server config (`services/backend_config.json`, written by the phone builds from
the `FLAPJAW_API_URL` and `FLAPJAW_SERVER_ID` secrets) show made-up sample
boards instead.

Runs are **verified**: the server replays every new run with the game's own
rules and only runs that match their score show on the boards (see
"Verification" below).

The boards, wallet, prizes and saves are SQL functions in `backend/migrations/`
(written for Supabase before the server existed, and kept as they are). Both
daily boards (Today and Daily Run) reset on one clock, `spikey_board_zone()` in
`20261113130000_daily_run.sql` (`Europe/Amsterdam`). To move it, replace that
one function in a new migration. Later database changes go in a new file in
`backend/migrations/` (and in `MIGRATIONS` in `backend/src/db.rs`); never edit
one that already ran: the server remembers applied migrations by file name.

## How it works

- `services/flapjaw_client.gd` signs the phone in as a new player once and
  keeps the session in `user://flapjaw_session.json`.
- **Same player after a reinstall.** Each player also gets a device key: 32
  random bytes in `user://flapjaw_device.json`, which the server keeps only as
  a hash (`POST /v1/auth/device` signs in with it). The refresh token changes every hour, so the one in a phone backup is
  usually dead; the key never changes. On Android, Auto Backup is on
  (`user_data_backup/allow` in `export_presets.cfg`) and restores user:// on a
  reinstall or a new phone with the same Google account, so the game signs in
  with the key and is the same player. Order: refresh token, then the key, and
  only if the server says both are no good a new player. No answer at all
  (offline) never makes a new player. iOS deletes app files with the app, so
  there the key is also kept in the Keychain, which survives an uninstall (and
  moves to a new iPhone with an encrypted backup): a generic password, service
  `flapjaw`, account `flapjaw_device`, readable after the first unlock. The game
  reads the file first and the Keychain when the file is gone, and puts back
  whichever copy is missing. The Keychain code is an engine module
  (`tools/engine/modules/flapjaw_keychain`, singleton `FlapjawKeychain`) built
  into the small iOS engine (`.github/workflows/engine.yml`), so only release
  builds from CI have it; a build with Godot's stock template keeps the key in
  the file only.
- **The save on the server.** `services/profile_sync.gd` sends the save
  (owned and worn items, gold, best score, rooms, settings; not diamonds or
  this phone's own switches, see `Profile.LOCAL_KEYS`) to `sync_profile` after
  it changed, and once at start. The server keeps it only when it was based on
  the newest copy. Otherwise it sends the newest copy back and the game merges
  the two (`Profile.merge_cloud`): items, rooms and best scores join, gold is
  the server's plus what this phone earned or spent since, and a phone that
  never synced (a reinstall) takes the old look and settings back.
- **Premium items count only when the server sold them**
  (`backend/migrations/20261110160000_paid_items.sql`). Gold and owned items
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

The server replays every run the moment it arrives with the Rust copy of the
sim (`backend/src/verify.rs`, `tools/fastsim-rs/sim`, held tick for tick to
`sim/`) and marks it:

- `ok`: the replay gives the same score, coins and end tick. Shown to everyone.
- `rejected`: it doesn't (a fake or broken run). Never shown; `reason` says why.
- `outdated`: played on an older gameplay version than the server's. Never shown.
- `pending`: not checked yet. Shown only to the player who sent it.

A run the Rust check would reject stays `pending` until headless Godot has the
last word: the godot-check CronJob (`deploy/godot-check/`, every 10 minutes)
replays it with `server/verify_batch.gd`, the GDScript sim itself. So a
difference between the two sims can never hide an honest score. Runs from a
newer gameplay version than the server's stay pending until it is deployed
with that sim.

After a gameplay change (a new `GAMEPLAY_VERSION`, deployed), runs from phones
on the older app become `outdated` until those phones update.

## Looking at the data

In the server's database (`kubectl -n flapjaw exec -it postgres-0 -- psql -U
flapjaw`, docs/DEPLOY.md): the tables `players` and `runs` (`status` and
`reason` show what the checker decided). To remove a player and their runs,
delete their row in `players`.

To start the boards over, run `select public.spikey_reset_boards();` there
(version 23 did this once, `20261113120000_reset_boards.sql`). It deletes
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

Database tests: `backend/sql_tests/80_test_daily_run.sql` (`tools/db_test.ps1`,
needs Docker).

## Score ladder

Past the four best-score milestones (25, 50, 75, 100), every 50 points from 150
to 1000 wins 3 diamonds once (`20261114120000_score_ladder.sql`, client:
`EarnRules.LADDER_*`): 18 steps, 54 diamonds at most. They are `bonus_prizes`
rows of kind `milestone` like the first four (ref `"150"`), written by
`spikey_award_bonuses` from the best checked score, so one run passing several
steps pays each. No back-pay: when the file was applied, `spikey_mark_ladder`
stored every player's best checked score in `ladder_marks`, and steps at or
below a player's mark never pay (players who came later start at 0).
`get_earn_status` sends the mark as `ladder_mark`.
