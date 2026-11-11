# RL bot: a trained player in five skill tiers

A playtest tool: a small neural policy, trained on FastSim, that plays Flapjaw
at five measured skill tiers: `beginner`, `normal`, `good`, `expert`,
`beast`. Use it to see how far players of each level get, which rooms kill
them, and how a change in a room moves those numbers.

It is a tool only (`tools/fastsim/RL/`, run by `tools/rlbot.ps1`). It never
changes `sim/` or gameplay, and the game does not ship it. It reads the sim
the same way the other FastSim bots do and only decides tap or no tap.

## What the bot sees

One observation per tick, built from sim state (`RL/Observer.cs`). All values
are scaled to about -1..1.

| part | values |
|---|---|
| bird | y, vy, direction, gravity sign, distance to the wall ahead (ticks), wall insets |
| wall ahead | 13 slots: spike or free (`sim.wall_mask`), the wall shift |
| exit | open on the wall ahead, preview, the exit heights relative to the bird, Wild/Calm |
| wall strip | 21 heights around the bird (every 16 px, -160..+160): 1 where a bird there would hit a spike on the wall ahead, the ceiling or the floor |
| at the wall | the bird's height when it reaches the wall if it waits and if it taps now (its own fall only, no sim copies), whether that height hits, and the nearest safe height |
| hazards | a danger grid in front of the bird: 7 columns (0..168 px ahead) x 9 rows (-128..+128 px), 1 where some hazard's `kills()` is true for a bird at that point |
| motion | the same danger grid 6 ticks earlier, so the policy sees which way hazards move |

The danger grid is the one generic piece: every hazard already answers
`kills(sim)` for the bird's position, so the observer moves the bird to each
grid point, asks every live hazard, and puts the bird back. No per-hazard
code, so new rooms work without touching the bot. Hazards that push instead
of kill (wind, updrafts, bumpers) show up in vy. The `rlbot` check makes sure
probing never changes the sim (checksum before and after).

The bot sees only what is on screen now and a moment ago: no look-ahead
copies of the sim, unlike PlannerBot and SurvivalSearch.

## Actions

Each tick: tap or no tap. The policy outputs one number; tap when it is above
0. A tap before the run starts starts it.

## Reward

The score: +1 per wall bounce (portals included, as in the game). A run ends
at death or at the tick cap. No revives (no ads in the measurement). Coins
don't count.

## Algorithm: evolution strategies on a small MLP

- Policy: MLP 181 -> 32 -> 16 -> 1, tanh, about 6,400 weights, plain C#
  (`RL/Policy.cs`). No framework, no GPU.
- Training: OpenAI-style evolution strategies (`RL/Trainer.cs`). Each
  generation draws N noise vectors, plays the weights +noise and -noise
  (antithetic pairs) on the same seeds, ranks the returns and steps the
  weights with Adam. This is gradient-free RL: it only needs whole-run
  returns, which suits a game where one late mistake ends the run, and every
  run is independent, so it parallelises over threads with no shared state.
- Episodes per candidate: a mix of full runs (from the start room) and
  practice runs that start in a random room (`GameSim(seed, season, room)`),
  so later rooms are learned without first surviving to them. Episodes are
  capped (default 3,600 ticks) to keep generations short.
- Seeds come from the generation number, so a training run is reproducible.

## How training runs

    powershell -ExecutionPolicy Bypass -File tools/rlbot.ps1 -Mode train -Minutes 45
    powershell -ExecutionPolicy Bypass -File tools/rlbot.ps1 -Mode train -Minutes 45 -Resume

- At most 4 threads (`-Threads`, default 4, BelowNormal priority).
- `-Minutes` stops cleanly after the generation that passes the limit, so a
  long training is done in chunks under an hour. The state (weights, Adam
  moments, generation) is saved to `tools/rlbot/train_state.json` after each
  generation; `-Resume` goes on from it.
- Every 10 generations the current weights are scored on fixed held-out
  seeds; the best ever is kept as `tools/rlbot/policy.json`.

## How the tiers are made

One strong policy (beast) plus handicaps that act like a human player's
limits, not a separate network per tier:

- **Reaction delay**: the policy sees the observation of `delay` ticks ago.
- **Tap jitter**: each tap lands 0..`jitter` ticks late (random).
- **Missed taps**: each tap is dropped with probability `miss`.

A tier is a target median score. `-Mode calibrate` walks one skill knob
s in 0..1 (delay, jitter and miss all grow as s drops) and bisects s until the
measured median over the calibration seeds hits the tier's target. Beast is
the policy with no handicap.

Targets (median score per run; 10 points = one room), set by the user: beast
is "basically unlimited" (500 or more), the lowest tier at least 30, and each
tier about double the one below:

| tier | target median |
|---|---|
| beginner | 30 |
| normal | 60 |
| good | 120 |
| expert | 250 |
| beast | 500 or more (the policy, no handicap) |

Tiers count as separated when each tier's
median is at least 1.5 times the one below and the p25 of each tier is above
the median of the tier below it.

Checkpoints by score were the alternative. They were left out because an
early checkpoint plays strangely (taps at random), not like a weak human,
and their levels can't be tuned after training.

## Where weights are stored

- `tools/rlbot/policy.json`: the weights, the observation layout version, and
  the `GAMEPLAY_VERSION` it was trained on.
- `tools/rlbot/tiers.json`: each tier's handicaps (delay, jitter, miss) and the
  median/p90 measured when it was calibrated.
- `tools/rlbot/train_state.json`: training state, not committed.

A gameplay change can move the tiers: run `-Mode measure` to see, and
`-Mode calibrate` (minutes) or more training if they drifted.

## Running and measuring

    powershell -ExecutionPolicy Bypass -File tools/rlbot.ps1 -Mode measure -Seeds 400
    powershell -ExecutionPolicy Bypass -File tools/rlbot.ps1 -Mode measure -Tier expert -Seeds 1000
    powershell -ExecutionPolicy Bypass -File tools/rlbot.ps1 -Mode calibrate

`measure` plays full runs (seed `first..first+n`, no revives, capped at
`SimConfig.MAX_TICKS`) for each tier and prints median, p90, mean, the share
that leaves the first room, and the rooms that killed most. `-Out file.json`
writes the per-run results.

## Results

(Filled in after training.)
