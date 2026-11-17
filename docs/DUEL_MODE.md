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

Recommendation: a **mode carousel on Home**, with Play under it.

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
| Looks | The rival in their own flyer, hat and trail at about 45%, with a name tag. One hitbox for all. | |
| Version | A round is played by both on one `GAMEPLAY_VERSION`. | Same inputs, same run only on one sim. |

No sim change, no gameplay-version bump, no new goldens.

## 2. Battle (async)

### Match length (decided: a long match, "best of 10 or something")

| Option | Rounds | For | Against |
|---|---|---|---|
| **First to 6 round wins** (recommended) | 6 to 11 | Ends the moment it is decided, so no dead rounds: a 6-1 is over after 7. At 5-5 one decider settles it. | The length varies (6 to 11 rounds). |
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
| **A. Alternate who goes first; round 11 blind** (recommended) | Over rounds 1 to 10 each player gets the ghost five times. Round 11 (only at 5-5): the second player sees no run until they submit. | A ghost race every round but the decider. |
| B. Alternate, the ghost in every round | One player has the ghost in round 11, the round that decides it | Most ghost racing |
| C. Always blind, ghosts after | Fully fair | Loses watching the rival while you fly |

A battle that ends before round 10 can be uneven by one ghost round (A opened
one round more); first to 6 makes that one round of at least six, which is
small. Rematch swaps who opens round 1.

### How long a battle takes, and the timers

| Pace | Turns a day | A full 12-turn battle |
|---|---|---|
| Both playing now and then through the day (answer within about 2 h) | 6 to 8 | 1.5 to 2 days |
| Each plays once or twice a day | 2 to 4 | 3 to 6 days |
| Each uses the full 24 h every turn | 1 | 12 days |

| Setting | Recommendation |
|---|---|
| Turn timer | **24 h** a turn (as before): fits once-a-day players and time zones. |
| Missed turn | You lose the round you had to answer **and** the round you would have opened (it goes to the other player unplayed). The turn passes back. The other player gets "Mira missed a turn: 2 rounds to you". |
| Stopped replying | **Two missed turns in a row end the match** as a timeout win for the other player (48 h of silence). |
| Match cap | **14 days**: covers the slowest legal pace with room to spare. At the cap the one with more round wins takes it; level is a draw. |
| Open battles at once | **10**, of which at most **3 random ones** waiting for an opponent. |
| A random battle with no opponent | Closed quietly after **48 h** (your run still paid its gold). |
| Rematch | One tap at the result; the other gets a 24 h rematch turn, round 1 opener swapped. |

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
phone mid-run does not give a new try; a run not submitted by the turn's
deadline scores 0. The run's taps are saved locally as it goes (as Your runs
does at the end), so a run whose sending failed is sent later, and an app
killed mid-run sends what it had up to that tick, which the server scores as
a crash there.

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
| 12 h left | "12 hours left to answer Mira" |
| Rival missed a turn | "Mira missed a turn: 2 rounds to you" |
| 2 h left | "2 hours left, or round 2 goes to Mira" |
| Match over | "You beat Mira 6-4" or "Mira won 6-4. Rematch?" |
| Rematch asked | "Mira wants a rematch" |

- Quiet hours: no reminder between 22:00 and 08:00 on the phone's clock
  (`push_devices.utc_offset`); it is sent at 08:00 instead, or earlier when the
  deadline falls in the night.
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
| `battle_list()` | Your battles: your turn, their turn, finished (last 30 days), with scores, deadlines and the opponent's name and look. |
| `battle_get(battle)` | One battle, its rounds, and the rival's run for the round you answer (taps, only once checked `ok`; never in a blind decider before you submit). |
| `battle_start_run(battle, round)` | Checks the turn, hands out the seed and season, records the start. |
| `battle_submit(battle, round, taps, score, coins, end_tick, client_run_id)` | Stores the run (the same `runs` table with `mode = 'battle'`, so the checker handles it), idempotent on `client_run_id`. Answers at once with the round result once the Rust check passes (well under a second). |
| `battle_forfeit(battle)` | Gives up: the other wins. |
| `battle_rematch(battle)` | A new battle with the same two players, first player swapped. |

Tables: `battles` (id, mode, player_a, player_b, first_to, wins_a, wins_b, status, invite_code
hash, random, gameplay_version, turn_player, turn_deadline, missed_in_a_row,
expires_at, created_at, finished_at, winner) and `battle_rounds` (battle,
number, seed, season, first_player, blind, run_a, run_b, winner). The
`mode` column lets Duel reuse both tables.

**Deadlines**: a background task in the server process, like its checker and
push loops (`spawn_checker`, `spawn_push`), every minute: turns past their
deadline score 0, reminders go into the push outbox, battles past
`expires_at` (14 days) end. It locks rows with `FOR UPDATE SKIP LOCKED`, so a second
replica later never handles a battle twice. No CronJob needed.

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
- Rate limits: 10 open battles, 3 waiting random ones, 20 battle creates a
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
| Rules | `meta/match_rules.gd`: first to N, round winner, ties, time limit, blind decider; the server has the same in SQL/Rust, held together by shared fixtures | turn order, deadlines, missed turns | S + 1 clinch, sudden death |
| Rival | `game/match/rival_view.gd` (the see-through bird, name tag, WILD tag, crash puff) on a second `GameSim` | fed by the `ReplayDriver` from a checked run, stepped with your own tick | fed by `services/duel_link.gd` with the jitter buffer |
| Screens | opponent picker (friend code or link, random), round intro, in-round HUD (both scores, round dots), round result, match result with rematch | battle list, "your turn" states, submit | live countdown, reconnecting |
| Services | `MatchService` (create, join, invite codes, rating) | `BattleService` (HTTP ops) | `DuelLink` (WebSocket) |
| Server | `battles`, `battle_rounds`, invite codes, hidden rating, push kinds, the Rust check | the ops above, the deadline loop | the match actor, clock check |

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
| Opponent forfeits (Leave) after round 3 (Battle) or after round 1 (Duel) | a win | a loss |
| Forfeit earlier than that | not counted for either | not counted |
| Timeout (two missed turns, or the 14-day cap with a lead) | a win | a loss, marked as a timeout in their record |
| Draw (13 rounds level, or the cap level) | a draw, no win | a draw |
| Duel server restart | not counted | not counted |
| Closed random battle nobody joined | not counted | |

