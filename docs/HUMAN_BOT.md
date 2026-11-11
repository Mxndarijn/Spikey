# Human-model bots (experiment)

Playtest bots that should look like a person playing, at five skill tiers
(beginner 30, normal 60, good 120, expert 250, beast 500+ median points).
A tool only: `tools/fastsim/Human/`, run as `fastsim human <mode>`. It never
changes `sim/` or gameplay. Compare with the RL bot in `docs/RL_BOT.md`.

## Approach A: a human model on a short look-ahead planner (`HumanBot.cs`)

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

## Results

(See the end of this file, filled in after the runs.)
