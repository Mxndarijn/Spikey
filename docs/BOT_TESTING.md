# Bot testing: the protocol

How to tell whether a bot change helps, and how to report a bot's tier, for the
least CPU. FastSim only (`tools/fastsim/Measure/`), no Godot, no window. The
statistics behind it are in the measurement review
(`SpikeCage-coord/research/planner-review/10-measurement.md`); `docs/YARDSTICK.md`
has the yardstick and the `-Mode stats` tool this builds on.

```
powershell -ExecutionPolicy Bypass -File tools/yardstick.ps1 -Mode quick   -Bot blind,blind:fine=0
powershell -ExecutionPolicy Bypass -File tools/yardstick.ps1 -Mode confirm -Bot blind,blind:fine=0 -Ratio 0.8
powershell -ExecutionPolicy Bypass -File tools/yardstick.ps1 -Mode report  -Bot blind:fine=0 -Fair fair.txt
```

Take a CPU slot for each of them (`VARIANT_RULES.md`). Files go to
`-Out\measure` (default `SpikeCage-coord\research\yardstick\measure`).

| stage | what it does | seeds | typical CPU |
|---|---|---|---|
| `quick` | stratified screen: room trials where the deaths are | dev (10 001+) | minutes per bot |
| `confirm` | the same trials, sequential, stops when decided | dev | until decided (Pocock, 5 looks) |
| `report` | full runs once, KM median and tier; whole-run leak check | holdout 1..400; leak 900 001+ | one full 400-seed run |

Bots: any yardstick bot (`-Mode list`), or `blind` = the BlindPlanner as
`rl review atlas` plays it, with knobs after a colon: `blind:fine=0`,
`blind:lines=4,wobble=2` (the same keys as `rl review atlas --fine 0`).

## Rules

1. **Size by deaths, not seeds.** The relative CI half-width of a death rate is
   about 1.96 / sqrt(deaths): 100 deaths give +-20%, 400 give +-10%. To see a
   rate ratio of 0.8 with 80% power takes about 315 deaths per arm; 0.9 about
   1 400. Seed pairing does not help (per-seed scores are uncorrelated).
2. **Tune on dev seeds, report on the holdout.** Dev seeds are 10 001 and up
   (the bank and every trial). The holdout 1..400 is played once per release
   candidate, by `report`. The leak check has its own seeds, 900 001 and up.
   Picking the best of k settings on the seeds you report inflates the winner by
   about sqrt(2 ln k) standard errors.
3. **Decide with a plan fixed in advance.** `confirm` looks five times and stops
   at the first look with |z| > 2.413 (Pocock: 5% overall). Don't add looks.
4. **Compare plateau rates** (deaths per 100 points from 40 on), not pooled rates
   across different caps.

## The room-stratified estimator (`quick`, `confirm`)

The rooms a run meets come from the spine, an RNG of their own, so how often each
room (and variant) comes up is a property of the game, not of the bot. The death
rate on the plateau is

```
Q = 100 * sum_s pi_s p_s / sum_s pi_s l_s      (deaths per 100 points)
```

