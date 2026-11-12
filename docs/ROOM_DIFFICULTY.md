# Room difficulty

`fastsim difficulty` gives every room, variant and boss a difficulty score, so rooms can be
ranked, the ones that are too hard or too easy for their group found, and each placed in a
category. Code: `tools/fastsim/Difficulty/`. It only reads the sim; it changes no gameplay.

```
powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode difficulty -Step list
powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode difficulty -Room gates,hunter/twin -Seeds 16 -Jobs 8 -Out d.tsv
powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode difficulty -Step score -In d.tsv -Out report
powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode difficulty -Step show -Room gates/classic -Seed 0
```

`measure` plays `-Seeds` room entries per room (default 16) for each measure in `-What`
(`tube,react,bots`) and appends one TSV row per (measure, room, entry, bot) to `-Out`. Rows
already in the file are not played again, so a stopped run carries on and new rooms can be
added to an old file. `score` reads one or more TSVs and writes `report.md` (the ranked table)
and `report.json` (everything, for pages). `show` prints one entry's tube tick by tick.

Take a CPU slot for `measure` (VARIANT_RULES.md). Rough cost per room entry: tube 1-4 s,
react 1-10 s, bots 2-4 s per tier (expert and beast 8-40 s).

## Room entries

Every measure starts from the same entries: a portal arrival as in a real run
(`Reaction.arrival`), heights spread over the screen, both sides, three scores and layout seeds,
at a height the game would bring that variant in at. Boss rooms come in through the boss portal
at 100 (as `BossRuns.arrive`). An entry ends when the bird goes through the exit (in a boss
room: when the boss is down), dies, or runs past the room's cap (`Passable.CASES` ticks + 450).

## The measures

### 1. Bots: who clears the room

Each human-like tier (beginner, normal, good, expert, beast: `MotorPlayer` on BlindPlanner,
docs/HUMAN_BOT.md) and the honest BlindPlanner play every entry. A clear is a room left alive.

An item-response (Rasch) fit over all clears gives every bot a skill and every room a
difficulty `b`: P(clear) = 1 / (1 + e^-(skill - b)). The skill a room needs for 90% clears is
`b + ln 9`, read on a tier scale that is linear through beginner = 1 and good = 3. **Skill
score = 20 x that**: 20 means a beginner clears it 9 times in 10, 40 a normal player (normal
lands there by itself, so the scale is linear), 60 a good player. Expert and beast clear little
more than good in a single room (their edge is in long runs), so they land just above 60 (about
66 and 71 on the 2026-11-12 run); a room above about 70 needs more than any bot tier has. The fit uses every tier at once, so a room that every bot clears still
gets a sensible number, and noise in one tier is smoothed by the others.

### 2. The tube: every way through (exact knowledge)

A breadth-first search from the entry over real sim copies, one tick at a time, keeping one copy
per bucket of bird state (4 px height, 1/8 flap of vertical speed, 40 px x, direction). Unlike
SurvivalSearch it keeps every bucket, and records where each copy's tap and no-tap step landed.
A backward pass marks the **viable** copies: those with a line that still reaches the exit.
An entry where none is viable is checked again with SurvivalSearch (finer buckets): only when it
finds no way either does the entry count as `no-way` (otherwise `no-way?` in old files).
Taps follow SurvivalSearch's rule (only once the last flap has half worn off).

- **Free band** (px): how many px of bird heights are still viable at a tick. Measured from
  1.5 s after the arrival hold to 40 ticks before the first exit (the tube fans out of the portal
  and funnels into the exit). `band_p10` is the 10th percentile over those ticks, `band_min` the
  narrowest moment (the bottleneck), `tight_s` the seconds under 60 px.
- **Ways** (`bits_per_point`): log2 of the number of viable tap sequences (paths through the
  bucket graph), per point. How much freedom the room leaves.
- **Tap window** (ticks): for a tap, the run of neighbouring ticks (no tap in between) at which
  the tap still leads through. The **most forgiving line** is the line whose tightest tap window
  is widest (maximin over the graph); `window` is that tightest window (capped at 30), and
  `tight_taps_per_s` its taps with a window of 3 ticks or less, per second.
- **Route choice** (`choice_frac`): the part of the room where the viable heights form two or
  more groups at least 24 px apart (over or under something).

Bucketing merges near-equal states (one copy per bucket, the better one by room, score and
coins), so counts are of buckets, not exact states.

### 3. Reaction: how fast you must react

The boss review's fairness sweep (`BossRuns.fair`) for every room. The honest planner plays the
entry. Each time something new shows (new spikes on the wall ahead, a hazard appearing, a boss
tell), the bird keeps the plan it had before for R = 0, 20, 40, 60 ticks, then SurvivalSearch
(exact knowledge) looks for a way to live until the next new thing plus 1 s.

- `fail20/40/60`: of the new things with a way at R = 0, the share with no way (or a death in the
  old plan) at R. More than 2% (`Reaction.MAX_EXTRA_PCT`, at least 2 cases) means new things often leave
  no way through for a player who reacts in a third of a second: **unfair** at a human reaction.
- `doomed0`: the share already without a way at R = 0 (the planner's own mistakes, or a room that
  dooms the bird before it shows what will kill it).
- Holding the old plan for 60 ticks right after a bounce leaves only ~20 ticks before the next
  wall, so even Open Sky fails some new walls at R = 60. Compare with the starter rooms.

## The score

- **Skill**: the bot score above.
- **Analytic**: a ridge regression of the bot skill on the tube and reaction measures
  (standardised, logs of the px and tick measures), checked leave-one-out. It is the score the
  analytic measures alone would give.
- **Score** = the mean of skill and analytic, on the same scale (clamped to 0..130).
- **Sub-scores** (0-100, rank among all rooms scored, 100 hardest): space (band), precision (tap
  windows), reaction (fail rates), busy (new things per second, route choice, few ways).

## Categories and flags

- **Bands** on the tier scale: starter up to 40 (a normal player clears it 9 times in 10), mid
  up to 60 (a good player), late above. The report also gives the two cut points that would
  agree best with today's groups (degenerate when today's late rooms are no harder than the mid
  ones). Bonus, seasonal and boss rooms are placed by the same bands but keep their group.
- Flags: `no-way` (an entry with no way through even with exact knowledge), `unfair-react`
  (`fail20` over 2%, at least 2 cases), `slow-react` (`fail40` over twice the 90th percentile of the starter rooms),
  `too-hard` / `too-easy` (the band says a later / earlier group than today's; bonus and seasonal
  rooms above the mid band; bosses below the starter band).

Recategorising is the user's call: the tool only suggests.

## Results

The run of 2026-11-12 (next-features-2 at 5354aac): `D:\SoftwareProjects\SpikeCage-coord\research\room-difficulty\`
(README.md, the TSVs and report.md/json). Page: https://claude.ai/artifact/LReB6JtzyrC3nSqag71kCD

- Best single predictors of the bot skill (Spearman): viable share of reachable states -0.75,
  tap window -0.70, ways through per point -0.66, route choice +0.63, free band about -0.55,
  fail at 0.67 s +0.60. Together, leave-one-out r = 0.81.
- A tube "no way" is checked with SurvivalSearch: on that run 6 of 10 were confirmed, the other 4
  were ways the bucket merging lost.
