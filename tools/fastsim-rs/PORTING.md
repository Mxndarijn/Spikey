# FastSim-RS: porting the sim to Rust, for fast playtest bots

`tools/fastsim-rs` is a Rust copy of `sim/` (the deterministic game) plus the
playtest bots, so big sweeps run as native code instead of GDScript. It is a
tool only: the game and the server still run the GDScript sim, which stays the
one source of truth. Layout, build and commands: `docs/FASTSIM_RS.md`.

The port is line by line from GDScript: the Rust keeps the GDScript names,
order and structure, so a Rust line can be checked against its GDScript line.
Every `sim/` change is ported here the same way.

**It must match `sim/` exactly.** `tools/fastsim_parity.gd` records runs in
Godot (inputs plus a checksum every tick, in every room); `fastsim-rs parity`
replays them and stops at the first tick that differs. Each recorded run
also ends in `w:<n>`, every tick's `GameSim.warnings()` mixed into one number:
the Rust hazards must show the same tells (they are not part of the checksum).
Run it after any sim change:

    powershell -ExecutionPolicy Bypass -File tools/fastsim-rs/parity.ps1 -Quick
    powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode parity

`tools/check.ps1` runs the full set as its "FastSim-RS parity" step and fails
until the port matches.

Parity covers every room in practice and full runs in every season, every
room variant forced (`GameSim.forced_variant`), a portal arrival into every
room variant (`ArrivalBench.arrival` = `Setups::arrival`), a revive in every
room, and the bots and searches the checks below use: for those cases the Rust
bot must choose the same taps as the GDScript one (`case ... gap` /
`planner:...` and `csearch` lines, see `tools/fastsim_parity.gd`).

## Rendering a bot's run

