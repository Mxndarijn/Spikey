# FastSim-RS: the bot sim in Rust

`tools/fastsim-rs` is a Rust copy of the C# FastSim (`tools/fastsim`), which is
itself a line-by-line copy of `sim/`. It runs the same bots faster on the same
CPU. It is a tool only: the game and the server run the GDScript sim, the one
source of truth. C# FastSim stays until the Rust one matches it everywhere.

## Layout

    tools/fastsim-rs/
      Cargo.toml          workspace; release: lto, codegen-units 1, panic abort
      .cargo/config.toml  -C target-cpu=native
      sim/                the deterministic core (integers only), a port of tools/fastsim/Sim
      fastsim/            the binary `fastsim-rs`: parity, bots, checks, yardstick

## Build and run

    cargo build --release --manifest-path tools/fastsim-rs/Cargo.toml
    tools/fastsim-rs/target/release/fastsim-rs parity <cases.txt>

Install: `winget install Rustlang.Rustup`, then `rustup default stable`
(x86_64-pc-windows-msvc; it links with the Visual Studio Build Tools).

## Porting rules (C# -> Rust)

Same names, same order, same structure as the C# (and so the GDScript) line.

- Every game value is `i64`. Integer `/` and `%` truncate toward zero, as in C#
  and GDScript. Overflow wraps (overflow checks are off in every profile).
  Shifts: `1i64 << slot` (slot an `i64`; counts are masked like C#).
- Indexes: `xs[i as usize]`. Lists are `Vec<i64>` (`.Count` -> `.len()`,
  `.Add` -> `.push`). A C# `long[]` constant is a `[i64; N]` const.
- Static classes are unit structs with associated consts and functions, so a
  call reads as in C#: `G::mini(a, b)`, `SimConfig::SUB`,
  `ExitZone::hits_rect(sim, ...)`, `FairLanes::start_path(sim)`. `G::b(bool)` is
  `G.B`. Enum classes (`DeathCause`, `ExitKind`, `Lane`) are unit structs of
  `i64` consts.
- Names stay snake_case exactly as in C#, fields and methods. Rust keywords get
  a trailing `_` (`move_`, `type_`, `ref_`, `box_`, `loop_`, `match_`, `in_`).
  C# `out_` stays `out_`.
- C# default arguments: Rust has none, so pass every argument (the doc comment
  of the function lists the C# defaults).
- Each hazard is a struct with `pub base: Base` (kind, alive, t, idx) and
  `impl Hazard for X { impl_base!(); ... }`. `kind` is set in the constructor
  (`Base::new("bouncer")`). Read `self.base.t` where C# reads `t`, and
  `self.base.alive` for `alive`.
- A C# subclass holds its parent as a field and forwards: `HeavyBouncer { b:
  Bouncer, .. }` with `impl_base!(b.base)`, `base.setup(sim, rng)` ->
  `self.b.setup(sim, rng)`, `base.checksum(h)` -> `self.b.checksum(h)`. A
  parent method that calls a virtual method the subclass overrides goes through
  a small trait (or a parameter) so the subclass's version runs, exactly as in C#.
- The room keeps hazards by value in the enum `Hz` (`hazards/mod.rs`, with
  `From<X> for Hz`, so `X::new(..).into()`). A room copy is a plain `clone()`:
  every hazard derives `Clone`; lists and RNGs inside are copied with it, so
  `clone_deep` overrides go away.
- Methods that change the sim and the hazard (`setup`, `step`, `touch`,
  `adjust_wall`, `on_bounce`, `on_flap`) take `&mut self, sim: &mut GameSim`.
  While one runs, the hazard is taken out of `sim.room.hazards` and its slot
  holds `Hz::Taken`. A hazard that loops over `sim.room.hazards` sees
  `Taken` at its own index `self.base.idx` and must use `self` there (C# would
  see `this`). Calling anything on `Taken` panics, so a missed case fails
  loudly instead of quietly differing.
- Read-only methods (`kills`, `blocks_exit`, `guards_edge`, `band_top`,
  `band_bottom`, `near_row`, `wall_shift`, `locks_exit`, `checksum`) take
  `&self, sim: &GameSim`. If C# changes fields in one of them and restores them
  (Bouncer.near_row), work on a copy.
- A field that points at another hazard (`Gate.partner`) is an index into
  `sim.room.hazards` (`Option<usize>`); reach it with
  `if let Hz::Gate(p) = &mut sim.room.hazards[i]`. Hazards are never removed
  or reordered, so a room copy needs no remap.
- C# `h is CoinPickup c` matches subclasses too: use `Hz::as_coin_pickup(_mut)`,
  `as_boss(_mut)`, `as_bouncer`.
- Hazard factories (`Func<Hazard>`): `mk(|| Bouncer::new(..).into())`; a C#
  lambda that captures a loop variable copies it into a local first (`move`).
- `GameSim` API as in C#: `sim.state.*`, `sim.room.*` (`sim.room.def()` for
  `room.def`), `sim.collect_coin(x, y, 1)`, `sim.kill(cause)`,
  `sim.bump_bird_from(..)`, `sim.bird_touches_circle(..)`, `sim.events`.
  RoomRuntime's `start` and `step` live on GameSim (`room_start`, `room_step`)
  because they need the sim and the room at once.

## Parity

Rust must give the same checksum every tick as `sim/` and C# FastSim:
`fastsim-rs parity <cases.txt>` replays `tools/fastsim_parity.gd`'s recording
exactly like `fastsim parity`. `tools/check.ps1` runs it as its own step and
skips it cleanly when cargo is not installed.
