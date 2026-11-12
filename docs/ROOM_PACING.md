# Room pacing

How the next room is picked (`RoomCatalog.pick_next`) and how often each room comes up as the
score climbs. Code: `sim/rooms/room_pacing.gd` (RoomPacing) and `sim/rooms/room_catalog.gd`.
Page with the curve: https://claude.ai/artifact/AzyWMy11kN2qCpNmAPJa36

## Tiers and curves

Every room the picker can pick has a tier, set from its measured difficulty
(`fastsim difficulty`, docs/ROOM_DIFFICULTY.md: the mean score over its variants), not from its
group label. Data: `D:/SoftwareProjects/SpikeCage-coord/research/room-difficulty/` (2026-11-12 run)
and its `rerun-pacing/` (the 11 rooms room-fixes changed, measured again at next-features-2 2055eb8).
The tier gives the room a weight curve over the score (`RoomDef.pace`): score,
weight pairs, 0 before the first score (the unlock, `RoomDef.from_score`), straight integer lines
between the points, the last weight after the last point.

| Tier | Measured score | Curve (weight at score) |
|---|---|---|
| Easy | up to 32 | 10 at 10, 10 at 60, 1 at 150 |
| Steady | 32-40 | 6 at 20, 10 at 40, 10 at 100, 2 at 250 |
| Middle | 40-48 | 5 at 30, 10 at 60, 10 at 160, 4 at 400 |
| Hard | 48-56 | 4 at 50, 12 at 100, 14 at 200 |
| Harder | 56-63 | 4 at 70, 14 at 130, 18 at 250 |
| Hardest | over 63 | 4 at 90, 16 at 160, 20 at 300 |
| Bonus | bonus rooms | 3 from 20 |

Seasonal rooms (not bonus) take their tier's weights times 3/2 in their season. After a new
difficulty run, change the room's tier in `RoomPacing.TIERS` (and its port in
`tools/fastsim-rs/sim/src/rooms/room_pacing.rs`).

## The deck

`pick_next` is a shuffle bag kept in `SimState.deck_lo` / `deck_hi` (bit i: room i was drawn from
this bag; 62 rooms per word).

- A drawn room stays out until the bag refills. A room that unlocks meanwhile joins the bag.
- Among the rooms still in the bag, the pick is by weight at the current score.
- The bag refills once what is left weighs less than `DECK_REFILL_PCT` (25%) of all the rooms
  that could be picked; on a refill only the current room stays drawn. Light rooms (easy ones
  late in a run) so don't hold the bag open and bunch up at its end. With 0 the bag refills only
  when empty: every room once per bag, but the curve sags past 200 (light leftovers).
- Kept: never the current room, never Open, bosses only through `pick_boss` every 100, arrival
  height skips (`RoomDef.arrival_skip`, `state.anchor_y`). One spine RNG draw. Only the picks
  change the deck, so it is the same for every route and every player of a seed.

## Odds per score band

From `tools/room_odds.gd` (the real picker, 2000 runs, year-round rooms; old: the previous
picker, every room at its full weight once unlocked), mean measured difficulty of the picked
rooms and the share of each tier:

| Score | Picker | Mean difficulty | Easy | Steady | Middle | Hard | Harder | Hardest | Bonus |
|---|---|---|---|---|---|---|---|---|---|
| 10-19 | old | 34 | 50% | 16% | 34% | 0% | 0% | 0% | 0% |
|  | new | 26 | 100% | 0% | 0% | 0% | 0% | 0% | 0% |
| 20-49 | old | 38 | 27% | 25% | 19% | 9% | 11% | 2% | 7% |
|  | new | 32 | 35% | 43% | 13% | 0% | 0% | 0% | 9% |
| 50-99 | old | 41 | 22% | 20% | 19% | 11% | 15% | 7% | 6% |
|  | new | 39 | 17% | 32% | 21% | 16% | 7% | 1% | 6% |
| 100-199 | old | 42 | 20% | 24% | 16% | 14% | 13% | 7% | 5% |
|  | new | 48 | 3% | 19% | 17% | 22% | 21% | 12% | 6% |
| 200-299 | old | 42 | 20% | 24% | 17% | 15% | 13% | 6% | 5% |
|  | new | 50 | 3% | 9% | 16% | 26% | 25% | 13% | 7% |
| 300-499 | old | 42 | 20% | 24% | 16% | 15% | 13% | 7% | 5% |
|  | new | 49 | 5% | 11% | 14% | 27% | 23% | 12% | 8% |
| 500+ | old | 42 | 20% | 24% | 17% | 15% | 13% | 7% | 5% |
|  | new | 48 | 5% | 12% | 13% | 27% | 23% | 12% | 8% |

Per room, new picker, % of the picks in each band (`godot --headless --path . -s
res://tools/room_odds.gd -- 2000 -1 990` prints it):