with `s` a stratum (room/variant plus the score class: `@b0..@b30` below 40
points, `@t1..@t3` for a boss's tier, `@p` for the plateau), `pi_s` its share
of visits, `p_s` the chance to die in one visit and `l_s` the points a visit
gives.

- **The bank** (`*.bank.json`): full runs of the first bot on dev seeds, to
  400 points, with every room entry. It gives `pi_s` and the entry snapshots,
  and its visits are trials of that bot too.
- **A trial**: a bank entry snapshot (the state before the step that enters a
  room), the spine replaced by a new seed, the entry step played: a new room
  is drawn exactly as the game draws it (arrival checks, variant, hazards'
  seeds). Then the bot plays from there to the next room or its death. The
  trial counts for the stratum it landed in.
- **Neyman allocation**: trials go where they remove the most variance per
  CPU second, `n_s ~ pi_s sd_s / sqrt(cost_s)`. Deadly rooms get many, safe
  rooms a few (at least 3 for every stratum with 0.2% of visits or more; the
  rest take the bank's p, shown as `imputed`).
- **Paired arms**: in a comparison every bot plays the same trials (same
  snapshot, same spine seed, same bot seed). The covariance between the arms
  is used in the ratio's CI; `rho` is printed.
- **CI**: delta method on the ratio estimator, including the error in `pi`.
  A stratum's p for its variance is shrunk toward its own bank rate by 2
  pseudo-visits, so a stratum with no deaths yet is not certain (shrinking toward the
  trials' pooled rate instead was wrong: Neyman makes that the deadly rooms' rate).

### What it saves (measured 2026-11-12, gameplay 21, BlindPlanner `blind`)

Information = 1 / se² of the log rate (or log ratio); a plain death count gives one
unit per death, so full runs cost **216 CPU s per unit** here (the bank: 160 dev runs
to 400 points, 12 772 CPU s, 59 plateau deaths, ramp included).

| what | CPU s per unit of information | vs full runs |
|---|---|---|
| one bot, bank + Neyman trials (0.108 [0.089, 0.132]) | 142–169 | 1.3–1.5x |
| a second bot on the shared bank (trials only, `margin=10`) | 120 | 1.8x |
| a comparison, paired trials (`bpx=6` vs base, stopped at look 2) | see below | **3.1x** (2.3x with the bank) |
| a comparison, paired trials (`margin=10` vs base) | see below | RESULT_C2 |

- The Neyman gain alone is small, about 1.25x: BlindPlanner's 59 plateau deaths are
  spread over 118 strata, and no room dominates once each is weighed by how often it
  comes up (crates/wide has the highest p, 0.2 per visit, but is 0.7% of visits).
- The big gain is **pairing**: both bots play the same room trials (same snapshot,
  same spine, same bot seed), and their deaths correlate, rho 0.52 to 0.56. Whole runs
  are uncorrelated (rho 0, the measurement review) because paths diverge over many rooms;
  one room is short enough that the same draw is deadly for both. That about halves the
  variance of the ratio.
- Then **sequential stopping**: `bpx=6` stopped at look 2 of 5 (0.75 [0.61, 0.91],
  z -2.85), at half the planned information.
- `bpx=6` vs base, all costs: 34 294 CPU s of trials for information 95 on the log
  ratio. Full runs need 2 x 95 = 189 plateau deaths per arm at 216 s (base) and 350 s
  (`bpx=6`, 1.6x slower per tick): 107 000 CPU s.

### Validation against full runs

- Same bot, same gameplay: stratified 0.108 [0.089, 0.132] and 0.110 [0.096, 0.127]
  (two trial sets) against full runs 0.125 [0.095, 0.162] (the bank, dev seeds) and
  0.112 [0.100, 0.126] (the 400-seed atlas of the measurement review, an older build of
  gameplay 21). The intervals overlap; the stratified number is 10–14% lower, inside
  the noise of the full runs (+-27%).
- Late starts from 100 points (96 runs, `measure runs`): 0.161 [0.122, 0.209] over
  about 100..470 points, against the bank's 0.131 (160..320) and 0.154 (320+).
- The death rate is not flat on the "plateau": 0.11 per 100 at 40..80, 0.13 at
  160..320, 0.15–0.20 past 320 (boss tier 3, rooms unlocked up to 120). Compare bots
  on the same score range.

Caveats: a trial starts the bot fresh at the room entry (no memory of earlier
rooms), and the entry states come from the bank bot's runs, so another bot's
estimate uses the bank bot's way of leaving the previous room. Both are checked
by the validation against full runs below; re-check when a bot keeps memory
across rooms.

## Late starts for strong bots (`measure runs`)

```
fastsim measure runs --bank blind.bank.json --bot blind --from 100 --n 80
```

Runs that start from a bank entry at 40, 100 or 200 points (the first per bank
run), with the spine replaced so the rest of the run is new, and play to death
or the cap. They give the plateau rate and the survival curve past that score
without replaying the easy first rooms.

## Report: tiers and "infinite" (`report`)

`report` plays the holdout (1..400, the bots' cap, 216 000 ticks) once and gives:

- **Tier by the KM median with its CI.** A bot fits its tier when the median is
  within +-15% of the target (30 / 60 / 120 / 250) **and** the whole CI lies
  inside the tier's band (edges at the geometric middles: 42 / 85 / 173 / 354).
- **Beast**: the KM median is missing (half the runs reach the cap) or its CI is
  above 354. Reported by the plateau rate and the share alive at the cap.
- **Infinite** (the user's definition): every run that can be finished is
  finished. The fairness judge (`fastsim rl review fair`, on the same seeds
  and cap) is the oracle: a death it calls `bot` had an honest, visible-only
  line, so that run could be finished; `reaction`, `hidden` and `lost` deaths
  had none (a room to fix). `finishable.share` = alive at the cap / (alive +
  `bot` deaths), with a Wilson CI; `infinite` is true when no `bot` death is
  left. Pass the judge's output with `-Fair`.

## Leak check over whole runs (`report`, `leakrun`)

`measure leak`: the bot plays whole runs on seeds 900 001+ (to 400 points),
then the check forks them: 40 random bounces per run, every boss room (a bounce
30+ ticks in) and a sample of exit draws (the bounce before the exit preview).
At a fork two fresh copies of the bot play two sims that show the same screen:
A is real; B has every RNG and seed replaced (`BlindPlanner.blind_copy`) and
then, **deny by default**, every field the screen does not show copied from a
donor (the same room and variant drawn again from its entry with another spine,
flown with the same taps to the fork tick). A field is visible only when the
game's drawing code reads it: `tools/fastsim/Measure/visible.tsv`, built by
`fastsim measure visibility --write` from `game/run/*.gd` and the painters (a
method a painter calls counts by its result, so a tide's salt stays hidden while
its depth is shown). Fields are copied one at a time and kept only while the
screen stays the same. An honest bot taps the same in A and B until something
visible differs; an earlier difference is a leak.

The output gives the forks tested per room and per reason, the detection power
(a leak that changes 1 flight in 100, 200, 1 000) and
`hidden_but_kept_by_blind_copy`: hidden fields the bot's own blind copy keeps,
which the old check (it scrambled only blind_copy's list) could never test.
First run (BlindPlanner `blind`, 12 seeds, 775 forks, up to 390 points, 29 in boss
rooms): **5 leaks**, 3 of them from `SimState.anchor_y` (the room's anchor, ruled hidden:
track it from walls seen instead). The old check could not see it: blind_copy keeps
anchor_y, and the old check scrambled only blind_copy's list.

`fastsim check yardstick` calibrates it: the gap seeker must pass and
PlannerBot (it steps copies of the real sim) must leak, and visible.tsv must
match the drawing code.

## Files (for every port)

Everything is plain data, so the Rust port can write the same files and either
tool can read them. A state is never stored: it is rebuilt by replaying taps.

**Bank**, `*.bank.json`: `{"format": "flapjaw_bank", "version": 1,
"gameplay_version", "bot", "about", "cap", "point_cap", "first_seed", "seeds",
"runs": [...]}`. Each run: `seed`, `season`, `points`, `dead`, `ticks`, `room`,
`ms`, `taps` (the ticks with a tap), `visits`. Each visit is
`[tick, tap, score, stratum, end, points, ticks, ms]`: the state before the step
of `tick` (replay `new GameSim(seed, season)`, stepping `tap = taps contains
tick`) is the entry snapshot; `tap` is that step's input; `score` the score
after entering; `end` 0 = left the room, 1 = died, 2 = cut by the cap.

**Trials**, `*.trials.tsv` (`# flapjaw_trials 1 gameplay N`, then a header):
`bot kind seed tick k stratum died censored points ticks ms`. A trial is
defined by (seed, tick, k): rebuild the entry snapshot, set
`spine = new SimRng(spine_seed)`, step `tap`, then the bot (made with
`bot_seed`) plays to the next room (`kind` room) or to death/the cap (`kind`
run). With `mix(h, v) = ((h ^ (v & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF`
(SimHash.mix) and `SEED = 0x811C9DC5`:

```
spine_seed = mix(mix(mix(SEED, seed), tick), k)
bot_seed   = mix(spine_seed, 0x5EED)
```

`k = -1` marks a bank visit (real spine, real bot). Strata are
`room/variant@class` with the class `b0`/`b10`/`b20`/`b30` (entry score under
40, by tens), `t1`..`t3` (boss tier) or `p`.

**Fairness**, the text `rl review fair` prints: the death table with header
`seed score tick room cause verdict ...`.

**Visible list**, `visible.tsv`: `Class.field` or `Class.method()` and the file
that draws it.
