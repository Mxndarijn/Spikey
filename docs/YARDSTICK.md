# Bot yardstick

One measure for every playtest bot, so the RL tiers, the world-model planner, the
human-like planner, the MPC planner and any later bot can be compared on the same
numbers. FastSim only (`tools/fastsim/Yardstick/`): no Godot, no window.

```
powershell -ExecutionPolicy Bypass -File tools/yardstick.ps1 -Mode list
powershell -ExecutionPolicy Bypass -File tools/yardstick.ps1 -Bot rl:all              # quick set
powershell -ExecutionPolicy Bypass -File tools/yardstick.ps1 -Bot mybot:all -Set full
powershell -ExecutionPolicy Bypass -File tools/yardstick.ps1 -Mode compare            # rebuild the table
```

Each bot and set writes `<bot>_<set>.json` to `-Out` (default
`D:\SoftwareProjects\SpikeCage-coord\research\yardstick`). `comparison.md` there is
rebuilt from every JSON in the folder after each run, so one table covers every bot
that has been measured. Take a CPU slot for big runs.

## Plugging a bot in

A bot is anything that answers "tap this tick?" for a live `GameSim`: a function
`GameSim -> bool`, called once per tick before `sim.step()`. It must not step or
change that sim (clone it to look ahead). Register it from your own file, so no one
edits the yardstick's files:

```csharp
static class MyBotYardstick
{
    [System.Runtime.CompilerServices.ModuleInitializer]
    internal static void Init()
    {
        foreach (var level in new[] { "beginner", "normal", "good", "expert", "beast" })
            FastSim.Yard.Bots.add(new(
                $"mybot:{level}",              // family:level; "mybot:all" runs them in tier order
                "what it is, its knobs",        // shown in the JSON and by -Mode list
                FastSim.Yard.Copies.NONE,       // what it steps to look ahead (see below)
                seed => new MyBot(level, seed).decide));
    }
}
```

`seed` is the run's seed: use it for the bot's own randomness so runs repeat. A new
instance is made per run, so per-run state is fine. Name levels after the tiers
(`beginner normal good expert beast`): the table then checks the claimed tier.

Every bot states what it reads (the *copies* column):

- `Copies.REAL`: it steps copies of the real sim, so it knows hidden random draws (RNG,
  rooms not yet shown). PlannerBot and the SurvivalSearch oracle do. A ceiling, not a player.
- `Copies.SCRAMBLED`: it steps copies whose RNG and hidden salts are replaced by its own
  random numbers. It knows the rules and visible motion (swings, saws, pistons), not the
  draws. The user allows predicting visible motion, not RNG outcomes.
- `Copies.NONE`: it plays from what it sees.

Built in: `gap` (gap seeker, none), `planner` (PlannerBot, real), `search`
(SurvivalSearch re-planned every 30 ticks, real, an oracle; slow), `honest` (the bot
review's BlindPlanner, `Bots/BlindPlanner.cs` from 651f45d: a beam on one copy with every
hidden draw replaced, horizon 200, 110 ticks past the next bounce, margin 10, re-planned
every 4 ticks; scrambled), `honest-v1` (the review's first try, which still leaks some
hidden draws: "scrambled (leaky)"), `rl:<tier>` (the policy and tiers in `tools/rlbot`, none).

## Seeds and cap

The shared protocol from the bot review (`SpikeCage-coord/research/bot-review.md`):

| set | seeds | cap |
|---|---|---|
| quick | 1 .. 100 | `BotCaps.RUN_CAP` (216 000 ticks, 60 min, about 2 400 points) |
| full | 1 .. 400 | `BotCaps.RUN_CAP` |

`BotCaps.RUN_CAP` (`tools/fastsim/Bots/BotCaps.cs`) is the bots' cap, twice the game's own
`SimConfig.MAX_TICKS` (30 min), which replays use; a bot run longer than that can't be
replayed or rendered by the game. Tables made before 2026-11-12 used `SimConfig.MAX_TICKS`.

A run ends at its first death: no revives. Every JSON states `gameplay_version`. A
median over 64 seeds moves between 39 and 51 by chance, over 400 between 41 and 46:
don't call a gain on fewer than 400. `capped` counts runs alive at the cap; when there
are any, their median is a floor, not a score.

## Leak check

The rule: a bot may know only what is on screen: not where the portal will be before it
is drawn, the next spike walls, the next room or hidden timers. `Leak.cs` tests it.
Each of 24 seeds is played twice by two fresh copies of the bot, forking just after a
wall bounce near ticks 200, 700, 1500, 3000, 5000 and 8000. At the fork the second sim
gets every hidden draw replaced (`BlindPlanner.blind_copy`: the sim's RNG, which draws
the next walls, the portal and the next room, plus the hazards' salts, private RNGs and
drawn-but-unshown values). Both bots have seen the same screen, so until something
visible differs between the two sims (`Leak.visible`: the sim's checksum with those
hidden values fixed) an honest bot must tap the same. A tap that differs earlier is a
leak. `leaks: yes (n/m)` gives the forks that leaked out of those tested;
`same_screen_ticks_median` is how long the screens stayed the same (about one flight,
83 ticks). Hidden values that blind_copy does not replace are not tested, and a
hazard's leak shows only when that hazard is in play during a tested flight.

