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
- **Duel** (realtime, later): the same best of three, both flying the same
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
  life.", "One map a day · 3 tries", "Take turns · best of 3", "Live 1v1 ·
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
rule_line     "Take turns · best of 3"
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
| Format | Best of three: the first to two round wins. Battle with a friend may choose best of five. | Short enough to finish. |
| Map | A new server seed each round, handed out only when the round's first run starts. Both players get the same seed and season. | Nobody can practise the map. |
| Round winner | Higher score. Equal score: more coins. Still equal: in Duel a sudden-death round, in Battle the round is a draw and does not count (another round is added, at most two). | Coins are a risk to take. |
| Time limit | 4 minutes a run (about 170 points). The run ends there, scored as it stands. | Keeps both modes short and equal. |
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

### How a battle goes

Turns ping-pong, and each turn after the first answers one round and opens
the next, so the game moves on every turn:

| Turn | Who | Plays |
|---|---|---|
| 1 | A (started the battle) | Round 1, first, blind |
| 2 | B | Round 1 with A's run as the rival, then Round 2, first, blind |
| 3 | A | Round 2 with B's run, then Round 3 (the decider at 1-1) |
| 4 | B | Round 3 |

A turn can be one run (the last answer) or two in a row (answer, then open);
after the answer the round result shows, then "Next: Round 2, you go first".

### Who goes first, and the ghost

