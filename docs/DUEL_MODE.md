# Duel mode (plan)

Status: **plan only, waiting on the user's answers** (open questions at the
end). No game or server code is written, and nothing in `sim/` changes.
Visual version with the mockups and diagrams:
<https://claude.ai/artifact/9cnM2DPqVKpwRShzaFRq4j> (source:
`docs/mockups/duel_mode.html`). This file is the text copy; keep
both in step.

Builds on the server move (`docs/SERVER_MIGRATION.md`, branch
`claude/server-backend-e4288c`): the Rust axum server with Postgres on k3s,
the Rust sim (`tools/fastsim-rs`) in the server, device-key sign-in.

## The idea in one paragraph

Two players, best of three rounds. Each round both fly the same map (a seed the
server picks) at the same time, and each sees the other as a see-through rival
bird on their own screen. Because a run is fully described by
`(gameplay_version, seed, tap ticks)`, the phones send each other only their
tap ticks through the server, and each phone rebuilds the rival exactly with a
second `GameSim`. The server runs both sims too and is the judge.

## 1. Game rules

| Rule | Recommendation | Why |
|---|---|---|
| Format | Best of three. The first to two round wins takes the match. A third round only when it is 1-1. | The user's ask. |
| Map | A new server seed each round, revealed only at the countdown (like the Daily Run seed). Both players get the same seed and season. | Nobody can practise the map, and three rounds are three different maps. |
| Who wins a round | Both play on until the result is settled: when one crashes at score S, the other wins the moment they reach S + 1, or loses by crashing at S - 1 or lower. "First crash loses" is the simpler alternative (open question 1). | Same pace for both (constant sideways speed), so a higher score also means lasting longer. Ending at S + 1 keeps rounds short and gives a clear "beat 23!" moment. |
| Ties | Equal score: more coins wins (coins are risky to take), then a sudden-death round on a new seed. | Coins reward skill, not money. |
| Time limit | 4 minutes a round (about 170 points at 4 px a tick). At the limit: higher score, then coins, then sudden death. | Two strong players could fly for a long time; a duel should be a few minutes. |
| Revives | Off. A crash ends that player's round. | Like the Daily Run; nothing to buy or watch that changes a result. |
| Pause | None. Leaving the app counts as a crash after a 5 s grace. | The rival keeps flying. |
| Fork rooms | Allow the split. The Calm and Wild exits lead to the same door of the same next room, so only that one room differs (Wild's extra spikes, `WILD_SPIKES`), and the map is the same again after it. Wild's 5 coins also matter for the tie-break. The rival shows a small WILD tag in that room. | No seed filtering, no syncing a choice, and the risk-or-safe choice is a nice duel moment. Fork-free seeds don't exist: every seed has a fork every 50 points. Syncing the choice would need a Duel-only sim rule, a gameplay change. |
| Out of step | A bumper turning the bird back, or a boss hold, can put the two birds a room apart. The rival is drawn only when both are in the same room index; otherwise an edge tag shows "Mira · room 7". | The rooms are the same, but the walls drawn are one player's. |
| Bird-following hazards | Stalker, Dart aim and Echo follow each player's own bird, so they differ. Only your own hazards are drawn; the rival can crash into something you don't see (a crash puff shows where). | Drawing the rival's hazards would clutter and mislead. |
| Coins and gold | Coins taken in a Duel go to gold like any verified run. No gold or diamonds for winning in phase 1 and 2. No stakes or wagers, ever. | Keeps monetization cosmetic only and avoids anything like betting. Later: a weekly Duel board with small diamond prizes like Today (open question 3). |
| Boards | Duel runs do not count on Today, Daily Run or All-time. | In the async phase the second player sees the first one's ghost, which is a hint. |
| Looks | The rival is drawn in their own flyer, hat and trail at about 45% opacity, with a name tag. Same hitbox for everyone. | Your bought looks are seen by others: a cosmetic reason to buy, nothing more. |
| Version | Both players must be on the same `GAMEPLAY_VERSION`; matchmaking pairs by version. | Same inputs, same run, only on the same sim. |

No sim change: a Duel round is a normal `GameSim(seed, season)` with
`MAX_REVIVES` unused. No gameplay-version bump, no new goldens.

## 2. Seeing each other live

### What is sent

Each phone sends a small binary message every 100 ms (every 6 ticks): "I am at tick T, and these are my taps since the last message". The
"no taps up to tick T" part matters as much as the taps: it is what lets the
other phone step the rival safely up to T.

```
tick_batch  u8 type, varint end_tick T, u8 n, n x varint (tap tick - previous)
```

### Bandwidth

| | Per player |
|---|---|
| Payload | 10 messages/s x about 6 bytes = 60 B/s (a tap adds 1 to 2 bytes) |
| With WebSocket, TLS, TCP/IP headers | about 90 bytes a message, so about 0.9 KB/s, 7 kbit/s each way |
| A 4-minute round | about 30 KB payload, about 220 KB on the wire, both directions together under 0.5 MB |
| The server, per live match | 2 players x 2 directions, about 4 KB/s |

A 3G connection carries this easily; an image on the Home screen costs more.

### Latency: the rival a little behind

- Your own bird is never delayed: your sim runs on your phone at 60 Hz as
  today.
- The rival is drawn at `display_tick = my_tick - D`. D is a jitter buffer:
  the 95th percentile of how late the rival's batches arrive plus one batch
  (100 ms), kept between 100 ms and 500 ms. Typical: 150 to 250 ms (9 to 15
  ticks), which at 4 px a tick is 36 to 60 px behind.
- D changes slowly: the rival plays at 0.95x or 1.05x speed for a moment to
  catch up or fall back, never a jump.
- The HUD shows the rival's confirmed score, so it can lag yours by a point
  for a moment; the server's result is what counts.

### When packets come late

1. **Within the buffer**: nothing to see; that is what D is for.
2. **Past the last confirmed tick, up to 0.5 s**: the rival sim steps on a copy
   (`SimCopy`) guessing "no tap". When the real taps arrive, the copy is
   thrown away, the rival sim steps exactly from its last confirmed state, and
   the drawn bird eases to the true spot over 6 frames. A guessed crash is
   never shown: the bird just holds.
3. **0.5 to 5 s**: the rival fades to 25% with a small "connection" icon over
   it; the buffer grows so it plays smoothly again when data returns.
4. **Over 5 s**: "Mira is reconnecting". Your round goes on; see rejoin rules.

### Drawing the rival without touching your sim

```
services/duel_link.gd      WebSocketPeer, encodes and decodes batches (services: may use sim/, meta/)
meta/duel_rules.gd         best of three, clinch, ties, time limit (pure rules, like DailyRunRules)
game/duel/rival_driver.gd  its own GameSim (a second instance), stepped from DuelLink's taps,
                           the jitter buffer, the guess-and-correct copy
game/duel/rival_view.gd    a BirdView in the rival's look at 45%, name tag, WILD tag, crash puff
game/duel/duel_flow.gd     the screens and rounds, like DailyRunFlow
```

- `sim/` does not change; it already supports many `GameSim` instances (the
  bots and `SurvivalSearch` run many side by side).
- Your `RunController` and its `GameSim` are not touched. The rival driver owns
  a separate `GameSim` that only reads taps; `game/` reads both sims and
  writes neither (it only calls `step(tap)` on the rival's, as the replay
  driver does for Watch).
- The rival's sim draws no room: your `RoomView` and `HazardLayer` stay yours.
  It gives only the rival bird's position, flap, crash and score.
- No sounds or haptics for the rival, except a soft sound when they crash.
- `test_layers.gd` holds: `services/duel_link` imports no `game/` code.

## 3. Network and server

### Transport

- One WebSocket per player: `wss://api.<domain>/v1/duel/ws`, axum's
  WebSocket support; Traefik passes WebSockets through without extra config.
- Sign-in: the same access token as the HTTP API, sent in the first message.
- Godot: `WebSocketPeer` (built in, works on Android and iOS).
- Each live match is one tokio task (an actor) on the server holding both
  players' Rust sims, stepped as taps arrive. A match is tiny in memory and CPU
  (two sims, microseconds a tick).
- One replica to start, so all matches live in one process. More replicas later
  need sticky routing by match id; not needed for a long time.
- Results, both tap lists and the seeds are written to Postgres at each round's
  end (`duel_matches`, `duel_rounds`), so a crash of the server loses at most
  the round in play.

### Match lifecycle

`Queued or Invited -> Matched -> Ready check (both tap Ready, 15 s) ->
Countdown (3 s, the seed is sent here) -> Round live -> Round over (5 s, scores
and replays) -> next Countdown, or Match over -> Rematch offer (20 s)`.
Any state: a disconnect starts the grace timer; a leave is a forfeit.

### Matchmaking

| Way in | Phase | How |
|---|---|---|
| Invite code or link | 1 and 2 | 6 letters (no look-alikes, like the transfer code), `https://<domain>/duel/ABC123` opens the app. The host waits; the code lasts 10 minutes. |
| Random queue | 2 | Pair by gameplay version, then by a Duel rating (Glicko-2) whose range widens every 5 s. After 30 s with nobody: offer a ghost duel against a recent player's verified run (phase 1 mode) instead. |
| Friends | later | Needs a friends list and so stable accounts (Apple/Google sign-in, `docs/ACCOUNT_TRANSFER.md` phase 2). |

### Rejoin, disconnect and forfeit

- In a round: your bird keeps flying on your phone. Taps sent within 5 s of
  the server's clock count. Past 5 s the server ends your round as a crash at
  the last tick it confirmed. Back within 30 s: you rejoin for the next round.
- Between rounds: 30 s to come back, else the match is forfeited.
- Leaving the match (Back, then Leave) is a forfeit: the other player wins
  2-0 or 2-1 from where it stood. Three forfeits in a day: 10 minutes out of
  the random queue.
- A server restart: matches in play end with no result (no rating change);
  deploys wait until no match is live or 10 minutes have passed.

### Anti-cheat (the server judges)

- The server steps both sims from the received taps, so the result never comes
  from the phones. Same Rust sim as the replay check; a round both phones and
  the server disagree on goes to the headless Godot check as today.
- **Clock check**: a player's ticks must follow the server's clock since the
  countdown, within 5 s. This stops slowing the game down to play a hard room
  in slow motion, the one cheat realtime makes possible.
- Taps must be ascending, at most one a tick, and at most 20000 a round, as
  `submit_run` checks.
- Bots that tap perfectly are not stopped by any of this: plausibility checks
  (tap timing spread, a sudden jump over the player's history) go into a
  review queue, as planned for the boards.

### Needed from the server move first

- Phase 1 (async): only HTTP ops. It can go on Supabase today (3 SQL functions
  in the Daily Run style) or on the new server's same ops. Recommended: build
  it on the new server after the cutover, so it isn't written twice.
- Phase 2 (realtime): the new server live (rollout step 5), its sessions and
  device-key sign-in, the Rust sim in the server (built on the branch), the
  versioned verifier (`sim_g24`, ...), the 426 "please update" answer,
  WebSocket through the ingress. Supabase can't host this.

## 4. Screens

Mockups on the visual page, in the Flapjaw Design Kit style:

1. **Duel entry**: a Duel card on Home under Play; the Duel sheet with "Find a
   rival", "Invite a friend", "Enter a code", your Duel record.
2. **Matchmaking and waiting**: the search with a timer and Cancel; the invite
   code with Copy and Share.
3. **Pre-round countdown**: both name plates with flyers, "Round 1", the round
   dots, 3-2-1.
4. **In round**: your bird, the rival's see-through bird with its name, both
   scores at the top, the round dots in the middle.
5. **Between rounds**: who won the round and by how much, the dots, "Round 2 in
   5", Watch round.
6. **Match result**: Win or Loss, 2-1, the three round scores, Rematch, Home.

## 5. Diagrams

On the visual page: the match state machine, the message sequence of one round
and the architecture (phones, server match actor, Postgres, Godot check).

## 6. Rollout

### Phase 1: ghost duel (async), about 1.5 to 2 weeks

- The challenger plays three rounds on three server seeds; the runs are
  verified like any run. They get a code or link to send.
- The rival plays each seed with the challenger's verified run drawn as the
  rival bird (the existing replay driver, stepped in step with their own
  tick). The match is decided when someone has two round wins, so a third
  round may not be needed.
- The challenger gets a notice (push, already built) and can watch each round
  with both birds.
- Server: 3 ops (`create_duel`, `get_duel`, `submit_duel_round`), 2 tables,
  the same checks as `submit_daily_run`. Client: the screens, `RivalView`,
  `DuelRules`. Works on today's backend if wanted.
- Most of phase 2's client code (rival view, rules, screens) lands here.

### Phase 2: realtime, about 4 to 5 weeks

- Server WebSocket, match actor, queue, rating, rejoin rules: 1.5 to 2 weeks.
- Client `DuelLink`, jitter buffer and guess-and-correct, live screens: 1.5
  weeks.
- Tests: two headless Godot clients over loopback with added delay, loss and
  reorder (`tools/duel_net_test.ps1`), bots playing whole matches against the
  server, the server's rules against the GDScript `DuelRules` on shared
  fixtures: 1 week.

### Risks

| Risk | What we do |
|---|---|
| Too few players for a random queue | Invite links first; a ghost duel when the queue is empty. |
| Phones switching networks, iOS stopping sockets in the background | 5 s grace and rejoin; a 4-minute cap keeps rounds short. |
| Slow-motion cheating | The clock check. |
| Perfect-tapping bots | Review queue, rating floor before prizes; no money at stake. |
| Two gameplay versions at once after an update | Pair by version; 426 forces updates. |
| Server restart kills live matches | Deploys wait for live matches; at most one round lost. |
| Drift between GDScript and Rust rules | Shared fixtures in the check, like the FastSim-RS parity step. |
| Rival in a different room (bumper, boss hold) | Edge tag instead of the bird. |

## 7. Open questions for the user

1. **Round end**: play until settled (crash, the other wins at S + 1), or
   first crash loses?
2. **Forks**: allow the split (recommended: one room differs, then the map is
   the same again), or a Duel-only rule that both take the same exit (a sim
   change and a gameplay-version bump)?
3. **Rewards**: coins to gold as in any run, nothing for winning, no diamonds
   for now. A weekly Duel board with diamond prizes later?
4. **Time limit**: 4 minutes a round, coins as the tie-break?
5. **Ghost duel fairness**: the second player sees the first player's bird
   (recommended, it is the fun of it), or both fly blind and compare after?
6. **Seeds**: a new map each round (recommended), or one map for all three?
7. **Phase 1 timing**: build the ghost duel on Supabase now, or wait for the
   new server (recommended)?
8. **Random queue and rating**: show a Duel rating to players, or keep it
   hidden and only use it for pairing?
9. **Rival colour**: add a rival violet to the Design Kit as a UI token, or
   draw the rival only by opacity in its own look?
