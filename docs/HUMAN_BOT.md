# Human-model bots (experiment)

Playtest bots that should look like a person playing, at five skill tiers
(beginner 30, normal 60, good 120, expert 250, beast 500+ median points).
A tool only: `tools/fastsim/Human/`, run as `fastsim human <mode>`. It never
changes `sim/` or gameplay. Compare with the RL bot in `docs/RL_BOT.md`.

## Main line: a human layer on the review's BlindPlanner (`MotorPlayer.cs`)

The planner is the bot review's `BlindPlanner` (`Bots/BlindPlanner.cs`): a beam over tap / wait on a copy
of the sim whose RNG and already-drawn hidden values are replaced, so it predicts visible motion (allowed)
but not random outcomes (not allowed). On top of it, a measured human motor model (Isaksen et al. 2015):

- **Tap timing error** (the main skill knob): each planned tap lands `N(0, sigma)` ticks off, early or late.
  Presses are committed ~2.5 sigma ticks ahead (the thumb is on its way); a press can still be held back
  until 5 ticks before it lands.
- **Tap rate cap**: at least 8 ticks between presses (at most 7.5 taps/s).
- **Reaction to new things**: spikes put up at a bounce and newly appearing hazards are hidden from the
  planner for an ex-Gaussian reaction time (mean ~17 ticks, 288 ms): the planner's copy has no spikes on
  that wall yet, and new hazards are not alive in it.
- **Planner settings for an imprecise thumb**: a 16 px margin that also counts the spikes of the wall
  ahead, the ceiling and the floor (`spike_margin`), margin cost 2000 (with 40 the mid-height cost won and
  the planner threaded one-slot gaps), 8 candidate lines tried with taps `round(sigma)` ticks early/late.

Tiers (`MotorTiers.TIER`), yardstick `human:<tier>`:

| tier | tap sd (ticks) | reaction to new things | search |
|---|---|---|---|
| beginner | 1.4 | ~17 ticks | default |
| normal | 0.6 | ~17 ticks | default |
| good | 0 | ~12 ticks | default |
| expert | 0.2 | ~6 ticks | fine (4 px x 12 speed buckets) |
| beast | 0 | none | fine |

With the planned exit mouths known (`TIER_KNOWN_EXITS`, `BlindPlanner.know_exits`; only honest if the
game shows them from room start): good 0.3 / ~17, expert 0 / ~12 / default, beast as above.

Beast has no human limit except the 8-tick thumb gap (free once the planner plans with it). It models
everything visible exactly: the planner steps a copy of the sim, so swings, orbits, pistons, crates
already warned, bramble paths, lava, bubbles, updrafts and visible stalactites move as in the game;
only values not yet on screen are replaced (`blind_copy`).

### What beast lacks (death atlas, `fastsim human atlas`)

Each death is replayed to 240 ticks before it; a fresh beast plays on with one kind of hidden value
left true in its copies at a time (`BlindPlanner.reveal`). Seeds 1..64, cap 30k:

- Hidden exits: 38 deaths. 17 "luck" (another guess of the hidden values lives), 14 saved by the
  exits alone or by the wall seed (which also plans the exits), 2 by the wall seed alone, 5 doomed even
  with the true future. Mostly bramble and stalker rooms: those hazards bounce off the reserved exit
  mouths from room start, before the mouths are drawn.
- Known exits: 16 deaths. 10 saved only by the wall seed (the next wall's spikes and spawns), 3 luck,
  2 doomed, 1 combination.

No death was saved by revealing something that is on screen, so there is no "visible but not
modelled" gap left among the scrambles. The gaps are truly hidden: the next wall (spikes, spawns), and
the exit mouths that hazards react to before they are drawn (a game rule question). Planning over
several guessed futures (copies 3-5) did not help; a finer search did (0.258 -> 0.213 deaths per 100
points on 200 seeds), at 3.6x the cost.

The planner plans with the thumb's limit too: `BlindPlanner.min_gap` (8) and `last_press` (the real
last press), so no line needs two taps closer than the thumb can do. Without that, the 8-tick cap took
the planner from 0.29 to 1.9 deaths per 100 points.

Isaksen's measured human sd is 2.2-3.7 ticks. At that sd this bot scores a rate median of 13-21 (below
beginner); the targets need a steadier thumb than the average player in that study, or a planner that
copes with noise better.

## First try: a human model on a short look-ahead planner (`HumanBot.cs`, real copies)

The player looks at the screen every `think` ticks and plans the next second
or two with copies of the sim, but only with what is on screen:

