# Bot sight: every bot sees every hazard

The FastSim check `sight` (`tools/fastsim-rs/fastsim/src/checks/sight.rs`, run by
`tools/fastsim.ps1 -Mode check` and so by `tools/check.ps1`) fails when a bot
is blind to a hazard type, or reads a value the player can't see.

## What it plays

Every hazard class is listed in `SightCheck::classes()` (Rust has no
reflection), so a new hazard must be added there to be in the check.
For each class, up to two rooms (or variants) that place it are played on a
line that lives (`SurvivalSearch.run_quick`, as long as the `passable` check
plays that room). A class that no room places fails the check, unless it is
only a base class (`SightCheck::BASES`, e.g. `Boss`).

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

A look is seen when the eye flags at least half of the danger points (within
8 px). A cell of the matrix is blind when fewer than half of its looks are
seen (`-`: fewer than 4 looks).

The C# check also had the eyes of the retired bots (`world` for WorldPlanner,
`worldobs`, `mpc`, `rl`) and a `warn` column that read `Hazard.warnings()`
(`sim/rooms/hazard.gd`) at the look. They were not ported: the bots went with
the C# FastSim on 2026-11-12, and the warnings are checked by parity (every
run's `w:` line) and `tests/unit/test_warnings.gd`.

## Hidden values

- Every hazard field of type `SimRng`, or a `long` named `seed`, `salt`,
  `*_seed` or `*_salt`, is a hidden draw. Two blind copies made with
  different RNGs must differ in it: `blind_copy` must replace it. Keep hidden
  draws in such fields so the check sees them.
- `blind_copy` must keep what is on screen: a scrambled value that changes a
  tell already showing shows up as a blind `blind` cell.

## Known gaps

`SightCheck::KNOWN` lists blind cells that are allowed while their fix is in
flight, each with the session fixing it. Remove an entry when its fix lands
(the matrix then shows the cell as seen). Its entries today are all for the
retired eyes, so none applies to `blind`.

The bar (MIN_RATE 0.5, MIN_SAMPLES 4) separated the C# matrix cleanly: blind
cells read 0-33% (Firework mpc danger 43%), seen cells 58% or more.

## Running it alone

```
powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode check -Check sight
```

`FASTSIM_SIGHT_ONLY=<text>` plays only rooms whose label contains it (and logs
the time each pass takes).
