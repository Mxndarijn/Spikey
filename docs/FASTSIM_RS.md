# FastSim-RS: the bot sim in Rust

`tools/fastsim-rs` is a Rust copy of the C# FastSim (`tools/fastsim`), which is
itself a line-by-line copy of `sim/`. It runs the same bots, with the same
results, faster on the same CPU. It is a tool only: the game and the server run
the GDScript sim, the one source of truth.

Rust is the default for every bot run; C# FastSim stays as the fallback
(`-CSharp`) until it is removed. Ported: the sim (with `Hazard.warnings` /
`GameSim.warnings`), BlindPlanner (blind_copy and every honesty rule, plan reuse,
`tap_free`, `frozen`, `mid_offset`, `plan_lives`, the `steps` counter), the human
tiers (MotorPlayer with the calibrated tiers, Persona habits and the reaction to
new warnings, Trace, Atlas), the yardstick, the test protocol (`measure`, incl.
`median`, `visibility` and the `tier:react=R,level=L` bots), the review tools
(`rl review fair|autopsy|exposure|bouncefair|fixtest|honest|atlas|trace|horizon|blindcheck`),
`boss run|fair`, `difficulty`, `honesty plan|anchor|rooms|seeds`, `sameseed`, the
`fastsim` modes search, searchruns, rooms, runs, reaction, odds, scan, runfile and
bench, and every check but four (below).
Not ported (frozen, they go with C# FastSim): WorldPlanner, MPC, RL, HumanBot and
Reflex, honest-v1, the checks rlbot, rlboss, mpcbot and mpcboss, `combos` (Double
Trouble is being removed), and C#-only research switches that are off by default
(`longest`, `peek`, `aim_wall`, `mid_visible`, `mc_samples`).

`tools/yardstick.ps1`, `tools/fastsim.ps1` and `tools/calibrate_tiers.ps1` run on
Rust by default; bots only C# has (rl:*, world:*, mpc*, honest-v1) switch to C#
on their own, and `-CSharp` forces C#. `fastsim.ps1 -Mode parity` checks C#
FastSim; `tools/fastsim-rs/parity.ps1` checks the Rust copy.
`tools/fastsim-rs/exe.ps1` builds the binary and prints its path.

## Layout

    tools/fastsim-rs/
      Cargo.toml          workspace; release: lto fat, codegen-units 1, panic abort
      .cargo/config.toml  -C target-cpu=native
      build.ps1           cargo build --release (exit 3 = cargo not installed)
      parity.ps1          record tools/fastsim_parity.gd in headless Godot, replay in Rust
      sim/                the deterministic core (integers only): a port of tools/fastsim/Sim
      fastsim/            the binary fastsim-rs: bots, parity, checks, yardstick, human

## Install, build, run

    winget install Rustlang.Rustup      # then: rustup default stable (x86_64-pc-windows-msvc)
    powershell -ExecutionPolicy Bypass -File tools/fastsim-rs/build.ps1
    powershell -ExecutionPolicy Bypass -File tools/fastsim-rs/parity.ps1 -Quick

The binary is `tools/fastsim-rs/target/release/fastsim-rs.exe`. `--jobs N` sets
the thread count for every mode.

    fastsim-rs parity <cases.txt>                       replay a parity recording
    fastsim-rs speed --seeds 16 --cap 20000             BlindPlanner runs: ticks/s and the taps
                                                        fingerprint of C# `rl review speed`
                                                        (same options: --h, --n, --margin, --ownanchor ...)
    fastsim-rs simspeed --seeds 64 --cap 50000          the sim alone (= C# `fastsim simspeed`)
    fastsim-rs check passable,arrival,sight,blind_seeds [--filter x]
    fastsim-rs yardstick run --bot honest,human:good --seeds 8 --out <dir>   (= C# yardstick)
    fastsim-rs human measure|fit|baseline|deaths|atlas|motortrace --bot motor ...
    fastsim-rs bench                                    copy / step time (Program.cs Bench)
    fastsim-rs measure bank|trials|estimate|confirm|runs|report|median|leak|visibility|check ...
    fastsim-rs rl review fair|autopsy|exposure|bouncefair|fixtest|honest|atlas|trace|horizon|blindcheck ...
    fastsim-rs search|searchruns|rooms|runs|reaction|odds|scan ...   fastsim-rs runfile <seed> [bot] --out f
    fastsim-rs honesty plan|anchor|rooms|seeds ...   fastsim-rs sameseed ...
    fastsim-rs boss run|fair ...    fastsim-rs difficulty list|measure|score|show ...

Options are C#'s; `--threads` is read where C# reads it, but one pool (`--jobs`)
runs everything. `measure/fields.rs` lists every SimState, RoomRuntime and hazard
field for the leak check (C# uses reflection): regenerate it with the scripts in
`measure/gen/` when a sim type gains or loses a field.

`tools/check.ps1` runs the Rust parity as its own step ("FastSim-RS parity",
beside the C# one) and skips it cleanly when cargo is not installed.

## Parity (how "the same" is checked)

- **Sim:** `parity.ps1` records `tools/fastsim_parity.gd` (inputs and a checksum
  every tick, every room and variant, portal arrivals, revives, every check
  setup, bots and searches) and `fastsim-rs parity` replays it. Full set: 1116 of
  1116 cases, 445,923 ticks; the bots (gap seeker, random tapper, PlannerBot) and
  SurvivalSearch choose the same taps as GDScript.
- **Planner:** `fastsim-rs speed` prints the same taps fingerprint as C#
  `fastsim rl review speed` (seeds 1..16, cap 20000: `eabaebfe531e3f7e`, same
  deaths, points and arrival-memo hits on both).
- **Human tiers and yardstick:** `yardstick run` on gap, honest, human:normal and
  human:good gives the same JSON and the same `comparison.md` as C#.
- **Checks:** the same verdicts and summary numbers as C#.

## Speed (Ryzen 9 9950X, 4 threads, the PC busy with other sessions)

| what | C# | Rust | |
|---|---|---|---|
| sim alone (`simspeed`, 64 seeds x 50k ticks) | 2.0 M ticks/s | 16.4 M ticks/s | 8.1x |
| sim copy (`bench`, 1 thread) | 0.91 us | 0.10 us | 9x |
| BlindPlanner (`speed`, 16 seeds, cap 20k) | 4,396 ticks/s | 14,055 ticks/s | 3.2x |
| checks passable, arrival, sight, blind_seeds | 24 s | 7 s | 3.3x |
| yardstick run, 4 bots x 8 seeds | 183 s | 60 s | 3.0x |

The straight port gave the planner 1.4x. What brought it to 3.2x, all exact:
mimalloc; no hazard taken out for a method it does not override; hazards that
never read the room run with the list lent out (3 words moved, not the hazard);
beam nodes are boxed sims from a reuse pool (`copy_into` reuses buffers); room
copies reuse their hazard buffer; FxHash for bucket maps; and a line that
already loses its bucket skips its near-death look. PGO gave nothing measurable.

Where the planner's time goes now (`--features prof`, a sampling profiler):
near-death looks 18%, hazard steps 15%, kills and touches 12%, the rest of the
step 13%, wall bounces 10%, beam bookkeeping 16%, copies 7%, arrival checks 4%.
A beam node costs about 125 ns (C#: about 400 ns). The next large win is the
speed review's shared hazard timeline (step bird-independent hazards once per
search depth): it needs a split step and a per-hazard proof of independence.

## Porting rules (C# -> Rust)

Same names, same order, same structure as the C# (and so the GDScript) line.
Every `sim/` change goes to C# FastSim (PORTING.md) and here; `parity.ps1`
fails until both match.

- Every game value is `i64`. Integer `/` and `%` truncate toward zero, as in C#
  and GDScript. Overflow wraps (overflow checks are off in every profile).
  Shifts: `1i64 << slot` (slot an `i64`; counts are masked like C#).
- Indexes: `xs[i as usize]`. Lists are `Vec<i64>` (`.Count` -> `.len()`,
  `.Add` -> `.push`). A C# `long[]` constant is a `[i64; N]` const.
- Static classes are unit structs with associated consts and functions, so a
  call reads as in C#: `G::mini(a, b)`, `SimConfig::SUB`,
  `ExitZone::hits_rect(sim, ...)`, `FairLanes::start_path(sim)`. `G::b(bool)` is
  `G.B`. Enum classes (`DeathCause`, `ExitKind`, `Lane`) are unit structs of
  `i64` consts; nested ones live in the hazard's module (`firework::Style`).
- Names stay snake_case exactly as in C#, fields and methods. Rust keywords get
  a trailing `_` (`move_`, `crate_`, `type_`). C# `out_` stays `out_`.
- C# default arguments: Rust has none, so pass every argument (the doc comment
  of the function lists the C# defaults).
- Each hazard is a struct with `pub base: Base` (kind, alive, t, idx) and
  `impl Hazard for X { impl_base!(); ... }`. `kind` is set in the constructor
  (`Base::new("bouncer")`). Read `self.base.t` where C# reads `t`.
- A C# subclass holds its parent as a field and forwards: `HeavyBouncer { b:
  Bouncer, .. }` with `impl_base!(b.base)`. A parent method that calls a
  virtual the subclass overrides goes through a small trait (`BossKind`).
- The room keeps hazards by value in the enum `Hz` (`hazards/mod.rs`, with
  `From<X> for Hz`, so `X::new(..).into()`). A room copy is a plain clone;
  `clone_deep` and `remap` overrides go away.
- Methods that change the sim and the hazard (`setup`, `step`, `touch`,
  `adjust_wall`, `on_bounce`, `on_flap`) take `&mut self, sim: &mut GameSim`
  and run through `GameSim::with_hazard`: a type in `Hz::needs_room` is taken
  out of `sim.room.hazards` (its slot holds `Hz::Taken`, which panics if used;
  the hazard's own loops use `self` at `self.base.idx`); any other type runs
  with the whole list lent out. **A hazard that starts reading
  `sim.room.hazards` must be added to `needs_room`.** `has_step`, `has_touch`,
  `has_on_flap`, `has_on_bounce`, `has_adjust_wall` list who overrides what
  (a new override must be added there).
- Read-only methods (`kills`, `blocks_exit`, `guards_edge`, `band_top`,
  `band_bottom`, `near_row`, `wall_shift`, `locks_exit`, `checksum`) take
  `&self, sim: &GameSim`. If C# changes state in one (EdgePad.guards_edge
  pushes the bird), give it a `_mut` twin and call that from GameSim.
- A reference to another hazard (`Gate.partner`) is an index into
  `sim.room.hazards` (`Option<usize>`). Hazards are never removed or reordered.
- C# `h is CoinPickup c` matches subclasses too: `Hz::as_coin_pickup(_mut)`,
  `as_boss(_mut)`, `as_bouncer`.
- Hazard factories: `mk(|| Bouncer::new(..).into())`; a captured loop variable
  is copied into a local first (`move`).
- `RoomRuntime.start` / `step` live on GameSim (`room_start`, `room_step`)
  because they need the sim and the room at once.
- Tool code (bots, checks): C# `new Random(seed)` is `DotnetRandom` (the same
  sequence); C# `Math.Round` is `round_ties_even`; .NET custom number formats
  round at 15 digits first (`yardstick::fmt_num`).
