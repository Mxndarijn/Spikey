# RL bot: a trained player in five skill tiers

A playtest tool: a small neural policy, trained on FastSim, that plays Flapjaw
at five measured skill tiers: `beginner`, `normal`, `good`, `expert`,
`beast`. Use it to see how far players of each level get, which rooms kill
them, and how a change in a room moves those numbers.

**Status: wound down.** The RL bot reached a median of 42 points, far
short of the tiers the user set (30 to 500+), and it can't take a human
reaction delay. The main line for tiered bots is now a planner on
scrambled sim copies (the humanlike-bot session). What was tried, the
numbers, and what was learned: see Results and Lessons at the end. The code
stays as a tool and as the base for the analysis commands (`deaths`,
`heights`).

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

PPO also has options from the research report (`D:\SoftwareProjects\SpikeCage-coord\research\bot-research.md`):
start states from SurvivalSearch runs (`--expert 0.5`), potential shaping
toward the safe height on the wall ahead (`--shape 0.5`), a decision every k
ticks (`--every 2`) with a tap cost (`--tapcost 0.02`), a reaction delay in
the loop (`--delay 12`), and a warm start from `policy.json` (`--from 1`).
The teacher can search on scrambled copies (`--blind 1`): the sim's RNG,
the hazards' RNGs and the crate and dart salts are reseeded, so it can't
know future spikes or drops (`Bubble.next_x` and `Stalactite.target_y` are
still visible to it).

The teacher runs only while training. At play time the policy is alone: it
sees the observation and nothing else.

Evolution strategies (gradient-free, whole-run returns) were tried first and
stopped at a median of about 31; PPO and the teacher got further (see
Results).

## How training runs

    powershell -ExecutionPolicy Bypass -File tools/rlbot.ps1 -Mode train -Minutes 45          # PPO
    powershell -ExecutionPolicy Bypass -File tools/rlbot.ps1 -Mode train -Minutes 45 -Resume
    powershell -ExecutionPolicy Bypass -File tools/rlbot.ps1 -Mode teach -Minutes 45          # teacher, from policy.json

- Up to 8 threads (`-Threads`, default 4, BelowNormal priority). Power
  throttling (Windows efficiency mode) is turned off for the process, and
  teach runs with the server garbage collector.
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

## Results

All numbers: full runs on seeds 1..400, cap `SimConfig.MAX_TICKS`, no revives,
gameplay version 19 (the median-42 policy also measures 42 on version 20).
No run reached the cap. Copies: none (the policy reads only the
observation). Eval medians on held-out seeds (64 at first, 200 later) read
high because training keeps the best of many; the 400-seed numbers are the
ones to trust.

| stage | median | p90 |
|---|---|---|
| evolution strategies, first observation | 13 | |
| evolution strategies, + wall strip and height at the wall | 31 | |
| PPO, 10 min | 34 | |
| PPO + teacher (`tools/rlbot/policy.json`) | 42 | 76 |
| + teacher on scrambled copies | 42.5 | 81 |
| PPO + SurvivalSearch start states + shaping (+ every 2 ticks, tap cost) | 45-46 on 200 eval seeds, not confirmed | |
| policy.json at a 12-tick reaction delay | 1 | 1 |
| PPO trained with a 12-tick delay (`tools/rlbot/policy_delay12.json`), at that delay | 20 | 36 |

Deaths per 100 points by score band (0..10 / 10..20 / 20..40 / 40..80 / 80+):
`policy.json` 0.05 / 0.67 / 2.25 / 5.04 / 6.32; with the 12-tick delay
trained in, 1.10 / 5.72 / 10.37 / 20.24 / -.

The partner session (rl-bot-speedup, notes in `rl-bot-speedup.md`) tried
imitation of whole runs from an aim rule, slack-width labels and Arc inputs
(the bird's own wait and tap arcs against the hazards where they are now):
best 30-36, below 42. Its WorldPlanner-teacher trial (a visible-only planner
as the teacher) was still running when this line was wound down.

### Tiers

`tools/rlbot/tiers.json` holds beast only. Calibrating handicaps on this
policy can't separate tiers: a 1-tick delay already brings it from 42 to
about 32, and a 2-tick delay to about 1, so normal, good and expert all
collapse onto beast or below beginner.

## Lessons

- **No room is impossible.** The full SurvivalSearch survives all 64 full runs
  of 48,000 ticks (median 543 points), and all 200 checked deaths of the
  policy could have been avoided from where the bird entered that room
  (`-Mode deaths`). The limit was the learner, not the game.
- **The policy is a 1-tick feedback controller.** It reacts to the bird's
  exact state every tick with bursts of small taps (3.6 taps per second,
  SurvivalSearch 2.0) and hovers low (62% of its time in the bottom quarter
  of the screen, SurvivalSearch 8%; `-Mode heights`). That style can't
  survive a reaction delay, so human-like handicaps can't be put on top of it
  afterwards. A delay can be learned (1 -> 20 at 12 ticks), so tiers would
  each need training at their own delay.
- **The teacher's labels fit but don't help.** Raising label fit from 86% to
  97%, a 4 s horizon, slack-width labels and scrambled copies all left the
  median at about 42. The teacher saves the run at the last moment by moves
  the policy can't tell apart from what it sees (the imitation gap of a
  future-seeing teacher), and fixing one death moves the error a little
  earlier.
- **Capacity is not the issue.** A 124k-weight network (the partner's) fits
  98-99% of its labels and plays no better.
- **Measure on 400 seeds.** A median over 64 seeds moves between about 39 and
  51 by chance; "55" was such a number.
- **Speed.** Plain play scales well over threads (8 threads 5.3x faster than
  one). The teacher stage needed the server garbage collector and replay
  checkpoints. Windows' per-process CPU time under-reports on this PC: judge
  by throughput.

If a learned bot is wanted later: distil a planner that sees only what a
player sees (no imitation gap), decide every 6 to 8 ticks, and train with the
reaction delay in the loop (the review's step 5).
