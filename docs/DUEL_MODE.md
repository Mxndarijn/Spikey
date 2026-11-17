# Game modes, Battle and Duel (plan)

Status: **plan only, waiting on the user's answers** (open questions at the
end). No game or server code is written, and nothing in `sim/` changes.
Visual version with the mockups and diagrams:
<https://claude.ai/artifact/9cnM2DPqVKpwRShzaFRq4j> (source:
`docs/mockups/duel_mode.html`). This file is the text copy; keep both in step.

Builds on the live server: the Rust axum server in `backend/` with Postgres
on the k3s VM (`https://flapjaw.mn-platform.tech`, merged in
`next-features-4`, shipped with v0.1.2). Its operations are Postgres functions
behind `POST /v1/<op>` (listed in `backend/src/rpc.rs`), runs are checked by the
Rust sim with headless Godot confirming rejections, and push alerts go out
through its FCM sender (`backend/src/push.rs`, an outbox the database fills).

## Built so far

- **Mode picker** (Home's carousel and the All modes sheet): `game/app/game_modes.gd`,
  `game/ui/widgets/mode_carousel.gd`, `modes_sheet.gd`. Battle and Duel show as Soon.
- **Battle on the server**: `backend/migrations/0110_battles.sql` (tables, the
  battle_* operations, rounds decided by a trigger after the replay check, the
  copied-taps check, the battle alert outbox on the `battles` channel, nudges),
  tests in `backend/tests/battles.rs`.
- **Wins boards on the server**: `0111_wins_boards.sql` (`match_results`, the
  counting rules, `get_wins_board`, `get_match_record`), `backend/tests/wins.rs`.
- **Battle bots**: `0112_battle_bots.sql` (bot players, the bot wait in
  `worker_settings.bot_wait_s`, `worker_set_bot_wait`, levels learned per
  player), the worker `backend/src/bot.rs` + `src/bin/battle_bot.rs`, the run
  from `fastsim-rs battlebot` (`tools/fastsim-rs/fastsim/src/human/battle_bot.rs`,
  8 levels), the image `backend/Dockerfile.bot`, the pod
  `deploy/base/app/battle-bot.yaml` (500m CPU, 128 Mi). Not deployed.
- **Battle in the game**: `services/battle_service.gd` + `battle_view.gd`,
  `meta/match_rules.gd`, `game/app/battle_flow.gd` (the list, New battle, one
  battle, its menu, a round's run and sending it), the screens
  `battle_list_screen.gd` (B1), `battle_screen.gd` (B3, B4, B6, B7, K1),
  `new_battle_sheet.gd` (B2), `battle_menu_sheet.gd` (K2), the rival's bird
  `game/match/rival_ghost.gd` (B5), the Battle card on Home is live with its
  your-turn badge. Tests: `test_battle_service.gd`, `test_battle_screens.gd`
  (with a whole round in the app), `test_battle_fit.gd`.
- **Wins boards in the game**: the Scores | Wins switch on the leaderboards
  (`board_switch.gd`), `wins_screen.gd` (L1, and L2 as the record card).

- **Duel on the server**: `backend/src/duel.rs` (the rules: both Rust sims,
  S + 1, coins, sudden death, the 4-minute cap, 3 s to the first tap, the
  clock check) and `duel_ws.rs` (`GET /v1/duel/ws`: invite codes, the random
  queue by version, the match task, rejoin, 30 s away forfeits, leave,
  rematch), `0113_duel.sql` (results on the Duel wins board). JSON text
  messages, about 100 bytes each, instead of the binary batches planned.
  Tests: `src/duel.rs`, `backend/tests/duel.rs` (a real socket).
- **Duel in the game**: `services/duel_link.gd` (the socket),
  `game/app/duel_flow.gd`, `game/ui/screens/duel_screen.gd` (D1, D2, D4, D5),
  the live rival (`RivalGhost.live_on`: a jitter buffer of 100 to 500 ms,
  holding at the last tick the rival confirmed instead of guessing), the Duel
  card on Home, the Duel tab of the wins boards. Tests: `test_duel.gd`.
- **Bot levels calibrated**: `docs/BATTLE_BOT_CALIBRATION.md`.
- **Only the newest version** (the user's rule): Battle and Duel run only on
  the server's gameplay version, so the server never needs an old sim. The app
  reads the server's version from `POST /v1/ping`; an older app shows "Update
  to play" on the Battle and Duel cards (Home, All modes, the Battle and Duel
  screens) and Play opens the store (`game/app/store_link.gd`). The server
  answers battle operations from an older app (header X-Flapjaw-Gameplay) and
  the Duel hello with `update_required` (409). Classic and the Daily Run go on.
  When the server starts on a newer version, every round not decided yet that
  was dealt on an older one starts over: same round, new seed, its runs
  dropped (also with only one player's run), from its opener; decided rounds
  and the score stay; both players hear "New game version: round N starts
  over" (`0115_versions.sql`, `spikey_battle_redeal_old`, called at start).

Not built yet: pausing in a Duel (a paused phone falls behind and is down after
5 s), the invite link opening the app (Android App Links, iOS
Universal Links and the files the server hosts for them), a push opening its
battle, the Android notification channels created on the phone (alerts use
the default channel until then), and Duel.

Changed while building (to agree with the user):
- **No 4-minute cap on Battle runs**: a run flies to its crash, like a Daily Run.
  The replay check plays a run to its end, so a cap needs its own rule in the
  check; left for later if long rounds turn out to be a problem.
- The 8 bot levels are set from the measured tiers but not yet calibrated one
  by one (`fastsim-rs human measure` per level): a CPU run for later.
- The alt-account rule checks the account's age and checked runs; the shared
  IP rule is not built (the server keeps no IPs per match yet).
- The hidden rating is, for now, the bot level per player (from their scores,
  then learned from bot battles); a full rating for random pairing comes with
  more players.

## The idea

Two head-to-head modes on one shared base:

- **Battle** (async, built first): you and a friend or a random player take
  turns. Each round is a seed. One plays it and submits; the other plays the
  same seed with that run drawn as a see-through rival bird, and submits.
  Then the next round. Nobody has to be online at the same time.
- **Duel** (realtime, later): best of three, both flying the same
  seed at the same moment, each seeing the other live.

Both rest on one fact: a run is fully described by
`(gameplay_version, seed, tap ticks)`. A rival is a second `GameSim` fed with
the rival's taps: from a finished, checked run in Battle, from a live stream in
Duel.

## 0. The mode picker

Modes now and soon: **Classic** (today's endless run), **Daily Run**,
**Battle**, **Duel**, and later perhaps Practice or seasonal events.

**Decided**: a **mode carousel on Home**, with Play under it.

- One card per mode, swiped sideways, the chosen one in the middle and its
  neighbours peeking in at the sides. Dots under it show how many modes there
  are.
- A card: the mode's icon, its name, its rules in one line ("Endless. One
  life.", "One map a day · 3 tries", "Take turns · first to 6", "Live 1v1 ·
  best of 3") and a badge.
- Badges: Battle shows a count of battles where it is your turn (ink circle
  with the number), Daily Run "2 tries left" or a tick when done, a new mode
  "NEW" for its first week.
- The big Play button names the mode: "Play", "Play Daily Run", "Battles"
  (opens the battle list), "Find a Duel".
- The mode last played stays chosen at the next launch. Classic is first and
  the default.
- An **All modes** link under the dots opens a sheet with every mode as a
  2-column grid, for when there are more than four or five.

**Easy to add modes**: a `GameMode` list in `game/app/game_modes.gd`, one entry
per mode:

```
id            "battle"
title         "Battle"
rule_line     "Take turns · first to 6"
icon          res://assets/icons/mode_battle.svg
play_label    "Battles"
badge()       -> {text, kind}   # read from services (BattleService, DailyRunInfo)
open(main)    -> starts the mode's flow (BattleFlow, DailyRunFlow, ...)
visible()     -> false hides it (server switch, platform, season)
```

Home draws the carousel from the list; a new mode is one entry and its flow.
The server can hide a mode with a flag in the `ping` answer
(`modes_off: ["duel"]`), so a mode can be turned off without an update.

Alternatives looked at: tabs along the top (fine for 3, crowded at 5 and
hard to read on a small phone), a list sheet only (one more tap for the most
played mode).

## 1. Shared match rules (Battle and Duel)

| Rule | Recommendation | Why |
|---|---|---|
| Format | **Battle: first to 6 round wins** (best of 11, a long match). **Duel: best of three**, first to two. | Battle has days to play out; a live Duel must fit one sitting. |
| Map | A new server seed each round, handed out only when the round's first run starts. Both players get the same seed and season. | Nobody can practise the map. |
| Round winner | Higher score. Equal score: more coins. Still equal: in Duel a sudden-death round, in Battle a drawn round (no point to anyone). | Coins are a risk to take. |
| Time limit | 4 minutes a run (about 170 points). The run ends there, scored as it stands. | Keeps runs short and equal. |
| Revives | Off. | Nothing to buy changes a result. |
| Fork rooms | Allowed to split. Calm and Wild lead into the same next room, so only that room differs, and the map is the same again after it. The rival shows a small WILD tag there. | Fork-free seeds don't exist (a fork every 50 points); keeping both on one exit would be a sim rule change. |
| Rival a room apart | Drawn only in the same room index, else an edge tag "Mira · room 7". | Bumpers and boss holds can put them out of step. |
| Bird-following hazards | Only your own are drawn; a rival crash shows a puff. | Stalker, Dart aim and Echo follow each bird. |
| Coins and gold | Coins go to gold as in any checked run. Nothing for winning, no diamonds, no stakes or wagers ever. | Cosmetic-only monetization. |
| Boards | Battle and Duel runs don't count on Today, Daily Run or All-time. | The second player sees the first one's run. |
| Looks | **Decided**: the rival in their own skin (flyer, hat and trail), slightly see-through (about 60%), with a name tag. No new colour token. One hitbox for all. | |
| Version | A round is played by both on one `GAMEPLAY_VERSION`. | Same inputs, same run only on one sim. |

No sim change, no gameplay-version bump, no new goldens.

## 2. Battle (async)

### Match length (decided: a long match, "best of 10 or something")

| Option | Rounds | For | Against |
|---|---|---|---|
| **First to 6 round wins** (decided) | 6 to 11 | Ends the moment it is decided, so no dead rounds: a 6-1 is over after 7. At 5-5 one decider settles it. | The length varies (6 to 11 rounds). |
| 10 rounds, then a tie-break | 10, or 11 at 5-5 | Always the same length; a clear "round 7 of 10". | Rounds still get played when it is decided (7-1 after 8): the trailing player has every reason to stop replying. |

**Recommendation: first to 6** (best of 11). Drawn rounds (same score and
coins) give no one a point; after 13 rounds the one with more wins takes it, a
level count is a draw. Duel stays best of three: ten live rounds would be
40 minutes in one sitting.

### How a battle goes

Turns ping-pong, and each turn after the first answers one round and opens
the next, so the game moves on every turn:

| Turn | Who | Plays |
|---|---|---|
| 1 | A (started the battle) | Round 1, first |
| 2 | B | Round 1 with A's run as the rival, then Round 2, first |
| 3 | A | Round 2 with B's run, then Round 3, first |
| ... | | A opens the odd rounds, B the even ones |
| 11 | A | Round 10 with B's run, then Round 11 at 5-5, **blind** |
| 12 | B | Round 11, **blind** |

A turn is two runs (answer, then open) except the first and the last; after
the answer the round result shows, then "Next: round 4, you go first". A
turn is about 5 minutes of play. At most 12 turns, 6 each.

### Who goes first, and the ghost

The second player of a round sees the first player's run while they play:
the target score and the path. That is the fun of it (the user's "you see him
playing while you play"), and also an edge.

| Option | Fair | Fun |
|---|---|---|
| **A. The starter opens round 1, then alternate; round 11 blind** (decided) | Over rounds 1 to 10 each player gets the ghost five times. Round 11 (only at 5-5): the second player sees no run until they submit. | A ghost race every round but the decider. |
| B. Alternate, the ghost in every round | One player has the ghost in round 11, the round that decides it | Most ghost racing |
| C. Always blind, ghosts after | Fully fair | Loses watching the rival while you fly |

A battle that ends before round 10 can be uneven by one ghost round (A opened
one round more); first to 6 makes that one round of at least six, which is
small. In a rematch the player who asks for it is the starter and opens round 1.

### How long a battle takes (decided: no timers)

| Pace | Turns a day | A full 12-turn battle |
|---|---|---|
| Both playing now and then through the day (answer within about 2 h) | 6 to 8 | 1.5 to 2 days |
| Each plays once or twice a day | 2 to 4 | 3 to 6 days |
| One player comes back only now and then | | weeks, or never |

No turn deadline and no match cap: a battle waits as long as it takes. What
keeps that workable:

| Setting | Decided / recommended |
|---|---|
| Open battles at once | **20 per player** (decided), of which at most **5 random ones** waiting for an opponent. |
| Reminders | "Your turn" at once, a nudge after 1 day and after 3 days without a move, then no more. The other player may tap **Nudge** once a day. |
| **Resign** | Any time, in the battle's menu (confirm: "Resign? Mira wins this battle"). The other player wins. Counts under rule 12: before round 3 for nobody; from round 3 on a win for them and a loss for you. |
| **Close (no result)** | When it has been the other player's turn for **7 days** or more, you can close the battle: it ends for both with no result (not counted for either), frees your slot, and the other player sees "Ada closed this battle after 7 days without a move". Against a bot: any time. |
| A random battle with no opponent | A bot takes it (bot phase, below); later a person, when one comes. |
| Finished battles | Kept 30 days in the list, then only in your record. |
| Rematch | One tap at the result; the other gets a rematch turn, the starter opens round 1. |

The 7 days for Close is not a deadline: nothing happens on its own. It only
stops one player from ending a battle the moment the other is slow.

### Starting a battle

- **Friend**: an invite code (6 letters, no look-alikes, like the transfer
  code) and a link `https://flapjaw.mn-platform.tech/battle/KD7WQ3` that opens
  the app (Android App Links, iOS Universal Links; without the app the page
  says how to get it). The code lasts 7 days and is used once. The starter plays
  round 1 at once, so the friend finds a run waiting.
- **Random**: you play round 1 at once; your battle goes into a pool. Someone
  starting a random battle is first matched to a waiting battle (same gameplay
  version, closest hidden Battle rating, never yourself or a battle you just
  had with that player), and only opens a new one when none is waiting. So
  nobody waits to play; the second player gets the first player's round 1 with
  the ghost.
- **Friends list**: later, with stable accounts.

### One try per run

The seed comes from the server only when the run starts (`battle_start_run`),
like a Daily Run try: a started run counts. Closing the app or losing the
phone mid-run does not give a new try. The run's taps are saved locally as it goes (as Your runs
does at the end), so a run whose sending failed is sent later, and an app
killed mid-run sends what it had up to that tick, which the server scores as
a crash there. A run that never arrives (the phone is gone) scores 0 at the
player's next action in that battle, or when the battle is resigned or
closed.

Pause works as in Classic (with its resume countdown); there is no one to
wait for.

### After an app update

A round is pinned to the gameplay version its first run was played on. If
the second player is on a newer version (the old app is refused with 426),
the open round is dealt again on the new version for both: a new seed, the
first player plays it again, with no turn lost. Rounds already finished stand.

### Notifications

Through the server's FCM sender, as a new kind in its outbox, on its own
Android channel `battles` (so a player can mute battles but keep board
alerts), and only when push is on.

| When | Text |
|---|---|
| Your turn | "Mira scored 27 in round 2. Your turn!" |
| A random opponent answered your round 1 | "Jun answered your battle. Your turn!" |
| No move for 1 day, and for 3 days | "Mira is waiting for round 5" |
| Nudged | "Mira nudged you: round 5 is yours" |
| Resigned or closed | "Mira resigned. You win the battle" |
| Match over | "You beat Mira 6-4" or "Mira won 6-4. Rematch?" |
| Rematch asked | "Mira wants a rematch" |

- Quiet hours: no reminder between 22:00 and 08:00 on the phone's clock
  (`push_devices.utc_offset`); it is sent at 08:00 instead.
- At most one reminder an hour per player for all battles together.
- A push opens the app on that battle. A badge on the Battle card on Home
  shows the count of your turns.

### Server

Same pattern as everything else on the live server: Postgres functions behind
`POST /v1/<op>`, one migration, listed in `backend/src/rpc.rs`.

| Op | Does |
|---|---|
| `battle_create(opponent: "invite" \| "random")` | A battle with A; for random, matches to a waiting battle when there is one. Returns the battle and, for invite, the code. |
| `battle_join(code)` | B joins an invite battle. |
| `battle_list()` | Your battles: your turn, their turn, finished (last 30 days), with scores, days since the last move and the opponent's name, look and Bot badge. |
| `battle_get(battle)` | One battle, its rounds, and the rival's run for the round you answer (taps, only once checked `ok`; never in a blind decider before you submit). |
| `battle_start_run(battle, round)` | Checks the turn, hands out the seed and season, records the start. |
| `battle_submit(battle, round, taps, score, coins, end_tick, client_run_id)` | Stores the run (the same `runs` table with `mode = 'battle'`, so the checker handles it), idempotent on `client_run_id`. Answers at once with the round result once the Rust check passes (well under a second). |
| `battle_resign(battle)` | Gives up: the other wins (rule 12 decides whether it counts). |
| `battle_close(battle)` | Ends with no result, allowed after 7 days waiting on the other player (any time against a bot). |
| `battle_nudge(battle)` | Once a day, a push to the player whose turn it is. |
| `battle_rematch(battle)` | A new battle with the same two players; the one who asks opens round 1. |

Tables: `battles` (id, mode, player_a, player_b, first_to, wins_a, wins_b, status, invite_code
hash, random, bot_level, gameplay_version, turn_player, last_move_at,
created_at, finished_at, ended_by, winner) and `battle_rounds` (battle,
number, seed, season, first_player, blind, run_a, run_b, winner). The
`mode` column lets Duel reuse both tables.

**Reminders**: a background task in the server process, like its checker and
push loops (`spawn_checker`, `spawn_push`), every few minutes: the 1-day and
3-day nudges go into the push outbox, and random battles waiting past the bot
wait get a bot turn queued. It locks rows with `FOR UPDATE SKIP LOCKED`, so a
second replica later never handles a battle twice. No deadlines, no CronJob.

**Anti-cheat**: every battle run is checked by the Rust sim like a board run,
with headless Godot confirming a rejection; a round's result only counts on
`ok` runs, and the rival only sees a checked run. On top:
- The seed is only known after `battle_start_run`, and only for one try.
- `end_tick` must fit the wall time between start and submit (no run faster
  than real time).
- **No copied taps**: the second player has the first player's taps, so a
  modded app could submit them as its own and always tie, or follow them
  and play on from there. A run whose taps match the rival's run within one
  tick for more than 30 taps in a row is rejected (honest players never
  match frame-exact).
- Rate limits: 20 open battles, 5 waiting random ones, 30 battle creates a
  day.

## 3. Duel (realtime, later)

### What is sent

Each phone sends a small binary message every 100 ms (every 6 ticks): "I am
at tick T, and these are my taps since the last message". The "no taps up to
tick T" part is what lets the other phone step the rival safely up to T.

```
tick_batch  u8 type, varint end_tick T, u8 n, n x varint (tap tick - previous)
```

| Bandwidth | Per player |
|---|---|
| Payload | 10 messages/s x about 6 bytes = 60 B/s |
| With WebSocket, TLS, TCP/IP | about 0.9 KB/s, 7 kbit/s each way |
| A 4-minute round | about 30 KB payload, about 220 KB on the wire |
| The server, per live match | about 4 KB/s |

### Round end in Duel

Both play until the round is settled: when one crashes at score S, the other
wins the moment they reach S + 1, or loses by crashing below S. A Battle run
always flies to its crash (the second player's "Round won!" shows at S + 1
and they fly on for gold).

### Latency and late packets

- Your bird is never delayed. The rival is drawn at `my_tick - D`, D a
  jitter buffer of 100 to 500 ms (typically 150 to 250 ms, 36 to 60 px
  behind), changed slowly by playing the rival at 0.95x or 1.05x.
- Late up to 0.5 s: a copy of the rival sim (`SimCopy`) guesses "no tap";
  when the real taps arrive it steps on exactly from the last confirmed state
  and the drawn bird eases there over 6 frames. A guessed crash is never
  shown.
- 0.5 to 5 s: the rival fades to 25% with a connection icon.
- Over 5 s: "Mira is reconnecting"; your round goes on.

### Server

- `wss://flapjaw.mn-platform.tech/v1/duel/ws`, axum WebSockets through
  Traefik; the HTTP access token in the first message; Godot's
  `WebSocketPeer`.
- One tokio task per match with both players' Rust sims, stepped as taps
  arrive. The server decides the result.
- **Clock check**: ticks must follow the server clock since the countdown
  within 5 s (no slow-motion play).
- Rejoin: 5 s grace in a round, then a crash at the last confirmed tick; 30 s
  between rounds, else forfeit. Leave = forfeit.
- Random queue by version and a hidden rating whose range widens every 5 s;
  after 30 s with nobody, offer a Battle instead.
- Matchmaking, rounds and results in the same `battles` and `battle_rounds`
  tables with `mode = 'duel'`.
- One replica for now; more need sticky routing by match id. Deploys wait for
  live matches.

## 4. What Battle and Duel share

| Part | Shared | Battle only | Duel only |
|---|---|---|---|
| Rules | `meta/match_rules.gd`: first to N, round winner, ties, time limit, blind decider; the server has the same in SQL/Rust, held together by shared fixtures | turn order, resign and close, bots; missed turns | S + 1 clinch, sudden death |
| Rival | `game/match/rival_view.gd` (the see-through bird, name tag, WILD tag, crash puff) on a second `GameSim` | fed by the `ReplayDriver` from a checked run, stepped with your own tick | fed by `services/duel_link.gd` with the jitter buffer |
| Screens | opponent picker (friend code or link, random), round intro, in-round HUD (both scores, round dots), round result, match result with rematch | battle list, "your turn" states, submit | live countdown, reconnecting |
| Services | `MatchService` (create, join, invite codes, rating) | `BattleService` (HTTP ops) | `DuelLink` (WebSocket) |
| Server | `battles`, `battle_rounds`, invite codes, hidden rating, push kinds, the Rust check | the ops above, the reminder loop, the bot worker | the match actor, clock check |

Layers hold: `sim/` unchanged; `meta/match_rules` pure rules; services carry
network only; `game/` reads both sims and writes neither.

## 5. Wins leaderboards

Who wins the most Battles and Duels, on the leaderboard screen next to the
score boards.

### Where

Today the screen has one tab bar (Today, Daily Run, All-time), a podium for
the top 3, pill rows and your own row pinned at the bottom
(`game/ui/screens/leaderboard_screen.gd`). Five or six tabs in one bar don't
fit a small phone, so:

- A **Scores | Wins** switch under the title. Scores is today's screen as it
  is.
- Wins has its own tab bar: **Battle** and **Duel** (Duel appears when Duel
  ships).
- Under the tabs a **This week | All time** switch.
- The same podium, rows and pinned own row. Each row: place, flyer, name, wins
  (big), W–L and win rate (small).
- Tapping a row shows that player's record: wins, losses, draws, win rate,
  their best streak, and the last 5 matches.

### Ranking

| Choice | Recommendation |
|---|---|
| Ranked by | **Counted wins.** Ties: higher win rate, then who got there first. |
| Win rate | Shown on every row, not used for ranking; "–" below **10 counted matches** (weekly: 3). A win-rate board can come later. |
| Periods | **This week** (Monday 00:00 to Sunday 24:00 Amsterdam time, the boards' day zone) and **All time**. A battle counts in the week it ends. Seasons later, if the game gets ranked seasons. |
| Top | 100 rows plus your own place, like the score boards. |
| Prizes | None for now (open question on rewards). The Today prize rules don't change. |

### What counts

| Ending | Winner | Loser |
|---|---|---|
| Played out (6 wins, or Duel 2) | a win | a loss |
| Opponent leaves a Duel after round 1 | a win | a loss |
| Resign before round 3 (Battle), or leaving a Duel in round 1 | not counted for either | not counted |
| Resign from round 3 on (Battle) | a win | a loss, marked "resigned" in their record |
| Closed after 7 days without a move | not counted | not counted |
| Draw (13 rounds level) | a draw, no win | a draw |
| Against a bot | not counted | not counted |
| Duel server restart | not counted | not counted |

Early resigns don't count so that a quick "start and quit" doesn't hand out
free wins.

### Stopping win farming

The easy farm is two accounts (or a willing friend) playing each other and
one losing on purpose. Recommendation, all of it on the server:

1. **Random matches count in full.** The pool pairs by rating and never the
   same pair twice in a row, so two own accounts rarely meet.
2. **Friend (invite) matches count at most 1 win per opponent per week**, and
   at most 3 per opponent all time. Everything still shows in your own record.
3. **No tanking**: a match counts only if the loser's runs average at least
   5 points (a real run, not a crash on the first wall).
4. **No alt accounts**: the loser's account must be at least 3 days old with
   20 checked runs; a match where both players used the same device key, or
   the same IP during the match, never counts. IPs are kept hashed for 7
   days, as the transfer rate limits already do.
5. **Review**: a player whose counted wins jump far above their history goes
   into the review queue planned for the boards.

Everything is stored, and `counted` with a `reason` decides the boards, so
the rules can be tuned and the boards recomputed without losing matches.

### Server

- Table `match_results`: match, mode, winner, loser, draw, ended_by (played,
  resigned, left, closed, bot), counted, reason, finished_at, week.
- Written in the same transaction that ends a battle or a duel.
- Op `get_wins_board(mode, period)`: top 100, your place, players, `resets_in_s`
  for the weekly board. Op `get_match_record(player, mode)`: one player's
  record for the row sheet.
- Client: `LeaderboardService` gets `WINS_BOARDS` next to `BOARDS`; the
  screen draws them with the same podium and rows.

## 6. Bots kickstart Battle

With few players, a random battle waits a long time for a person. The user's
idea: start with the beast-mode bots playing Battle turns from the server,
then match active players to each other automatically, then phase the bots
out once there are enough players.

### The bot

The FastSim-RS human-model bot (`tools/fastsim-rs/fastsim/src/human/`,
`docs/HUMAN_BOT.md`): the review's `BlindPlanner` with a measured human motor
model on top.

- **Screen-only sight**: it plans on a copy of the sim whose hidden values
  (the next wall's spikes, spawns, hidden exits) are replaced, so it reads
  only what a player sees. The FastSim `sight` check keeps it honest per
  hazard (`docs/BOT_SIGHT.md`).
- **Human limits**: the game's own tap gap (`SimConfig.TAP_GAP`, 100 ms) and
  the motor model's 8-tick thumb gap, tap timing error, and a reaction time
  to new spikes and tells.
- **Skill matched to the player** (decided: more levels): **8 bot levels**
  from beginner to beast, so a match stays close to 50%. The motor model's
  five measured tiers (beginner 30, normal 60, good 120, expert 250, beast
  500+ median points) are anchors, with three levels between them where the
  gaps are widest (between beginner and normal, normal and good, good and
  expert), the tap-timing spread and reaction time interpolated. Each level
  is calibrated once with `fastsim-rs human measure` to a median score. The
  level is picked from the player's hidden Battle rating so the bot wins
  about half the rounds, and moves after every finished battle (a bot that
  won 6-1 plays a level weaker next time). **The level is hidden**, like the
  player's rating: never shown, never in a name.
- **It plays real runs**: the bot's taps go through the same `battle_submit`
  path and the same Rust check, so its runs replay and show as the rival
  like anyone's. It never reads the player's run (its rival ghost): it plays
  the seed on its own, so it can't copy.
- **Its own motor noise is seeded** from the battle and round, so a bot run is
  reproducible for debugging.
- **Pacing**: it answers 2 to 30 minutes after the player's turn (random), so
  a battle feels like a game and not a machine gun, but never makes anyone
  wait hours.

### Never misleading

- The bot has a **BOT pill** everywhere its name shows (battle list, round
  intro, rival tag, result): a small ink pill beside its name. Required, so
  players always know.
- **Friendly names, no skill words** (decided): each bot battle gets a name
  from a small pool (Pip, Juno, Milo, Kiki, Bram, Nova, Tess, Oli, Rumi, Zed,
  Lola, Finn), drawn from the battle id, so one battle keeps its bot's name.
  A name never says how good the bot is ("Good" and the like can demotivate).
- The New battle sheet says it: "Random rival: a player, or a bot when no one
  is free".
- Its looks are the free starter flyers, so a bot never shows off a paid skin.

### What counts

| | Recommendation |
|---|---|
| Wins boards | **Bot matches never count** for wins, losses or win rate on the boards. They show in your own record as "vs bot". |
| Gold | Coins taken still go to gold, as in any checked run. |
| Hidden rating | A bot match moves your rating at half weight, so the next bot and the first people you meet fit your level. |
| Bot farming | Nothing to farm: no board wins, no prizes. |

### Three phases

| Phase | What happens | Moves on when |
|---|---|---|
| **a. Bots kickstart** | Every random battle that no person takes within **10 minutes** gets a bot. A player with no battle open is offered "Start a battle" on Home; the bot answers within minutes. | Phase b is built (with or soon after Battle). |
| **b. Auto-matchmaking** | Players who play are put in battles automatically: after a Classic run or an app open, a player with fewer than 3 auto battles open and **Auto battles** on (Settings, on by default) is given a waiting random battle of a person near their rating ("New battle from Jun, your turn"). People first; a bot only when no person is found in the wait time. | Enough people play Battle. |
| **c. Bots out** | The bot wait time grows with players: 10 minutes, then 2 hours, then 12 hours, then bots stop filling random battles. Open bot battles finish normally. A "Play a bot" choice stays in New battle as practice, if wanted. | Thresholds below. |

Thresholds for phase c (starting guesses, tuned on real numbers):

| Battle players a day | Bot wait | Measured |
|---|---|---|
| under 100 | 10 min | share of random battles a person answered within 2 h |
| 100 to 500 | 2 h | same, plus the median wait for a person |
| 500 to 2000 | 12 h | |
| over 2000, and 90% answered by a person within 2 h for 2 weeks | bots off | |

The server's `ping` carries `bot_wait_s`, so the wait can change without an
update; an admin op `set_bot_wait` sets it.

### Where the bots run

| Option | For | Against |
|---|---|---|
| In the server process (a tokio task) | No new pod | A bot turn is seconds of CPU; it would compete with request handling and the run check on the same pod |
| **A separate worker pod, `battle-bot`** (recommended) | Its own CPU and memory limit, can be scaled to 0 or stopped in phase c without touching the server, crashes stay apart | One more image and Deployment |

The worker is a small Rust binary on the `fastsim` crate (the human module and
the sim), polling a `bot_turns` queue table (`FOR UPDATE SKIP LOCKED`) and
submitting through the same database functions as a player. One replica,
CPU limit 500m, memory limit 128 MB (the planner keeps only beam copies of
the sim, about 1 KB each).

**CPU per turn** (from the measured BlindPlanner speed: 14,000 ticks/s on 4
threads of a Ryzen 9 9950X, so about 3,500 ticks/s a core; a VM core is
taken as half that, about 1,700 ticks/s):

| Run | Ticks | CPU on the VM |
|---|---|---|
| A typical round (score about 30, 45 s of flight) | about 2,700 | about 1.6 s |
| A long round (the 4-minute cap) | 14,400 | about 8.5 s |
| A bot turn (answer plus open: two runs) | | **3 to 17 s** |

At 500m that is about 2,500 to 14,000 bot turns a day; phase a needs far
fewer. Beast and expert use the fine search (about 3.6x the cost), so
those levels take the top of the range. The run check of each bot run costs
the server what any run costs (microseconds a tick, the plain sim).

## 7. Screens

Mockups on the visual page, in the Flapjaw Design Kit style:

- **Modes**: Home with the mode carousel (Battle card with a "2" badge), the
  All modes sheet.
- **Battle**: the battle list (your turn, their turn, finished, with Resign and Close), start a
  battle (friend or random, first to 6), the invite code, the round intro
  ("Mira scored 27, beat it"), playing with Mira's run as the rival, submit
  and the round result ("Next: round 5, you go first"), the match result with
  Rematch.
- **Wins boards**: Scores | Wins with the Battle tab this week, and a
  player's record sheet.
- **Bots**: a bot battle in the list with its Bot badge, and the round intro
  against a bot (Pip, with the BOT pill).
- **Duel**: finding a rival, the pre-round countdown, in round with the live
  rival, between rounds, the match result.

## 8. Diagrams

On the visual page: the Battle state machine and turn sequence, the Duel
state machine and round sequence, the shared architecture.

## 9. Rollout

1. **Mode picker** (3 to 4 days): `GameMode` list, carousel, All modes,
   badges; Classic and Daily Run as the first two cards. No server change
   except `modes_off` in `ping`.
2. **Battle, its wins board and the bots** (about 5 weeks):
   - Server (1 week): one migration with 2 tables and 10 functions, the
     reminder loop, the push kinds and `battles` channel, the copied-taps
     check, App Links / Universal Links files on the host, tests in
     `tools/backend_test.ps1`; `match_results`, `get_wins_board`,
     `get_match_record` and the counting rules (2 to 3 days).
   - Client (1.5 weeks): `MatchRules`, `BattleService`, rival view on the
     replay driver, battle list, flows, push deep links, the Battle card badge,
     the Scores | Wins switch on the leaderboard screen.
   - Tests (0.5 week): rules fixtures shared with the server, a bot playing
     whole battles against a local server, resign and close cases.
   - Bots, phase a (1 week): the `battle-bot` worker (Rust, on the `fastsim`
     crate), the `bot_turns` queue, level matching from the rating, the Bot
     badge, `bot_wait_s` in `ping`; its Deployment in `deploy/`.
   - Phase b (3 to 4 days, soon after): auto battles for active players, the
     Settings switch. Phase c is only numbers (`set_bot_wait`) and needs no code.
3. **Duel** (about 3.5 to 4 weeks, as Battle's rules, rival view, screens and
   tables carry over): WebSocket and match actor (1.5 weeks), `DuelLink` with
   the jitter buffer and live screens (1 week), two headless clients over
   loopback with delay, loss and reorder, bots playing whole matches (1 week).

| Risk | What we do |
|---|---|
| Few players for random matches | Battle first: async needs far fewer players online; random Duel falls back to Battle. |
| Battles stalling (no timers) | Nudges at 1 and 3 days, the Nudge button, the Home badge; Close (no result) after 7 days waiting; 20 slots. |
| Players feel tricked by bots | The Bot badge everywhere, the line in New battle, bot matches off the boards. |
| Bot CPU on the shared VM | Its own pod with a 500m CPU limit; scale to 0 at any time. |
| Win farming with friends or alt accounts | Friend wins capped per opponent, the tanking and alt-account rules, review queue. |
| Copied rival taps | The copied-taps check. |
| Updates in the middle of a battle | The open round is dealt again on the new version. |
| Slow-motion play in Duel | The clock check. |
| Perfect-tapping bots | Review queue; nothing of value at stake. |
| Phones switching networks in Duel | 5 s grace, rejoin. |
| Rules drifting between client and server | Shared fixtures in the check. |

## 10. Decisions and open questions

Decided by the user:

- **Mode picker**: the carousel on Home plus the All modes sheet.
- Battle is **first to 6** round wins.
- **The player who starts the battle opens round 1**, then the opener
  alternates, and round 11 (at 5-5) is blind for both.
- **No battle timers**: no turn deadline, no match cap. Instead: nudges,
  Resign, and Close (no result) after 7 days waiting.
- **At most 20 open battles** per player.
- The rival is drawn **in their own skin, slightly see-through**; no new
  colour token.
- As recommended: Duel round end at S + 1; coins to gold only, nothing for a
  win, no diamonds; hidden rating for pairing; wins boards with a Scores |
  Wins switch, Battle and Duel tabs, This week | All time, ranked by counted
  wins; random matches count in full and friend wins at most 1 per opponent a
  week; a resign before round 3 counts for nobody, later resigns as a win and
  a loss.

Also decided (the user, "rest is fine, start building"): Close (no result)
after 7 days waiting; bot matches never count on the boards; bot waits of
10 min, 2 h, 12 h, then off above 2000 Battle players a day; auto battles on
by default, at most 3, with a Settings switch; "Play a bot" stays as
practice; bots in a separate `battle-bot` pod with a 500m CPU limit; 8 bot
levels, hidden; friendly bot names with the BOT pill, no skill words.

Nothing is open. Building: phase 1 the mode picker, then Battle.