Early forfeits don't count so that a quick "start and quit" doesn't hand out
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
  forfeit, timeout, cap), counted, reason, finished_at, week.
- Written in the same transaction that ends a battle or a duel.
- Op `get_wins_board(mode, period)`: top 100, your place, players, `resets_in_s`
  for the weekly board. Op `get_match_record(player, mode)`: one player's
  record for the row sheet.
- Client: `LeaderboardService` gets `WINS_BOARDS` next to `BOARDS`; the
  screen draws them with the same podium and rows.

## 6. Screens

Mockups on the visual page, in the Flapjaw Design Kit style:

- **Modes**: Home with the mode carousel (Battle card with a "2" badge), the
  All modes sheet.
- **Battle**: the battle list (your turn, their turn, finished), start a
  battle (friend or random, first to 6), the invite code, the round intro
  ("Mira scored 27, beat it"), playing with Mira's run as the rival, submit
  and the round result ("Next: round 5, you go first"), the match result with
  Rematch.
- **Wins boards**: Scores | Wins with the Battle tab this week, and a
  player's record sheet.
- **Duel**: finding a rival, the pre-round countdown, in round with the live
  rival, between rounds, the match result.

## 7. Diagrams

On the visual page: the Battle state machine and turn sequence, the Duel
state machine and round sequence, the shared architecture.

## 8. Rollout

1. **Mode picker** (3 to 4 days): `GameMode` list, carousel, All modes,
   badges; Classic and Daily Run as the first two cards. No server change
   except `modes_off` in `ping`.
2. **Battle and its wins board** (about 3.5 weeks):
   - Server (1 week): one migration with 2 tables and 8 functions, the
     deadline loop, the push kinds and `battles` channel, the copied-taps
     check, App Links / Universal Links files on the host, tests in
     `tools/backend_test.ps1`; `match_results`, `get_wins_board`,
     `get_match_record` and the counting rules (2 to 3 days).
   - Client (1.5 weeks): `MatchRules`, `BattleService`, rival view on the
     replay driver, battle list, flows, push deep links, the Battle card badge,
     the Scores | Wins switch on the leaderboard screen.
   - Tests (0.5 week): rules fixtures shared with the server, a bot playing
     whole battles against a local server, deadline and expiry cases.
3. **Duel** (about 3.5 to 4 weeks, as Battle's rules, rival view, screens and
   tables carry over): WebSocket and match actor (1.5 weeks), `DuelLink` with
   the jitter buffer and live screens (1 week), two headless clients over
   loopback with delay, loss and reorder, bots playing whole matches (1 week).

| Risk | What we do |
|---|---|
| Few players for random matches | Battle first: async needs far fewer players online; random Duel falls back to Battle. |
| Turns forgotten, long battles stalling | Reminders at 12 h and 2 h, the Home badge; a missed turn costs 2 rounds, two in a row end it; 14-day cap. |
| Win farming with friends or alt accounts | Friend wins capped per opponent, the tanking and alt-account rules, review queue. |
| Copied rival taps | The copied-taps check. |
| Updates in the middle of a battle | The open round is dealt again on the new version. |
| Slow-motion play in Duel | The clock check. |
| Perfect-tapping bots | Review queue; nothing of value at stake. |
| Phones switching networks in Duel | 5 s grace, rejoin. |
| Rules drifting between client and server | Shared fixtures in the check. |

## 9. Open questions for the user

Decided: Battle is a long match. Recommendations first.

1. **Mode picker**: a carousel on Home with an All modes sheet (recommended),
   or tabs along the top?
2. **Battle length**: first to 6 round wins, which ends as soon as it is
   decided (recommended), or 10 rounds always played with a round-11
   tie-break?
3. **Battle fairness**: alternate who opens each round and play round 11
   blind (recommended), the ghost in every round, or always blind?
4. **Battle timers**: 24 h a turn; a missed turn loses the 2 rounds of that
   turn; two missed turns in a row end the match as a timeout; a 14-day cap
   (recommended)? Or 48 h turns with a 21-day cap?
5. **Open battles**: 10 at once, 3 random ones waiting (recommended)?
6. **Duel round end**: play until settled (the survivor wins at S + 1,
   recommended), or first crash loses?
7. **Rewards**: coins to gold only, nothing for a win, no diamonds
   (recommended); diamond prizes on the weekly wins boards later?
8. **Rating**: hidden, used only for random pairing (recommended), or shown?
9. **Rival colour**: a rival violet as a new UI token in the Design Kit
   (recommended), or opacity only in the rival's own look?
10. **Wins boards**: a Scores | Wins switch with Battle and Duel tabs and This
    week | All time, ranked by counted wins with the win rate shown
    (recommended)? Or a win-rate board instead?
11. **Farming**: random matches count in full, friend matches at most 1 win
    per opponent a week (recommended), or only random matches count?
12. **Forfeits and timeouts**: a forfeit before round 3 counts for nobody;
    later forfeits and timeouts count as a win and a loss (recommended)?
