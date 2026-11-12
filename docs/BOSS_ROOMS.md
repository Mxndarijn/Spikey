# Boss rooms (proposal, not built)

Mockups: https://claude.ai/artifact/KeMLFRj1umxk91DJnt21ci (source:
`docs/mockups/boss_rooms.html`, everything drawn in the page itself).
Nothing in `sim/` or `game/` changes until the user picks.

## Rules

- **Start.** The exit at 100, 200, 300, ... leads into a boss room. It is
  planned on the 99th point like any exit and its ghost carries a BOSS tag.
  Out of it the room holds 1.5 s (a `BOSS_HOLD` of 90 ticks instead of
  `PORTAL_HOLD`, taps ignored) while the boss comes in. The first tell starts
  no sooner than `ARRIVAL_BLIND` after the bird can move.
- **Length.** 20 bounces (100 to 120, about 23 s: a crossing is 70 ticks). Each
  bounce takes one pip off a 20-pip boss bar. Phases change at 7 and 14
  bounces, with one crossing of stagger (no new attack) between phases. No
  exit at 110.
- **End.** At 120 the boss breaks and its hazards stop, so the last crossing is
  free. The exit (planned on the 119th point) opens on the wall ahead. Reward:
  coins (15 / 20 / 25 from tier 3) and a first-clear trophy. Cosmetic money
  only; the score stays bounces.
- **Tiers** (score / 100). 1: one attack at a time. 2: phase 3 runs two attacks
  together (Double Trouble combo rules), shorter rests, +1 wall spike. 3+: each
  boss's rage variant, +2 wall spikes. Fixed for every tier: tells of 60 ticks
  or more, a free band of 120 px or more, 20 bounces. 3 wall spikes per wall at
  tier 1.
- **Forks.** If Calm/Wild stays, 100 and 200 get one boss portal and the boss
  exit (120, 220) is the fork. If forks go, the boss exit is one portal.
- **Death and revive.** Normal death. A revive restarts the room as entered
  (revive-reset): score 100, full bar, coins as at entry, same clock. No phase
  checkpoints.
- **Fairness.** The bird only chooses its height, so every safe line is a
  height band and every tell says which heights. A FastSim check per boss and
  tier (simple players must live through every phase, like `ArrivalCheck`).
- **Same seed.** Speed across is fixed, so every player bounces on the same
  ticks and the boss clock runs on room steps: same phases and tells for
  everyone. Lanes and columns come from the room seed; aimed attacks read the
  bird's height when the tell starts (as Hunter Spike). Which boss comes is a
  spine draw from those not met yet in the run.

## Bosses

| Boss | Built from | Phase 1 | Phase 2 | Phase 3 |
| --- | --- | --- | --- | --- |
| The Watcher | Beam Gates, Hunter Spike | 3 of 7 beam rows fire | gaze: dart along your marked height | 2 rows + gaze |
| The Crusher | Piston, Lava Rise, Crate Drop | press slams to 250/320 px | jaw: press + floor plate leave a moving 230 px lane | jaw + crate through the lane |
| Saw King | Saw Ring, Pinwheel, Bramble Ball | hops between 3 heights | blade ring swings out, safe band top or bottom | hops with a blade ring |
| The Gatekeeper | Shutter Gates, Ghost Doors | one gate, its 110 px gap jumps each cycle | two gates, gaps up to 60 px apart | three gates, gaps in 40 px steps |
| The Shade | Echo, Hunter Spike | a shadow flies your path 1 s behind | the Shade swoops wall to wall along a marked height | echo + mirror shadow |

Each tell is at least 1 s: dashed lines, rings or columns in the spike colour
(the one danger colour), flickering. The Gatekeeper's gaps only snap to
their new height while the bird is out by a wall, never between the gates.

## Open questions

1. Which bosses first (suggested: The Watcher and The Crusher, then The
   Gatekeeper and The Shade, then Saw King). Spike Serpent was dropped by the
   user.
2. 20 bounces or 10.
3. Reward size and whether a boss-only cosmetic joins it.
4. Fork placement (depends on fork-choice); with option A forks sit at 120
   and 150.
5. Seeded boss order or a fixed order.
6. Full restart on revive or a phase checkpoint.
7. 3 wall spikes per wall at tier 1.
