# MPC bot: results

All on full runs, seeds 1..400, cap 108000 ticks (`SimConfig.MAX_TICKS`), no
revives: the same as `tools/rlbot.ps1 -Mode measure`. The bot uses **no sim
copies**. No run reached the cap in any row. Measured 2026-11-11 on gameplay
version 21.

## Without noise, version by version

| version | what changed | median | p90 | p25 | max |
|---|---|---|---|---|---|
| v1 | kill grid per hazard, centroid motion, horizon = next wall + 30 steps | 52.5 | 90 | 36 | 230 |
| v2 | connected shapes with four tracked edges; bumper and bubbles seen by a touch test | 61.5 | 120 | 44 | 259 |
| v3 | horizon to the far wall; piston and beam warnings; follower model (stalker) | 71 | 131 | 56 | 307 |
| v4 | on-time memory (beams, piston strokes); updraft and wind read from the present state | 74 | 143 | 57 | 339 |

v4, deaths per 100 points: 1.16 overall. By score: 0..10: 0.00, 10..20: 0.00,
20..40: 0.51, 40..80: 1.61, 80..160: 2.43, 160+: 1.90. Taps: 1.37 a second.

For comparison: the RL bot's best median was 30 to 55. The planner on sim
copies with scrambled RNG (bot review) is near a median of 240.

## With human hands (v4 planner)

`-React 17 -MinGap 8` in every noise row (Isaksen et al.: 288 ms, 7.7 taps a second).

| tap timing sigma (ticks) | median | p90 | p25 | max | deaths per 100 points |
|---|---|---|---|---|---|
| 0, no reaction time, no tap cap | 74 | 143 | 57 | 339 | 1.16 |
| 0 | 60 | 103 | 40 | 189 | 1.60 |
| 1 | 40 | 75 | 30 | 211 | 2.20 |
| 2 | 30 | 58 | 18 | 120 | 3.28 |
| 3 | 18 | 40 | 10 | 80 | 4.92 |
| 4 | 10 | 31 | 7 | 51 | 6.87 |

- Timing error is the main skill knob, as Isaksen found: each tick of sigma
  costs about a third of the score. Reaction time and the tap cap together
  cost 74 -> 60.
- Sigma 3 alone (no reaction time, no cap): median 22. So at sigma 3 the
  reaction time and the cap cost only 22 -> 18.
- Letting the planner leave room for its shaky hands (land further from
  spikes, avoid taps that change the speed a lot) did nothing measurable at
  sigma 3: median 18 with and without, 4.92 against 5.00 deaths per 100 points.
- With noise, 80 to 95% of deaths are wall spikes: the last tap before the
  wall lands a few ticks off.

## What is left (v4, 400 deaths)

Causes: hazard 48%, spikes 36%, ceiling 16%. In 92% of deaths the planner had
no living plan a median of 27 ticks before the end: it sees the trap, but too
late to get out.

Killers: crate 38, drop 31, bouncer 25, stalactite 24, rotor 20, pendulum 16,
piston 13, beam 8, dart 7. Rooms: stalac/classic 26, crates (all) 45,
piston/ladder 18, beams 17, pinwheel (all) about 40, bramble (all) about 38,
swing (all) about 38, blink 20, orchard 12.

## What breaks "kill tests + straight lines"

Practice-room medians (24 seeds, 3600 ticks, at most 40 points):

| problem | rooms | fix | effect |
|---|---|---|---|
| a shape that grows from one side has a centroid that moves wrong | gates, pistons | track each box edge on its own | gates/classic: top killer -> 24 of 24 survive |
| horizon ends before the next obstacle past the bounce | gates/single-small | plan on to the far wall | 6 -> 40 |
| warnings are not in `kills()` | piston, beam | read the glow as "deadly from N steps on" | piston/classic 4 -> 40, double-slam 15 -> 40, beams 2 -> 14 |
| a shape that is on for a fixed time looks permanent | beams, piston/ladder | learn how long the last two stayed | beams 14 -> 26, ladder 8 -> 18 |
| a shape that follows the bird | stalker | learn "it moves toward my height", carry its place along each planned line | 11 -> 40 |
| bodies that never kill | cloud (bumper), bubbles | touch test, cost instead of death | cloud/two: 23 of 24 survive |
| forces on the bird | updraft, crosswind | read column, lift, bands and push from the present state | updraft/chimney 1.5 -> 40, twin 1 -> 40, drift 4.5 -> 40, gust 11.5 -> 38.5 |
| accelerating fallers | crates, drops | none found | crates/wide stays at 7 to 10 |

Tried and dropped:

- A least-squares parabola per edge (constant acceleration): worse in 5 of 6
  rooms. It overshoots whenever a shape changes speed (stalker 11 -> 4,
  stalac 6 -> 2).
- Widening a shape the way it moves by its observed speed changes: worse too
  (stalker 11 -> 3.5, pinwheel 10 -> 7.5).
- Making the margins harder or softer: no effect on the rooms tested.

The lesson for the simple approach: being more careful about a hazard's
future does not help. A wider guess closes the gaps the bird needs, the
planner finds no living plan and falls back to a poor one. What helps is
knowing more (the warning, the on-time, the follower rule), not fearing more.
The remaining killers all need the hazard's real motion rule: gravity and
wall bounces (crates, drops, bouncers), rotation (pinwheel, swing), the gap
retargeting at a bounce (stalactites).

## Files

- `tools/mpcbot/v3.json`, `v4.json`: every run of those measurements (seed,
  points, ticks, room, cause, killer).
- Video of the best v4 run (seed 223, 339 points), with its run file:
  `D:\SoftwareProjects\SpikeCage-coord\renders\mpc-best-seed223-score339.mp4`.
  The Godot game replays the run file to the same score and checksum.