To render (or check) a run a FastSim-RS bot played, write a run file with
`fastsim/src/bots/run_file.rs` (`RunFile::write(path, sim, taps, revives, name)`;
`fastsim-rs runfile <seed> [bot_seed] --out f` writes a gap seeker's run)
and call `tools/render_run.ps1 -Run <file>` (`-Check` headless, `-Out x.mp4`
only when the user asked). See `docs/RENDERING.md`. `SimConfig::GAMEPLAY_VERSION`
in `sim/src/sim_config.rs` must equal the GDScript one, and `run_file.rs` must
write the format of `meta/run_file.gd` (`tests/unit/test_fastsim_checks.gd`).

## The check's bot tests (`fastsim-rs check`)

`tools/check.ps1` plays bots only on FastSim-RS (`tools/fastsim.ps1 -Mode
check`, `fastsim/src/checks/`), after parity. Each check took over a GDScript
test (still named so `-TestFilter` finds it), with the same rule and
thresholds and more seeds or arrivals. No GDScript test plays a bot; parity
proves the sim, the bots and the start sims (`tests/support/bot_setups.gd` =
`fastsim/src/setups.rs`) match:

| check | file | was | rule |
|---|---|---|---|
| `passable` | `passable.rs` | `tests/sim/test_variants_passable.gd` | SurvivalSearch gets through each practice seed of every variant (6 each) and takes the first portal |
| `arrival` | `arrival.rs` | `tests/sim/test_arrival_reaction.gd` | out of a portal, no 0.75 s reaction is killed with no way to live; at 1 s at most `ArrivalBench.MAX_EXTRA_PCT` of arrivals over every room and variant (32 each) |
| `points` | `points.rs` | `tests/sim/test_room_points_cap.gd` | no room stay pays more than `POINTS_PER_ROOM`, every variant, revives included |
| `revive` | `revive.rs` | `tests/sim/test_revive_survivable.gd` | after a revive in every room, every exit case, both walls, both ways in and three portal heights, a way to live on |
| `pairs` | `pairs.rs` | `tests/sim/test_double_trouble.gd` | every Double Trouble pair has a way through |
| `keys` | `keys.rs` | (new, named `tests/unit/test_locked_out.gd:test_every_key_can_be_taken`) | Locked Out, every variant, 12 seeds each: SurvivalSearch takes every key before it leaves through the exit |
| `crawl` | `searches.rs` | searches of `tests/sim/test_crawl_passable.gd` | through the first portal on the seeds a crawler once blocked; from a revive through the hard exits |
| `gates` | `searches.rs` | searches of `tests/sim/test_gates_passable.gd` | the portal is reachable: once impossible seeds, quick runs before an exit, after a revive at every height |
| `isles` | `searches.rs` | searches of `tests/sim/test_isles_passable.gd` | Floating Isles and Egg Hunt, every variant: through the portal, and from a revive through the exit (QuickSearch) |
| `rescued` | `searches.rs` | `tests/sim/test_rooms_survivable.gd` | rooms once proved impossible stay survivable; no way for a dead bird |
| `runs` | `runs.rs` | `tests/sim/test_bot_runs.gd` | random tappers keep the invariants and every run ends; gap seekers clear several rooms |
| `exits` | `exits.rs` | `tests/sim/test_exit_clear.gd` | no hazard kills in, or turns the bird back from, an exit mouth; no wall spike reaches into it |
| `reach` | `reach.rs` | `tests/sim/test_exits_reachable.gd` | every exit can still be taken once its ghost shows |
| `yardstick` | `../yardstick/check.rs` | (new) | the yardstick's own self-tests |
| `sameseed` | `sameseed.rs` | (new) | a revived run meets the same map as a run that never died there (`docs/REVIVE.md`) |
| `sight` | `sight.rs` | (new) | the bots see every hazard (`docs/BOT_SIGHT.md`) |
| `blind_seeds` | `honesty.rs` | (new) | a blind copy carries no true random state |
| `bossfair` | `../boss/check.rs` | (new) | every boss tell is fair with a 1 s reaction |
| `difficulty` | `../difficulty/` | (new) | the room difficulty measures (`docs/ROOM_DIFFICULTY.md`) |

    powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode check
    powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode check -Check arrival,revive
    powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode check -Filter variants_passable

The checks are the tests now: change their cases and thresholds in
`fastsim/src/checks/`. A new room or variant mostly needs nothing: the checks
read the catalog. A room with variants goes in `Passable::CASES` (with its
ticks). A check that starts from a new kind of sim: write the setup in
`tests/support/bot_setups.gd`, port it to `fastsim/src/setups.rs`, and add
parity cases for it (`tools/fastsim_parity.gd` setup(), `fastsim/src/parity.rs`
setup()). `ArrivalBench`'s thresholds are pinned to `checks/arrival.rs` by
`tests/unit/test_fastsim_checks.gd`.

## Porting rules (GDScript -> Rust)

Keep names, order and structure the same as the GDScript line.

- Every GDScript `int` is an `i64`. Integer `/` and `%` truncate toward zero in
  both. Overflow wraps (overflow checks are off in every profile). Never use
  another integer type for game values.
- Shifts: `1i64 << slot` (slot an `i64`; counts are masked as in GDScript).
- Indexes: `xs[i as usize]`.
- Names stay snake_case, exactly as in GDScript: fields, methods, constants and
  parameters (`p_lane`). A private `_name` stays `_name`. A file is the
  GDScript file name in snake_case (`crate_drop.gd` -> `crate_drop.rs`), its
  type the class name in PascalCase (`CrateDrop`).
- Rust keywords get a trailing `_` (`move_`, `crate_`, `type_`). Names that
  already carry one (`out_`) keep it.
- Default arguments: Rust has none, so pass every argument (the doc comment of
  the function lists the GDScript defaults).
- Static classes are unit structs with associated consts and functions, so a
  call reads as in GDScript: `G::mini(a, b)`, `SimConfig::SUB`,
  `ExitZone::hits_rect(sim, ...)`, `FairLanes::start_path(sim)`.
- Helpers: `mini maxi clampi absi signi posmod` are `G::mini(...)` etc. (in
  `sim/src/g.rs`, same edge cases as Godot). `int(some_bool)` is `G::b(some_bool)`.
- GDScript enums become unit structs of `i64` consts (`DeathCause`, `ExitKind`,
  `Lane`) and the field is an `i64`. A hazard's own enum lives in its module
  (`firework::Style`).
- `for i in n` -> `for i in 0..n`. `for i in range(a, b)` -> `for i in a..b`.
  `for x in list` over hazards or any list that may grow while looping: an
  index loop that re-reads `len()` each time (GDScript sees appended items).
- `Array[int]`, `PackedInt32Array`, `PackedInt64Array` -> `Vec<i64>`,
  `Array[bool]` -> `Vec<bool>`. `.size()` -> `.len()`, `.append` -> `.push`,
  `.clear()` -> `.clear()`, `.resize(n)` -> `.resize(n, 0)` (or `false`),
  `x in list` -> `list.contains(&x)`. A constant array is a `[i64; N]` const.
- `const X := preload(...)` of another hazard: just use that module's type.
- `assert(...)`: leave out.
- `_init(...)` -> `new(...)` with every argument. Set `kind` in it
  (`Base::new("bouncer")`).
- **Hazards.** The trait is in `sim/src/rooms/hazard.rs`. Each hazard is a
  struct with `pub base: Base` (kind, alive, t, idx) and
  `impl Hazard for X { impl_base!(); ... }`. Read `self.base.t` where GDScript
  reads `t`. Override with the GDScript names: `setup`, `step`, `kills`,
  `touch`, `adjust_wall`, `on_bounce`, `on_flap`, `blocks_exit`,
  `guards_edge`, `checksum`, `warnings(&self, sim, out_: &mut Vec<i64>)` (add
  each warning with `add_warning`, as GDScript does). `mix_all(h, &[a, b, c])`
  must mix in the GDScript order (`mix_all(h, [a, b] + xs)` builds one slice).
- A hazard that `extends` another holds its parent as a field and forwards:
  `HeavyBouncer { b: Bouncer, .. }` with `impl_base!(b.base)`. A parent method
  that calls a virtual the subclass overrides goes through a small trait
  (`BossKind`).
- The room keeps hazards by value in the enum `Hz` (`sim/src/hazards/mod.rs`,
  with `From<X> for Hz`, so `X::new(..).into()`). A new hazard gets a `Hz`
  variant and its arms in the dispatch. A room copy is a plain clone.
- Methods that change the sim and the hazard (`setup`, `step`, `touch`,
  `adjust_wall`, `on_bounce`, `on_flap`) take `&mut self, sim: &mut GameSim`
  and run through `GameSim::with_hazard`: a type in `Hz::needs_room` is taken
  out of `sim.room.hazards` (its slot holds `Hz::Taken`, which panics if used;
  the hazard's own loops use `self` at `self.base.idx`); any other type runs
  with the whole list lent out. **A hazard that starts reading
  `sim.room.hazards` must be added to `needs_room`.** `has_step`, `has_touch`,
  `has_on_flap`, `has_on_bounce`, `has_adjust_wall` list who overrides what
  (a new override must be added there; a missing entry silently skips the
  method, and parity catches it).
- Read-only methods (`kills`, `blocks_exit`, `guards_edge`, `band_top`,
  `band_bottom`, `near_row`, `wall_shift`, `locks_exit`, `checksum`) take
  `&self, sim: &GameSim`. If GDScript changes state in one (EdgePad.guards_edge
  pushes the bird), give it a `_mut` twin and call that from GameSim.
- A reference to another hazard (`Gate.partner`) is an index into
  `sim.room.hazards` (`Option<usize>`). Hazards are never removed or reordered.
- GDScript `h is CoinPickup` matches subclasses too: `Hz::as_coin_pickup(_mut)`,
  `as_boss(_mut)`, `as_bouncer`.
- GameSim API (same names as GDScript): `sim.state.*`, `sim.room.*`,
  `sim.steps_to_wall(side)`, `sim.wall_mask(side)`,
  `sim.bird_touches_circle(...)`, `sim.bird_touches_rect(...)`,
  `sim.bump_bird_from(...)`, `sim.collect_coin(...)`, `sim.kill(cause)`,
  `sim.is_practice()`, `sim.events`. Lanes and exits are their own unit
  structs: `FairLanes::entry_y(sim)`, `FairLanes::start_path(sim)`,
  `FairLanes::arrival_path(sim)`, `ExitPlanner::slots(&sim.state)`.
- `RoomRuntime.start` / `step` live on GameSim (`room_start`, `room_step`)
  because they need the sim and the room at once.
- Room catalogs: `catalog_core.gd` -> `sim/src/rooms/catalog_core.rs` with
  `defs()`. A GDScript factory `func() -> Hazard: return Bouncer.new()` or
  `_island.bind(i)` is `mk(|| Bouncer::new(..).into())`; a captured loop
  variable is copied into a local first (`move`), so each factory keeps its
  own value.
- Tool code (bots, checks): `DotnetRandom` is the .NET `Random(seed)` sequence
  the C# bots used, `round_ties_even` is .NET `Math.Round`, and
  `yardstick::fmt_num` rounds at 15 digits as .NET number formats did. Keep
  them: the calibrated tiers and the check thresholds were measured with them.

### Fields of the leak check (`measure/fields.rs`)

`fastsim/src/measure/fields.rs` lists every SimState, RoomRuntime and hazard
field (with a getter and a setter) and `methods.rs` their no-argument methods,
for the leak check and `measure visibility` (C# found them by reflection; Rust
has none). Both are generated from the Rust sim. Regenerate them when a sim
type gains or loses a field or such a method:

    cd tools/fastsim-rs
    python fastsim/src/measure/gen/rs_fields.py sim/src fastsim/src/measure/fields.rs
    python fastsim/src/measure/gen/rs_methods.py sim/src fastsim/src/measure/methods.rs

## Playing one room variant

A RoomDef with `variants` normally draws one from the run's RNG each time the
room starts (`RoomRuntime.start`). To test a variant on its own, force it:

    powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Room bramble -Variant twin -Seeds 256
    powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Room bramble -Variant all
    powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode rooms -Room pinwheel -Variant all
    powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 -Mode reaction -Room tide -Variant big

- `-Variant <id>` plays that variant in every room matching `-Room` that has
  it (a room without it is skipped; with none at all the run stops and lists
  the variant ids of the matching rooms).
- `-Variant all` plays each variant of each matching room in turn, with one
  report line (and one JSON entry, `"id": "bramble/twin"`, `"variant": "twin"`)
  per variant.
- Works with the per-room modes: `search` (default), `rooms`, `reaction` and
  `scan`.
- Godot side, same option: `tools/sweep.ps1 -Room bramble -Variant all`
  (`tools/playtest.gd` takes the variant as its seventh argument). In tests:
  `GameSim.new(seed, season, practice_room, "twin")`.

How it works: `GameSim.forced_variant` (a variant id, `""` in real play). The
room still draws its variant as always, then plays the forced one if it has a
variant with that id, so the RNG goes on exactly as in a normal run. Unset, the
sim is unchanged, tick for tick (`tests/unit/test_room_variants.gd`); goldens
and `GAMEPLAY_VERSION` are untouched. It is part of the port like any sim
field (`sim/src/game_sim.rs`, `sim/src/rooms/room_runtime.rs`).
