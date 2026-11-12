# Room pacing

How the next room is picked (`RoomCatalog.pick_next`) and how often each room comes up as the
score climbs. Code: `sim/rooms/room_pacing.gd` (RoomPacing) and `sim/rooms/room_catalog.gd`.
Page with the curve: https://claude.ai/artifact/AzyWMy11kN2qCpNmAPJa36

## Tiers and curves

Every room the picker can pick has a tier, set from its measured difficulty
(`fastsim difficulty`, docs/ROOM_DIFFICULTY.md: the mean score over its variants), not from its
group label. The tier gives the room a weight curve over the score (`RoomDef.pace`): score,
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
`tools/fastsim/Sim/Rooms/RoomPacing.cs`).

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
| 10-19 | old | 33 | 50% | 16% | 34% | 0% | 0% | 0% | 0% |
|  | new | 25 | 100% | 0% | 0% | 0% | 0% | 0% | 0% |
| 20-49 | old | 37 | 27% | 27% | 18% | 20% | 0% | 2% | 7% |
|  | new | 32 | 29% | 48% | 14% | 0% | 0% | 0% | 9% |
| 50-99 | old | 40 | 19% | 23% | 19% | 21% | 7% | 4% | 6% |
|  | new | 40 | 12% | 33% | 24% | 23% | 3% | 0% | 5% |
| 100-199 | old | 40 | 17% | 27% | 19% | 22% | 7% | 3% | 5% |
|  | new | 46 | 3% | 21% | 20% | 35% | 11% | 5% | 6% |
| 200-299 | old | 41 | 17% | 27% | 19% | 22% | 7% | 3% | 5% |
|  | new | 47 | 2% | 11% | 19% | 41% | 12% | 7% | 8% |
| 300-499 | old | 41 | 16% | 27% | 19% | 22% | 7% | 3% | 5% |
|  | new | 46 | 4% | 13% | 16% | 41% | 11% | 6% | 8% |
| 500+ | old | 41 | 17% | 27% | 19% | 22% | 7% | 3% | 5% |
|  | new | 46 | 4% | 14% | 16% | 41% | 11% | 6% | 9% |

Per room, new picker, % of the picks in each band (`godot --headless --path . -s
res://tools/room_odds.gd -- 2000 -1 990` prints it):

| Room | Tier | Score | Unlock (was) | 10-19 | 20-49 | 50-99 | 100-199 | 200-299 | 300-499 | 500+ |
|---|---|---|---|---|---|---|---|---|---|---|
| lava | Easy | 16 | 10 (50) | 20.2 | 5.6 | 2.4 | 0.5 | 0.4 | 0.8 | 0.9 |
| cloud | Easy | 25 | 10 (10) | 21.1 | 5.7 | 2.4 | 0.5 | 0.5 | 0.8 | 0.8 |
| tide | Easy | 25 | 10 (10) | 19.9 | 5.9 | 2.4 | 0.5 | 0.5 | 0.7 | 0.8 |
| crosswind | Easy | 29 | 10 (10) | 19.6 | 6.0 | 2.4 | 0.6 | 0.5 | 0.8 | 0.8 |
| court | Easy | 31 | 10 (40) | 19.3 | 6.0 | 2.2 | 0.5 | 0.5 | 0.8 | 0.9 |
| belt | Steady | 33 | 20 (20) | - | 5.5 | 3.5 | 2.3 | 1.3 | 1.4 | 1.6 |
| piston | Steady | 33 | 20 (30) | - | 5.5 | 3.7 | 2.4 | 1.2 | 1.4 | 1.6 |
| crawl | Steady | 33 | 20 (30) | - | 4.9 | 3.6 | 2.2 | 1.1 | 1.3 | 1.3 |
| hunter | Steady | 36 | 20 (80) | - | 5.6 | 4.0 | 2.4 | 1.1 | 1.5 | 1.6 |
| crowded | Steady | 37 | 20 (10) | - | 5.3 | 3.7 | 2.5 | 1.2 | 1.7 | 1.6 |
| echo | Steady | 38 | 20 (80) | - | 4.8 | 3.1 | 2.1 | 1.1 | 1.2 | 1.3 |
| blink | Steady | 39 | 20 (80) | - | 5.7 | 3.5 | 2.2 | 1.2 | 1.5 | 1.6 |
| flip | Steady | 40 | 20 (90) | - | 5.3 | 3.9 | 2.3 | 1.3 | 1.5 | 1.5 |
| lockexit | Steady | 40 | 20 (40) | - | 5.2 | 3.6 | 2.4 | 1.2 | 1.4 | 1.6 |
| isles | Middle | 42 | 30 (10) | - | 2.2 | 4.0 | 3.4 | 3.2 | 2.9 | 2.6 |
| stalker | Middle | 42 | 30 (40) | - | 2.0 | 4.0 | 3.4 | 3.0 | 2.7 | 2.7 |
| narrow | Middle | 43 | 30 (10) | - | 2.6 | 4.1 | 3.2 | 3.1 | 2.8 | 2.8 |
| midnight | Middle | 43 | 30 (100) | - | 2.2 | 4.0 | 3.3 | 3.2 | 2.9 | 2.7 |
| bubbles | Middle | 45 | 30 (50) | - | 2.5 | 3.6 | 3.0 | 3.0 | 2.4 | 2.4 |
| beams | Middle | 46 | 30 (50) | - | 2.3 | 4.1 | 3.3 | 3.3 | 2.7 | 2.7 |
| rain | Hard | 49 | 50 (70) | - | - | 3.1 | 4.3 | 5.4 | 5.4 | 5.2 |
| stalac | Hard | 51 | 50 (30) | - | - | 2.7 | 4.2 | 4.9 | 4.9 | 4.9 |
| gates | Hard | 52 | 50 (20) | - | - | 2.4 | 3.9 | 4.8 | 4.8 | 4.7 |
| swing | Hard | 52 | 50 (30) | - | - | 2.9 | 4.6 | 5.2 | 5.3 | 5.2 |
| bramble | Hard | 54 | 50 (40) | - | - | 3.1 | 4.6 | 5.2 | 5.1 | 5.3 |
| crates | Hard | 54 | 50 (60) | - | - | 2.8 | 4.5 | 5.4 | 5.2 | 5.2 |
| sawring | Hard | 55 | 50 (80) | - | - | 3.1 | 4.5 | 5.2 | 5.3 | 5.2 |
| updraft | Harder | 57 | 70 (60) | - | - | 1.6 | 5.3 | 6.1 | 5.7 | 5.5 |
| squeeze | Harder | 60 | 70 (50) | - | - | 1.6 | 5.2 | 6.3 | 5.7 | 5.5 |
| pinwheel | Hardest | 66 | 90 (40) | - | - | 0.5 | 5.3 | 6.9 | 5.8 | 5.6 |
| slowmo | Bonus | 7 | 20 (60) | - | 2.4 | 1.4 | 1.5 | 1.9 | 2.1 | 2.2 |
| keepy | Bonus | 9 | 20 (40) | - | 2.2 | 1.2 | 1.6 | 1.8 | 2.1 | 2.2 |
| orchard | Bonus | 11 | 20 (30) | - | 2.7 | 1.1 | 1.4 | 1.7 | 2.0 | 2.2 |
| garden | Bonus | 19 | 20 (20) | - | 1.9 | 1.1 | 1.3 | 2.2 | 2.0 | 2.1 |
