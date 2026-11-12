# Bot sight: every bot sees every hazard

The FastSim check `sight` (`tools/fastsim/Perception.cs`, run by
`tools/fastsim.ps1 -Mode check` and so by `tools/check.ps1`) fails when a bot
is blind to a hazard type, or reads a value the player can't see.

## What it plays

Every hazard class in FastSim is found by reflection (every non-abstract
subclass of `Hazard`), so a new hazard is in the check as soon as it exists.
For each class, up to two rooms (or variants) that place it are played on a
line that lives (`SurvivalSearch.run_quick`, as long as the `passable` check
plays that room). A class that no room places fails the check, unless it is
only a base class (`SightCheck.BASES`, e.g. `Boss`).

## The truth

Every tick, the bird is moved to each point of a 12 px grid and each hazard's
own `kills()` is asked (coarse 24 px first, then every point near a hit).
From that:

- **deadly** looks: every 30th tick on which the hazard kills somewhere. Does
  the bot's eye see that danger now?
- **tell** looks: an *onset* is danger that appears where the hazard killed
  nothing within 24 px one tick before (a beam firing, a press slamming in, a
  dart leaving the wall). The bot is asked `LEAD` = 20 ticks before the onset:
  does it expect danger there at the onset tick?

## The eyes

| column | bot | what is asked |
|---|---|---|
| `blind` | BlindPlanner and the human tiers on it | a `blind_copy` of the sim, stepped on along the bot's line: does it kill at the danger points? |
| `world` | WorldPlanner | `WorldModel.Read` (`Models.Read`), the models stepped on: does a deadly body cover the points? |
| `worldobs` | the RL world bot's input | `WorldObs.Fill`: does the vector change when the hazard is taken out of the model? |
| `mpc` | MPC bot | `Sight` shapes (moved on as Planner does) and warnings: does one cover the points? |
| `rl` | RL bot | `Observer.frame`: does the frame change when the hazard is taken away? |

A look is seen by a recall eye (`blind`, `world`, `mpc`) when it flags at least
half of the danger points (within 8 px). The input eyes (`worldobs`, `rl`) are
asked on deadly looks and on pure tells only (nothing of that hazard kills
yet), so a change can only come from the tell. A cell of the matrix is blind
when fewer than half of its looks are seen (`-`: fewer than 4 looks).

## Hidden values

- Every hazard field of type `SimRng`, or a `long` named `seed`, `salt`,
  `*_seed` or `*_salt`, is a hidden draw. Two blind copies made with
  different RNGs must differ in it: `blind_copy` must replace it. Keep hidden
  draws in such fields so the check sees them.
- Every eye must read the same from a blind copy as from the true sim (the
  RL frame, the WorldObs vector, the world models stepped on, Sight's shapes
  and warnings). A difference means the eye reads a hidden value.
- `blind_copy` must keep what is on screen: a scrambled value that changes a
  tell already showing shows up as a blind `blind` cell.

## Known gaps

`SightCheck.KNOWN` lists blind cells that are allowed while their fix is in
flight, each with the session fixing it. Remove an entry when its fix lands
(the matrix then shows the cell as seen).
`SightCheck.KNOWN_LEAKS` does the same for hidden-value reads (eye, scene).

Gaps on 2026-11-12 (the check runs 112 rooms in about 10 s on 8 workers):
- world / worldobs: no boss models (WorldModel makes bosses UnknownM). Fix:
  the world-model boss models branch.
- mpc: no boss tells (Sight reads only Piston and Beam warnings). Fix: the MPC
  boss sight branch.
- rl: no tell input at all (its grid is kills() now and 6 ticks back), so it is
  blind to every tell. Owner: planner-next.
- worldobs tells (Beam, Dart, Drop, Firework, Piston), mpc tells (CrateDrop,
  Dart, Drop, Firework, Lava, Stalker), mpc Firework danger, and
  Models.Read hidden reads in bubbles/spiky, keepy/two-balls and
  double/bramble_beams: WorldPlanner and MPC are frozen and retire at the
  Rust switch, so these have no owner.

The bar (MIN_RATE 0.5, MIN_SAMPLES 4) separates the matrix cleanly: blind
cells read 0–33% (Firework mpc danger 43%), seen cells 58% or more.

## Running it alone

```
powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode check -Check sight
```

`FASTSIM_SIGHT_ONLY=<text>` plays only rooms whose label contains it (and logs
the time each pass takes).
