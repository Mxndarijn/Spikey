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
| hazards | a danger grid in front of the bird: 10 columns (0..216 px ahead, every 24 px) x 15 rows (-168..+168 px, every 24 px), 1 where some hazard's `kills()` is true for a bird at that point, or the ceiling or floor line |
| motion | the same danger grid 6 ticks earlier, so the policy sees which way hazards move |

The danger grid is the one generic piece: every hazard already answers
`kills(sim)` for the bird's position, so the observer moves the bird to each
grid point, asks every live hazard, and puts the bird back. No per-hazard
code, so new rooms work without touching the bot. Hazards that push instead
of kill (wind, updrafts, bumpers) show up in vy. A hazard may write while it
answers (`EdgePad.guards_edge` bounces the bird and marks the pad), so the
observer asks guards of a copy of the hazard and restores the bird. The
`rlbot` check makes sure probing never changes the sim (checksum before and
after, in every room variant).

The bot sees only what is on screen now and a moment ago: no look-ahead
copies of the sim, unlike PlannerBot and SurvivalSearch.

## Actions

Each tick: tap or no tap. The policy outputs one number; tap when it is above
0. A tap before the run starts starts it.

## Reward

The score: +1 per wall bounce (portals included, as in the game). A run ends
at death or at the tick cap. No revives (no ads in the measurement). Coins
don't count.

## Algorithm

Policy: MLP 355 -> 64 -> 64 -> 1, tanh, about 27,000 weights, plain C#
(`RL/Mlp.cs`: forward, backward, Adam; `RL/Policy.cs`). No framework, no GPU.
Two training stages, both on FastSim:

1. **PPO** (`RL/Ppo.cs`, `-Mode train`): 32 runs play side by side, 512 ticks
   each per iteration; every tick is a sample (tap chance from the policy, a
   separate value network, GAE, clipped policy loss, entropy bonus). Reward +1
   per point, -2 on death. Half the runs start in a random room (practice),
   so later rooms are learned without first surviving to them.
2. **Learning from a teacher** (`RL/Dagger.cs`, `-Mode teach`), starting from
   the PPO policy. The policy plays runs on its own. For every death the
   teacher (`RL/Teacher.cs`: a beam search over copies of the sim, one per
   height and speed bucket) binary-searches back for the last tick where some
   move still lives `horizon` (90) more ticks, and labels the move that saves
   the run there and at earlier ticks where only one move is safe. The policy
   learns these labels by cross-entropy, plus some of its own moves as
   anchors. Practice runs start more often in the rooms that kill it.

The teacher runs only while training. At play time the policy is alone: it
sees the observation and nothing else.

Evolution strategies (gradient-free, whole-run returns) were tried first and
stopped at a median of about 31; PPO and the teacher got further (see
Results).

## How training runs

    powershell -ExecutionPolicy Bypass -File tools/rlbot.ps1 -Mode train -Minutes 45          # PPO
    powershell -ExecutionPolicy Bypass -File tools/rlbot.ps1 -Mode train -Minutes 45 -Resume
    powershell -ExecutionPolicy Bypass -File tools/rlbot.ps1 -Mode teach -Minutes 45          # teacher, from policy.json

- At most 4 threads (`-Threads`, default 4, BelowNormal priority).
- `-Minutes` stops cleanly after the iteration that passes the limit, so a
  long training is done in chunks under an hour. The state is saved to
  `tools/rlbot/train_state.json` (PPO) or `teach_state.json` (teacher) after
  each iteration; `-Resume` goes on from it.
- Every few iterations the policy is scored on held-out seeds; the best is
  kept as `tools/rlbot/policy.json`.

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
- `tools/rlbot/train_state.json`, `teach_state.json`: training state, not committed.

A gameplay change can move the tiers: run `-Mode measure` to see, and
`-Mode calibrate` (minutes) or more training if they drifted.

## Running and measuring

    powershell -ExecutionPolicy Bypass -File tools/rlbot.ps1 -Mode measure -Seeds 400
    powershell -ExecutionPolicy Bypass -File tools/rlbot.ps1 -Mode measure -Tier expert -Seeds 1000
    powershell -ExecutionPolicy Bypass -File tools/rlbot.ps1 -Mode calibrate

    powershell -ExecutionPolicy Bypass -File tools/rlbot.ps1 -Mode deaths -Seeds 200    # were the deaths avoidable?
    powershell -ExecutionPolicy Bypass -File tools/rlbot.ps1 -Mode heights              # where it flies, vs SurvivalSearch

`measure` plays full runs (seed `first..first+n`, no revives, capped at
`SimConfig.MAX_TICKS`) for each tier and prints median, p90, mean, the share
that leaves the first room, and the rooms that killed most. `-Out file.json`
writes the per-run results. `deaths` replays every death and asks the full
SurvivalSearch whether the bird could have lived on from where it entered
that room. `heights` compares how much time the policy and SurvivalSearch
spend in each height band, and where the policy dies.

## Results so far

Medians are full runs on the measure seeds 1..400 unless marked "eval" (the
held-out seeds training picks its best on; 64 of them at first, which read
high, now 200).

| stage | median |
|---|---|
| evolution strategies, first observation | 13 |
| evolution strategies, + wall strip and height at the wall | 31 |
| PPO, 10 min | 34 (eval 43) |
| + teacher | 42 (eval 55) |

Findings:

- No room is impossible. The full SurvivalSearch lives through all 64 of 64
  full runs of 48,000 ticks (median 543 points), and every one of 200 deaths
  of the policy could have been avoided from where the bird entered that room.
- The policy flies low: 62% of its time in the bottom quarter of the screen
  (SurvivalSearch: 8%), with 3.6 taps per second (SurvivalSearch: 2.0). When a
  gap forces it high it overshoots into the ceiling. The teacher only fixes
  the last savable moment, so the low habit is never corrected.
- Fitting the teacher's labels better (97% instead of 86%) did not raise the
  median, and neither did a longer teacher horizon.

Next: label the policy's ordinary moves too (fly toward the gap or exit
height where both moves are safe), a bigger network, and inputs for every
free gap and the exit over the whole wall.
