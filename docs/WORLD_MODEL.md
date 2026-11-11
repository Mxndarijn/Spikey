# World model: structured inputs for bots, and a planner on them

A playtest tool (`tools/fastsim/World/`, run as `fastsim world ...`). It reads
the present FastSim state once per tick and describes it as objects and
maths, so a bot plays from what a practised player knows: where everything
is now and how each thing moves. It never runs the game forward. It is a
tool only: it never changes `sim/` or gameplay.

## Why

The RL bot's input (`RL/Observer.cs`) is mostly a 7x9 "would I die here"
grid plus the same grid 6 ticks earlier: a tiny picture. The network has to
discover saws, motion and speed by itself. The strong search bots
(`PlannerBot`, `SurvivalSearch`) copy the sim (`clone_deep()`) and step the
copies, so they see the future, including RNG draws. The world model is the
middle ground: exact about the bird, exact about every hazard whose motion
follows from what is visible, and honest about what is hidden.

## What the model holds (`WorldModel.Read(sim, memory)`)

| part | content |
|---|---|
| bird | x, y, vx, vy, direction, gravity sign, radius (one shared hitbox) |
| own path | exact: `BirdPath.AtWall(w, t)` = where the bird reaches the wall ahead (height, ticks, lives or which death) for wait, tap now, tap at tick t |
| room (`RoomModel`) | room and variant id, speed (normal/fast/slow, substeps per tick), gravity and flip-flop, insets (squeeze, breathe), tide and blink walls, spike size, points, score, clock |
| wall ahead | spike slots (`Mask`), belt shift, the gaps as height bands (`WorldDesc.Gaps`), ticks to contact, the exit (heights, kinds, locked), the exit preview for the wall after; the wall after that is not drawn until the bounce |
| hazards | one model per hazard (`ModelsMotion.cs`, `ModelsTimed.cs`): its bodies (circle, rectangle or triangle; deadly or not), its motion rule with parameters (`Motion`, `Params`), its state (`State`: warning, active, retracting...), pushes on the bird (`Touch`: wind, updrafts, bumpers, bubbles; `Guard`: edge pads) |

`WorldModel.Tick(tap)` advances the model one tick in the game's own step
order (hazards, fall, spikes, hazard kills, pushes, walls, ceiling and
floor), so a model copy predicts the bird's exact path for any taps and every
hazard by its rule. `WorldDesc.Of(w)` turns it into records
(`fastsim world describe <seed> <tick>` prints one).

### What is read and what is not

Read (visible on screen, or learned by watching): positions, sizes,
velocities, phases and periods of cycles, warning states, a firework's
burst ring, a falling crate's marked column, a dart's glowing lane, the
echo's trail (the bird's own last second), both patterns of a blink wall.

Not read (hidden random choices): the sim's RNG and hash salts, a drop's or
crate's next column, a lanes dart's next lane, a firework's next spot, a
bubble's next column, a stalactite's slide target, a piston's next height,
the next wall's spikes and a new exit's height. Bodies that depend on those
are marked `guess` (the model places a best guess, for example a stalactite
sliding toward the bird's height at its last bounce, which is how the room
picks it). `Memory` keeps what a player remembers: where each stalactite gap
was a tick ago (to see it slide) and the bird's height at the last bounce.

Hazards whose motion depends on the bird (`reactive`): stalker, curious and
splitting bouncers, echo, aimed darts, bubbles (they carry the bird), lava
(its stone), keys. Given the bird's planned path they are exact too.

### No peeking (enforced)

`tests/unit/test_world_model_no_peek.gd` (in the check) and
`fastsim world nopeek` scan `World/` for `clone_deep`, `.step(`, the RNG
(`SimRng`, `_rng`, `next_below`...), hidden fields (`.salt`, `.target_y`,
`.next_x`), the sim's hazard hooks (`.setup(`, `.on_bounce(`, `.kills(`,
`.touch(`...) and any write to `sim.state`/`sim.room`.

## Prediction error per hazard type

`fastsim world errors [seeds] [ticks]` plays practice runs in every room
variant, lets the model predict 10, 30 and 60 ticks ahead from the present
(fed the taps really made), and compares with the sim: each body's outline,
bodies there or not, and the kill zone on a 24 px grid (`hazard.kills()` vs
the model). Results: see "Measured" below.

## The planner (`WorldPlanner`)

Each tick: read the world, build a shared timeline of the hazards that do
not react to the bird (one model copy per substep ahead), then a beam search
over tap/wait, tick by tick, up to the horizon (stopping a path 24 ticks
after it bounces or when it takes the exit). Paths keep their own copies of
the reactive hazards. A path that dies is dropped. Costs: passing inside the
safety margin of anything deadly (twice for guessed bodies), flying near the
ceiling or floor, and at the bounce the distance from the middle (the next
wall's gap is drawn near the bird's height, so the middle keeps the most
options). Taking the exit wins. Paths are merged per (height, speed) bucket,
keeping the cheapest.

Skill levels add human limits: reaction delay (the bot plans on the world as
it was `delay` ticks ago, moved on by the model with the taps made since),
tap timing noise, dropped taps, a shorter horizon, a smaller margin, a beam
cut, and a misjudged height (a new error at every wall, sometimes 3x).

    fastsim world runs 100 --skill beast
    fastsim world tiers 100
    fastsim world runfile 7 --skill beast --out run.json

## The structured observation for learned policies (`WorldObs`)

`WorldObs.Fill(w, x)`: 152 floats (layout in `WorldObs.cs`): bird and room,
exact landing heights at the wall for 9 tap timings, the 13 slots, the
nearest gaps and the exit, the 8 nearest deadly bodies (position, size,
velocity, position 30 ticks ahead, guess/reacts flags), and the pushes at the
bird.

## Measured

(filled in below as results come in)