```
powershell -ExecutionPolicy Bypass -File tools/yardstick.ps1 -Mode leak -Bot planner,honest
```

`-Mode leak` adds the result to the bot's JSONs already in `-Out` and rebuilds the table;
`-Mode run` runs it for every bot it measures.

## Strength

- `median`, `p25`, `p75`, `p90` of the score.
- `death_rate_per_point` h = deaths / (points scored + deaths): the chance to die at
  each point. Scores are roughly exponential (Isaksen et al. 2015), so h uses every run
  and is steadier than the median. `rate_median` = ln 0.5 / ln(1 − h) is the median an
  exponential player with that rate would have; tiers are judged on it.
- Tiers: the nearest target on a log scale. Edges are the geometric middles of
  30 / 60 / 120 / 250 / 500: beginner < 42, normal < 85, good < 173, expert < 354,
  beast from 354. Under 21 is "below beginner". `fits` says whether the tier a bot's
  name claims is the one it lands in.
- `exp_fit_ks`: the Kolmogorov-Smirnov distance between the scores and the
  exponential fit. Small (~0.1) means the bot dies at a steady rate, like a human
  population; large means it dies in the same few places.
- `deaths_per_100_by_band`: deaths per 100 points scored inside each score band
  (0..10, 10..20, 20..40, 40..80, 80..160, 160..320, 320+). A run ending at p scored
  min(p, hi) − lo points in each band it reached and died in the band holding p; capped
  runs count their points and no death. It works on capped runs and needs fewer seeds.
  The review found the rate rises about 250 times from the first room to score 40, then
  stays flat: low tiers are about the ramp, high tiers about the plateau rate.
- `killers`: the rooms (room/variant) it dies in most, with deaths per visit, and
  `deadliest_per_visit` (rooms visited 20+ times).

## Human-likeness

- Taps made while the bird waits at a portal (`arrival_hold`) do nothing in the game and
  are left out of every tap number; `taps_ignored_in_portal_wait` gives their share.
- `taps_per_s` (per run), and the inter-tap interval histogram. Humans tap at most
  7.7 times a second (Isaksen 2015), so `under_8_ticks` should be about 0. A bot that
  taps on many ticks in a row shows up here.
- `height_bands`: share of ticks in 8 bands from the ceiling kill line (band 0) to
  the floor kill line (band 7); `bottom_quarter` is the last two.
- `timing`: tap timing against the ideal moment. A *press* is a tap or a burst of
  taps no more than 3 ticks apart. Each press is moved by −12..+12 ticks with the run's
  other taps kept; the shifts the bird survives (40 ticks past) form its window, and
  the window's middle is the ideal moment. For presses whose window is closed on both
  sides (`critical`), `error_sd` is the spread around the ideal (positive mean = late).
  Isaksen measured σ 36–61 ms for humans: 2.2–3.7 ticks. This replays the real sim
  but only to judge taps already made. Judged on the first 40 runs, 20 presses each.
- `react_new`: ticks from a new room or a new hazard to the next tap; `react_bounce`
  the same after a wall bounce. Humans react in ~17 ticks (288 ms), rarely under 10.
  This is a proxy: a tap can be planned before the new thing shows.
- `reference`: pass/fail against those published human numbers.

### Against human runs

No human runs of Flapjaw exist on this PC yet (no `runs.json` in the game's user
data, the upload queue is empty, golden replays are bot-made). The yardstick reads
any run file (`meta/run_file.gd`), a folder of them, or a Your runs file
(`user://runs.json`, every object with `"format": "flapjaw_run"`). Runs of another
gameplay version are skipped, since they no longer replay.

```
powershell -ExecutionPolicy Bypass -File tools/yardstick.ps1 -Mode humans -Human <file or folder>
powershell -ExecutionPolicy Bypass -File tools/yardstick.ps1 -Bot rl:all -Human <file or folder>
```

`-Mode humans` adds a `human` row to the table. `-Human` with a run adds `vs_human`
to each bot's JSON: total-variation distances of the interval, height and reaction
histograms, a KS distance of taps per second, `likeness` (1 − their mean), and a
human-vs-bot classifier (logistic regression on 15 per-run features, 5-fold
cross-validated; the Navigation Turing Test idea, Devlin et al. 2021). Balanced
accuracy 0.5 means the classifier can't tell the bot from the humans.

What would be enough: 30+ human runs on the current gameplay version, ideally from a
few players at different skill, played on the phone (touch timing differs from a
mouse). The Your runs file keeps the last 100.

## Check

`fastsim check yardstick` (part of `tools/check.ps1`) checks that a replay of a bot's
taps scores what the bot scored, the tier edges, and that the classifier tells the
gap seeker from the RL bot but not two halves of the gap seeker's runs.