| Room | Tier | Score | Unlock (was) | 10-19 | 20-49 | 50-99 | 100-199 | 200-299 | 300-499 | 500+ |
|---|---|---|---|---|---|---|---|---|---|---|
| lava | Easy | 16 | 10 (50) | 19.4 | 5.6 | 2.9 | 0.6 | 0.5 | 0.8 | 0.8 |
| cloud | Easy | 24 | 10 (10) | 11.7 | 6.5 | 3.1 | 0.5 | 0.5 | 0.8 | 0.8 |
| tide | Easy | 26 | 10 (10) | 19.1 | 5.1 | 2.7 | 0.5 | 0.5 | 0.7 | 0.8 |
| court | Easy | 28 | 10 (40) | 18.8 | 5.9 | 2.9 | 0.5 | 0.6 | 0.7 | 0.8 |
| crosswind | Easy | 31 | 10 (10) | 13.1 | 6.0 | 2.9 | 0.6 | 0.5 | 0.8 | 0.8 |
| crates | Easy | 32 | 10 (60) | 18.1 | 6.0 | 2.7 | 0.6 | 0.5 | 0.7 | 0.8 |
| piston | Steady | 32 | 20 (30) | - | 5.8 | 4.1 | 2.4 | 1.2 | 1.5 | 1.6 |
| belt | Steady | 33 | 20 (20) | - | 5.0 | 4.4 | 2.5 | 1.2 | 1.5 | 1.6 |
| crawl | Steady | 34 | 20 (30) | - | 4.5 | 3.6 | 2.2 | 1.2 | 1.2 | 1.3 |
| hunter | Steady | 37 | 20 (80) | - | 5.8 | 4.2 | 2.3 | 1.2 | 1.5 | 1.6 |
| crowded | Steady | 38 | 20 (10) | - | 6.0 | 4.1 | 2.3 | 1.1 | 1.5 | 1.5 |
| echo | Steady | 39 | 20 (80) | - | 4.5 | 3.3 | 2.4 | 1.1 | 1.1 | 1.2 |
| flip | Steady | 39 | 20 (90) | - | 6.0 | 4.1 | 2.2 | 1.2 | 1.4 | 1.6 |
| blink | Steady | 40 | 20 (80) | - | 5.4 | 4.1 | 2.3 | 1.2 | 1.4 | 1.5 |
| lockexit | Middle | 41 | 30 (40) | - | 2.6 | 4.3 | 3.4 | 3.1 | 2.7 | 2.7 |
| isles | Middle | 41 | 30 (10) | - | 2.6 | 4.5 | 3.3 | 3.3 | 2.8 | 2.8 |
| stalker | Middle | 42 | 30 (40) | - | 2.2 | 4.5 | 3.6 | 3.2 | 2.8 | 2.6 |
| bubbles | Middle | 45 | 30 (50) | - | 2.2 | 3.7 | 3.1 | 3.0 | 2.5 | 2.4 |
| narrow | Middle | 47 | 30 (10) | - | 2.9 | 4.2 | 3.4 | 3.1 | 2.9 | 2.6 |
| rain | Hard | 49 | 50 (70) | - | - | 3.4 | 4.6 | 5.3 | 5.4 | 5.4 |
| gates | Hard | 51 | 50 (20) | - | - | 2.8 | 3.7 | 5.0 | 4.9 | 4.9 |
| midnight | Hard | 52 | 50 (100) | - | - | 3.1 | 4.6 | 5.5 | 5.4 | 5.4 |
| sawring | Hard | 54 | 50 (80) | - | - | 3.3 | 4.9 | 5.0 | 5.4 | 5.5 |
| squeeze | Hard | 56 | 50 (50) | - | - | 3.7 | 4.5 | 5.2 | 5.7 | 5.4 |
| bramble | Harder | 56 | 70 (40) | - | - | 1.9 | 5.6 | 6.2 | 6.0 | 5.8 |
| swing | Harder | 57 | 70 (30) | - | - | 1.7 | 5.5 | 6.3 | 6.0 | 5.8 |
| stalac | Harder | 60 | 70 (30) | - | - | 1.4 | 5.0 | 6.1 | 5.5 | 5.5 |
| beams | Harder | 61 | 70 (50) | - | - | 1.9 | 5.3 | 6.3 | 5.8 | 5.9 |
| pinwheel | Hardest | 65 | 90 (40) | - | - | 0.4 | 5.7 | 6.8 | 6.2 | 6.0 |
| updraft | Hardest | 74 | 90 (60) | - | - | 0.4 | 5.8 | 6.7 | 6.2 | 6.0 |
| slowmo | Bonus | 9 | 20 (60) | - | 2.2 | 1.4 | 1.4 | 2.0 | 1.9 | 2.2 |
| keepy | Bonus | 10 | 20 (40) | - | 2.5 | 1.2 | 1.5 | 1.8 | 2.2 | 2.1 |
| orchard | Bonus | 12 | 20 (30) | - | 2.3 | 1.4 | 1.4 | 1.8 | 2.1 | 2.2 |
| garden | Bonus | 19 | 20 (20) | - | 2.4 | 1.5 | 1.5 | 1.9 | 2.0 | 2.1 |
