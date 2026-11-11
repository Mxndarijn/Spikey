# The MPC bot

A playtest bot that plans its taps and never uses the future of the run. It
is the simple baseline among the bots: the bird's own movement is exact,
everything else is moved on from what has been on screen. It is a tool only
(`tools/fastsim/Mpc/`, run by `tools/mpcbot.ps1`). It never changes `sim/` or
gameplay.

The idea follows the research notes (Piper et al. 2017, Flappy Bird as model
predictive control; Baumgarten's A* Mario; velocity-obstacle dodging): plan
over your own physics and the visible obstacles, do the first action, plan
again next tick.

## The rule: no future

The bot reads the present sim state and nothing else. It never calls
`clone_deep`, `step` or `revive` on the `GameSim`, never touches the RNG and
never builds a second sim. The `mpcbot` check (`tools/fastsim/Mpc/MpcCheck.cs`,
part of `tools/check.ps1`) holds this two ways:

- it scans the bot's source for those calls (only `MpcRun.cs`, which plays the
  bot's taps on the real run, may step the sim);
- in every room variant it compares the sim's checksum before and after each
  decision.

## How it sees (`Sight.cs`)

Every tick, for each live hazard:

1. **Kill grid.** The bird is moved to a grid of points (8 px cells, a coarse
   16 px pass first, fine cells only near hits), the hazard's `kills()` is
   asked, and the bird is put back. The result is the set of places where the
   bird would die of that hazard right now. Two hazards that never kill but
   move the bird (the cloud bumper, a carrying bubble) are seen the same way
   with a touch test, as bodies.
2. **Shapes.** Touched cells are split into connected shapes. Each shape gets
   its box, with the four edges found to 1/8 px by bisection.
3. **Motion.** Each edge has its own speed: a least-squares line through its
   sightings of the last 10 steps. A shape that slides moves all four edges
   alike. A shape that grows (a gate half, a piston) moves one edge. An edge
   at the screen border counts as off screen, not as standing still.
4. **Three things learned while watching**, each from sightings only:
   - *It follows me.* A shape that moved toward the bird's height in at least
     85% of 30 samples is a follower (the stalker), with the speed it showed.
   - *It goes away.* When a hazard's last two shapes each stayed the same
     number of steps (a beam's on time, a piston's stroke), the next one is
     expected to stay that long too.
   - *It lifts me.* When the bird's speed differs from its own movement by a
     small steady amount, that lift is remembered per column of the room (an
     updraft).
5. **Warnings.** The glow of a piston and the charging line of a beam are on
   screen before they strike. The bot reads them as a box that will be deadly
   from a number of steps on, for a number of steps. This is the only place
   with per-hazard code (two hazards), and it reads only what is drawn.

## How it plans (`Planner.cs`)

- **The bird is exact:** gravity, flap, the room's speed (fast and slow
  rooms), flipped gravity, the wall bounce and the exit. The bird's x does
  not depend on taps, so it is worked out once per plan.
- **The wall ahead is exact for now:** the sim's own spike triangle test on
  the mask, depth and shift as they are this tick. The wall after the bounce
  is not known yet, so nothing is assumed about it.
- **Hazards are guesses:** at step `j` ahead a shape's box is its edges moved
  on by `j` steps, and the present cells are stretched into that box. A
  margin grows with `j` (`m0 + grow * j`, more for a shape whose speed keeps
  changing). The inner part of the margin kills the plan, the rest costs. A
  follower's position is carried along each planned line, so the plan can
  lure it one way and dash the other.
- **The search:** a beam over (height, speed) buckets, one layer per tick,
  tap or no tap. The horizon runs to the next wall bounce and on to the far
  wall (up to 170 steps). The cheapest surviving line wins; its first action
  is played. If every line dies, the bot plays the longest-lived one.
- **Cost:** taps, being near a predicted shape, landing close to a spike,
  being near the floor or ceiling, and ending far from the middle (or from
  the exit when it is shown).

## Human hands (`MpcBot.cs`, `Motor`)

After Isaksen, Gopstein and Nealen (2015), measured on Flappy Bird players:

| knob | meaning | human value |
|---|---|---|
| `-Sigma` | each tap lands a Gaussian number of ticks early or late | 2.2 to 3.7 ticks (36 to 61 ms) |
| `-React` | a new wall layout or a new shape is not acted on for this many ticks | 17 ticks (288 ms) |
| `-MinGap` | fewest ticks between taps | 8 ticks (7.5 taps a second) |

The hand commits to a planned tap a few ticks ahead and lands it with the
timing error, whatever the plan says in between.

## Using it

    powershell -ExecutionPolicy Bypass -File tools/mpcbot.ps1                       # 400 full runs
    powershell -ExecutionPolicy Bypass -File tools/mpcbot.ps1 -Sigma 3 -React 17 -MinGap 8
    powershell -ExecutionPolicy Bypass -File tools/mpcbot.ps1 -Room stalker -Seeds 24 -Cap 3600
    powershell -ExecutionPolicy Bypass -File tools/mpcbot.ps1 -Set "grow=0.2,soft=10"   # planner knobs
    tools/fastsim/bin/Release/net9.0/FastSim mpc trace --room beams --seed 3 --last 60  # the last ticks before a death

Runs use the same seeds (1..n) and tick cap as `tools/rlbot.ps1 -Mode measure`,
so the numbers compare.

## Results

See `tools/mpcbot/RESULTS.md` for the measured numbers and what was learned
about each hazard.
