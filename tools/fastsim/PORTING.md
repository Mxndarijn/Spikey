# FastSim: the sim in C#, for fast playtest bots

`tools/fastsim` is a C# copy of `sim/` (the deterministic game) plus the
playtest bots, so big sweeps run as native code instead of GDScript. It is a
tool only: the game and the server still run the GDScript sim, which stays the
one source of truth.

**It must match `sim/` exactly.** `tools/fastsim_parity.gd` records runs in
Godot (inputs plus a checksum every tick, in every room); `fastsim parity`
replays them and stops at the first tick that differs. Run it after any sim
change:

    powershell -ExecutionPolicy Bypass -File tools/fastsim.ps1 parity

## Porting rules (GDScript -> C#)

The port is line by line, so a C# line can be checked against its GDScript
line. Keep names, order and structure the same.

- Every GDScript `int` is a C# `long`. Integer `/` and `%` behave the same in
  both (truncate toward zero). Never use `int` for game values.
- Shifts: the count must be an `int`: `1L << (int)slot`, `mask >> (int)slot`.
- List indexes must be `int`: `xs[(int)i]`. Arrays (`long[]`) take a `long`.
- Names stay snake_case, exactly as in GDScript: fields, methods, constants,
  and parameters (`p_lane`). A private `_name` stays `_name`. The C# class is
  the file name in PascalCase (`crate_drop.gd` -> `CrateDrop`).
- `out` is a C# keyword: use `out_`. Same for other keywords (`base` ->
  `base_`, `fixed` -> `fixed_`, `checked` -> `checked_`, `params` ->
  `params_`, `object` -> `object_`, `lock` -> `lock_`, `event` -> `event_`,
  `operator` -> `operator_`, `string` -> `string_`, `default` -> `default_`).
- Helpers: `mini maxi clampi absi signi posmod` are `G.mini(...)` etc. (in
  `Sim/G.cs`, same edge cases as Godot). `int(some_bool)` is `G.B(some_bool)`.
- `for i in n` -> `for (long i = 0; i < n; i++)`.
  `for i in range(a, b)` -> `for (long i = a; i < b; i++)`.
  `for x in list` over hazards or any list that may grow while looping: an
  index loop that re-reads `Count` each time (GDScript sees appended items).
- `Array[int]` -> `List<long>`, `Array[bool]` -> `List<bool>`,
  `PackedInt32Array` -> `List<long>`. `.size()` -> `.Count`, `.append` ->
  `.Add`, `.clear()` -> `.Clear()`, `.resize(n)` -> fill/trim to `n` with
  zeros (or false), `x in list` -> `list.Contains(x)`.
- GDScript enums become nested static classes of `long` constants
  (`enum Phase { WAIT, FALL }` -> `public static class Phase { public const
  long WAIT = 0, FALL = 1; }`) and the field is a `long`.
- `const X := preload(...)` of another hazard: just use that C# class.
- `assert(...)`: leave out.
- Hazard base: `Sim/Rooms/Hazard.cs`. Override with the same names:
  `setup(GameSim sim, SimRng rng)`, `step(GameSim sim)`, `kills(GameSim sim)`,
  `touch(GameSim sim)`, `adjust_wall(GameSim sim, long side, long mask)`,
  `on_bounce(GameSim sim, SimRng rng)`,
  `on_flap(GameSim sim)`, `blocks_exit(GameSim sim, long side, long y)`,
  `guards_edge(GameSim sim, bool top)`, `checksum(long h)`.
  `Hazard.mix_all(h, a, b, c)` takes values directly (params) or a
  `List<long>`. A GDScript `mix_all(h, [a, b] + xs)` must mix in the same order.
- `_init(...)` -> a constructor with the same defaults. Set `kind` as GDScript
  does (field initializer or constructor).
- **Copies:** a hazard with a `List`, an `SimRng` or other reference field
  overrides `clone_deep()` to copy them:
  `var c = (Crawler)MemberwiseClone(); c.xs = new List<long>(xs); return c;`
  (an `SimRng` copies with `.Clone()`). A field that points at another
  hazard (`partner`) overrides `remap(map)`:
  `if (partner != null) partner = map[partner];`.
- GameSim API (same names as GDScript): `sim.state.*`, `sim.room.*`,
  `sim.steps_to_wall(side)`, `sim.wall_mask(side)`,
  `sim.bird_touches_circle(...)`, `sim.bird_touches_rect(...)`,
  `sim.bump_bird_from(...)`, `sim.collect_coin(...)`, `sim.kill(cause)`,
  `sim.is_practice()`, `sim.events` (a `List<int>`, `Event.COIN` etc.).
  Lanes and exits are their own static classes, as in GDScript:
  `FairLanes.entry_y(sim)`, `FairLanes.start_path(sim)` (a `List<long>`),
  `FairLanes.start_path_hits_rect(sim, ...)`, `FairLanes.blocks_start_lane(sim, ...)`,
  `FairLanes.arrival_path(sim)`, `ExitPlanner.slots(sim.state)`.
  Constants: `SimConfig.*`, `GameSim.BUMP_VY`, `DeathCause.*`, `ExitKind.*`,
  `RoomDef.WallMode.*`, `RoomDef.Speed.*`, `Seasons.*`, `SimTrig.*`,
  `SimMath.*`, `RoomRules.*`, `RoomRuntime.*`.
- Room catalogs: `catalog_core.gd` -> `CatalogCore` (static class) with
  `public static List<RoomDef> defs()`. A GDScript factory `func() -> Hazard:
  return Bouncer.new()` or `_island.bind(i)` is a C# `Func<Hazard>` lambda
  (`() => new Bouncer()`, `() => _island(i)` with `i` copied into a local
  first so each lambda keeps its own value). `def.combos` is a
  `List<List<Func<Hazard>>>`, `def.variants` a `List<RoomVariant>`.