- **No foresight of new spikes.** The wall ahead gets new spikes at each
  bounce. A planned flight that dies on those after a bounce counts as fine
  (the player can't know yet), and after a bounce it aims at mid screen, not
  at the new gap. A room change ends the plan (the next room isn't on screen).
- **Reaction lag**: a decision can place a tap no earlier than `lag` ticks
  later. Taps already decided in that window stay.
- **Motor noise**: each tap lands `N(0, jitter)` ticks off.
- **Misjudged height**: at each look the player sees itself `N(0, perr)` px off.
- **Lapses**: a look is skipped with chance `lapse`; the old plan runs out.
- **Comfort height**: plans are ranked (among the ones that live) by how
  close they stay to the gap on the wall ahead, pulled toward mid screen
  just after a bounce, with extra cost near the floor and ceiling. This is
  what keeps the bot off the floor.
- **Planner**: a bucketed beam over tap / no tap per tick ("careful search",
  `plan` ticks, `width` lines kept per tick, no taps faster than 6 ticks
  apart), with cheap "habits" (aim at the gap +- an offset, tap now or hold)
  as a fallback.

One skill knob `s` in 0..1 moves every limit together (`Skill.at`), and
`fastsim human fit` bisects `s` per tier to hit the target medians.

## Approach B: reflex rules tuned by evolution (`Reflex.cs`)

No sim copies at all: the bird's own flight (wait or tap now) is
extrapolated with the sim's physics and checked against where hazards are
now (`kills()` probes, like the RL observer), the spikes on the wall ahead,
the ceiling and the floor. A weighted rule of ~10 numbers decides the tap;
`fastsim human train-reflex` tunes them with antithetic, rank-based ES.

## The "looks human" score (`Trace.cs`, `Humanness`)

0..100 from parts that each compare one habit with a band for people playing
one-button flyers: time near the floor (bottom 15%) and ceiling, mean and
spread of the height, the median tap gap and its variation, taps faster than
10 per second, tick-exact repeated gaps, and first taps under ~130 ms after a
bounce (faster than a human can react to new spikes).

No real Flapjaw replays were on this PC (the desktop profile has two runs),
so the bands are priors, not measured. With leaderboard or "Your runs"
replays (needs the user's OK) the bands should be refit from them.

## Commands

    fastsim human measure --skill 0.7 --seeds 100 [--cap ticks] [--set lag=4,perr=2]
    fastsim human measure --bot reflex --seeds 100
    fastsim human baseline --bot gap|rl|search --seeds 32
    fastsim human fit --seeds 60
    fastsim human train-reflex --gens 20 --pop 16 --seeds 24
    fastsim human runfile --skill 1 --seed 7 --out run.json

At most 4 threads (`--threads`), BelowNormal priority.

## Results (yardstick, seeds 1..400, full cap, first death ends the run; next-features-2 code, seed-only generation)

| bot | median | p90 | rate median | tier (rate) | deaths/100 pt | alive at cap | reaction to new things (median, < 10 ticks) |
|---|---|---|---|---|---|---|---|
| human:beginner | 39 | 81 | 30.5 | beginner | 2.25 | 0 | 35 ticks, 7% |
| human:normal | 67 | 154 | 57.7 | normal | 1.19 | 0 | 34, 6% |
| human:good | 153 | 455 | 148.3 | good | 0.47 | 1 | 32, 6% |
| human:expert (= beast) | 226 | 629 | 209.6 | expert | 0.33 | 7 | 32, 5% |
| reflex (approach B, ES-tuned rules, no copies) | 23 | 50 | 18 | below beginner | 3.7 | 0 | - |
| rl:beast (for comparison) | 42 | 78 | 32 | beginner | 2.1 | 0 | 30 ticks, 5%; 62% in the bottom quarter |

Every tier: 1.4 taps/s, 0% of taps under 8 ticks apart, timing sd 2.4-2.5 ticks (Isaksen: 2.2-3.7),
3% of the time in the bottom quarter, no leaks. Deaths per 100 points by score band
(0..10 / 10..20 / 20..40 / 40..80 / 80..160 / 160..320 / 320+): beginner 0.41 / 1.55 / 2.68 / 4.05 / 3.97 / 4.00 / -;
normal 0.03 / 0.36 / 0.72 / 1.92 / 1.82 / 1.70 / 2.42; good 0 / 0 / 0.11 / 0.58 / 0.58 / 0.57 / 0.52;
expert 0 / 0 / 0.03 / 0.37 / 0.33 / 0.42 / 0.39.

Beast misses its target: it is the planner itself with only the 8-tick tap gap, and the planner core
(the review's) sits at ~0.33 deaths per 100 points; beast needs ~0.14.

Findings on the way:
- A tap 1 tick off moves the bird up to ~17 px, so tap timing is the big skill lever. A planner that
  assumes exact taps threads one-slot gaps and dies at once with noise; a margin that counts spikes,
  with a cost that beats the pull to mid height, fixed most of it.
- Reacting ~17 ticks late to new wall spikes more than halves the rate median of a perfect thumb
  (251 -> ~120): the bird runs out of time to reach a far gap. In Flappy Bird (Isaksen) reaction barely
  mattered because pipes show far ahead; here new spikes appear only ~90 ticks before the wall.
- The bot never goes for coins (a person would); it does not hug the floor (1% of the time in the
  bottom quarter).