The second player of a round sees the first player's run while they play:
the target score and the path. That is the fun of it (the user's "you see him
playing while you play"), and also an edge.

| Option | Fair | Fun | Notes |
|---|---|---|---|
| **A. Alternate who goes first; the decider blind** (recommended) | Each player gets the ghost once in rounds 1 and 2. In a decider both play blind: the second player sees no ghost, only after submitting. Best of five: rounds 1 to 4 alternate, round 5 blind. | The ghost race in every round but the decider; the decider is a clean "who is better". | The turn order above gives the alternation for free. |
| B. Always alternate, the ghost in every round | One player gets the ghost one round more in an odd match | Most ghost racing | Unfair in exactly the round that decides it. |
| C. Always blind, ghosts only after | Fully fair | Loses watching the rival while you play | Closer to a score compare. |

### How long a battle lasts ("until how long?")

| Setting | Options | Recommendation |
|---|---|---|
| Match length | Best of 3; best of 5; first to N wins; a fixed number of rounds | **Best of 3** for every battle; **best of 5** as a choice in friend battles. First to N is the same as best of 2N-1; a fixed count allows ties, which feels flat. |
| Turn timer | 8 h, 24 h, 48 h | **24 h** a turn. Fits "once a day" players and time zones. |
| Missed turn | Lose the round; lose the match | The round(s) of that turn score 0 (lost unless the other also scored 0). **Two missed turns in a row lose the match.** |
| Match expiry | 3, 7, 10 days | **7 days** for best of 3, **10** for best of 5. At expiry the leader wins, a level match is a draw. Typical battles finish within a day or two. |
| Open battles at once | 5, 10, 20 | **10 open battles**, of which at most **3 random ones** waiting for an opponent. |
| A random battle with no opponent | | Waits **48 h**, then is closed quietly (your run still paid its gold). |
| Rematch | | One tap at the result; the other gets a "rematch?" turn with 24 h. |

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
| 2 h left | "2 hours left, or round 2 goes to Mira" |
| Match over | "You beat Mira 2-1" or "Mira won 2-1. Rematch?" |
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
| `battle_create(opponent: "invite" \| "random", best_of)` | A battle with A; for random, matches to a waiting battle when there is one. Returns the battle and, for invite, the code. |
| `battle_join(code)` | B joins an invite battle. |
| `battle_list()` | Your battles: your turn, their turn, finished (last 30 days), with scores, deadlines and the opponent's name and look. |
| `battle_get(battle)` | One battle, its rounds, and the rival's run for the round you answer (taps, only once checked `ok`; never in a blind decider before you submit). |
| `battle_start_run(battle, round)` | Checks the turn, hands out the seed and season, records the start. |
| `battle_submit(battle, round, taps, score, coins, end_tick, client_run_id)` | Stores the run (the same `runs` table with `mode = 'battle'`, so the checker handles it), idempotent on `client_run_id`. Answers at once with the round result once the Rust check passes (well under a second). |
| `battle_forfeit(battle)` | Gives up: the other wins. |
| `battle_rematch(battle)` | A new battle with the same two players, first player swapped. |

Tables: `battles` (id, mode, player_a, player_b, best_of, status, invite_code
hash, random, gameplay_version, turn_player, turn_deadline, missed_in_a_row,
expires_at, created_at, finished_at, winner) and `battle_rounds` (battle,
number, seed, season, first_player, blind, run_a, run_b, winner). The
`mode` column lets Duel reuse both tables.

**Deadlines**: a background task in the server process, like its checker and
push loops (`spawn_checker`, `spawn_push`), every minute: turns past their
deadline score 0, reminders go into the push outbox, battles past
`expires_at` end. It locks rows with `FOR UPDATE SKIP LOCKED`, so a second
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
| Rules | `meta/match_rules.gd`: best of N, round winner, ties, time limit, blind decider; the server has the same in SQL/Rust, held together by shared fixtures | turn order, deadlines, missed turns | S + 1 clinch, sudden death |
| Rival | `game/match/rival_view.gd` (the see-through bird, name tag, WILD tag, crash puff) on a second `GameSim` | fed by the `ReplayDriver` from a checked run, stepped with your own tick | fed by `services/duel_link.gd` with the jitter buffer |
| Screens | opponent picker (friend code or link, random), round intro, in-round HUD (both scores, round dots), round result, match result with rematch | battle list, "your turn" states, submit | live countdown, reconnecting |
| Services | `MatchService` (create, join, invite codes, rating) | `BattleService` (HTTP ops) | `DuelLink` (WebSocket) |
| Server | `battles`, `battle_rounds`, invite codes, hidden rating, push kinds, the Rust check | the ops above, the deadline loop | the match actor, clock check |

Layers hold: `sim/` unchanged; `meta/match_rules` pure rules; services carry
network only; `game/` reads both sims and writes neither.

## 5. Screens

Mockups on the visual page, in the Flapjaw Design Kit style:

- **Modes**: Home with the mode carousel (Battle card with a "2" badge), the
  All modes sheet.
- **Battle**: the battle list (your turn, their turn, finished), start a
  battle (friend or random, best of 3 or 5), the invite code, the round intro
  ("Mira scored 27, beat it"), playing with Mira's run as the rival, submit
  and the round result ("Next: round 3, you go first"), the match result with
  Rematch.
- **Duel**: finding a rival, the pre-round countdown, in round with the live
  rival, between rounds, the match result.

## 6. Diagrams

On the visual page: the Battle state machine and turn sequence, the Duel
state machine and round sequence, the shared architecture.

## 7. Rollout

1. **Mode picker** (3 to 4 days): `GameMode` list, carousel, All modes,
   badges; Classic and Daily Run as the first two cards. No server change
   except `modes_off` in `ping`.
2. **Battle** (about 3 weeks):
   - Server (1 week): one migration with 2 tables and 8 functions, the
     deadline loop, the push kinds and `battles` channel, the copied-taps
     check, App Links / Universal Links files on the host, tests in
     `tools/backend_test.ps1`.
   - Client (1.5 weeks): `MatchRules`, `BattleService`, rival view on the
     replay driver, battle list, flows, push deep links, the Battle card badge.
   - Tests (0.5 week): rules fixtures shared with the server, a bot playing
     whole battles against a local server, deadline and expiry cases.
3. **Duel** (about 3.5 to 4 weeks, as Battle's rules, rival view, screens and
   tables carry over): WebSocket and match actor (1.5 weeks), `DuelLink` with
   the jitter buffer and live screens (1 week), two headless clients over
   loopback with delay, loss and reorder, bots playing whole matches (1 week).

| Risk | What we do |
|---|---|
| Few players for random matches | Battle first: async needs far fewer players online; random Duel falls back to Battle. |
| Turns forgotten | Reminders at 12 h and 2 h, the Home badge, two missed turns end it. |
| Copied rival taps | The copied-taps check. |
| Updates in the middle of a battle | The open round is dealt again on the new version. |
| Slow-motion play in Duel | The clock check. |
| Perfect-tapping bots | Review queue; nothing of value at stake. |
| Phones switching networks in Duel | 5 s grace, rejoin. |
| Rules drifting between client and server | Shared fixtures in the check. |

## 8. Open questions for the user

Recommendations first.

1. **Mode picker**: a carousel on Home with an All modes sheet (recommended),
   or tabs along the top?
2. **Battle fairness**: alternate who goes first and play the decider blind
   (recommended), the ghost in every round, or always blind?
3. **Battle length**: best of 3 for all, best of 5 as a choice with friends
   (recommended), or always best of 3?
4. **Turn timer**: 24 h a turn, two missed turns lose the match, 7 days at
   most (10 for best of 5) (recommended)? Or 48 h for a calmer pace?
5. **Open battles**: 10 at once, 3 random ones waiting (recommended)?
6. **Duel round end**: play until settled (the survivor wins at S + 1,
   recommended), or first crash loses?
7. **Rewards**: coins to gold only, nothing for a win, no diamonds
   (recommended); a weekly Battle board with diamond prizes later?
8. **Rating**: hidden, used only for random pairing (recommended), or shown?
9. **Rival colour**: a rival violet as a new UI token in the Design Kit
   (recommended), or opacity only in the rival's own look?
