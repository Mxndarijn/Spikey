# FastSim-RS: the bot sim in Rust

`tools/fastsim-rs` is a line-by-line Rust copy of `sim/` plus the playtest
bots. It is the only bot sim: it began as a port of the C# FastSim
(`tools/fastsim`), which was removed on 2026-11-12. It is a tool only: the game
and the server run the GDScript sim, the one source of truth.

Ported from C#: the sim (with `Hazard.warnings` /
`GameSim.warnings`), BlindPlanner (blind_copy and every honesty rule, plan reuse,
`tap_free`, `frozen`, `mid_offset`, `plan_lives`, the `steps` counter), the human
tiers (MotorPlayer with the calibrated tiers, Persona habits and the reaction to
new warnings, Trace, Atlas), the yardstick, the test protocol (`measure`, incl.
`median`, `visibility` and the `tier:react=R,level=L` bots), the review tools
(`rl review fair|autopsy|exposure|bouncefair|fixtest|honest|atlas|trace|horizon|blindcheck`),
`boss run|fair`, `difficulty`, `honesty plan|anchor|rooms|seeds`, `sameseed`, the
`fastsim` modes search, searchruns, rooms, runs, reaction, odds, scan, runfile and
bench, and every check but four (below).
Retired with C# FastSim, not ported: WorldPlanner, MPC, RL, HumanBot and Reflex,
honest-v1, the checks rlbot, rlboss, mpcbot and mpcboss, `combos` (Double
Trouble was removed), and research switches that were off by default
(`longest`, `peek`, `aim_wall`, `mid_visible`, `mc_samples`). Their research is
in the git history (`docs/ARCHITECTURE.md`, Retired bots).

`tools/yardstick.ps1`, `tools/fastsim.ps1` and `tools/calibrate_tiers.ps1` run
on Rust only. `fastsim.ps1 -Mode parity` and `tools/fastsim-rs/parity.ps1` both
check the Rust copy. `tools/fastsim-rs/exe.ps1` builds the binary and prints its
path. Data files: `tools/fastsim-rs/data/visible.tsv` (`docs/BOT_TESTING.md`)
and `tools/fastsim-rs/data/tiers.json` (the calibrated human tiers).

## Layout

    tools/fastsim-rs/
      Cargo.toml          workspace; release: lto fat, codegen-units 1, panic abort
      .cargo/config.toml  -C target-cpu=native
      build.ps1           cargo build --release (exit 3 = cargo not installed)
      parity.ps1          record tools/fastsim_parity.gd in headless Godot, replay in Rust
      sim/                the deterministic core (integers only): a port of sim/
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
    fastsim-rs simspeed --seeds 64 --cap 50000          the sim alone (C#'s `fastsim simspeed`)
    fastsim-rs check passable,arrival,sight,blind_seeds [--filter x]
    fastsim-rs yardstick run --bot honest,human:good --seeds 8 --out <dir>   (the yardstick)
    fastsim-rs human measure|fit|baseline|deaths|atlas|motortrace --bot motor ...
    fastsim-rs bench                                    copy / step time
    fastsim-rs measure bank|trials|estimate|confirm|runs|report|median|leak|visibility|check ...
    fastsim-rs rl review fair|autopsy|exposure|bouncefair|fixtest|honest|atlas|trace|horizon|blindcheck ...
    fastsim-rs search|searchruns|rooms|runs|reaction|odds|scan ...   fastsim-rs runfile <seed> [bot_seed] --out f
    fastsim-rs honesty plan|anchor|rooms|seeds ...   fastsim-rs sameseed ...
    fastsim-rs boss run|fair ...    fastsim-rs difficulty list|measure|score|show ...

Modes and options keep C#'s names; `--threads` is read where C# read it, but
one pool (`--jobs`) runs everything. `measure/fields.rs` lists every SimState,
RoomRuntime and hazard field for the leak check (C# used reflection): a sim
type that gains or loses a field must be changed there too (PORTING.md).

`tools/check.ps1` runs the Rust parity as its "FastSim-RS parity" step and the
bot checks on Rust; without cargo both fail (install Rust, below).

## Parity (how "the same" is checked)

- **Sim:** `parity.ps1` records `tools/fastsim_parity.gd` (inputs and a checksum
  every tick, every room and variant, portal arrivals, revives, every check
  setup, bots and searches) and `fastsim-rs parity` replays it. Full set: 1116 of
  1116 cases, 445,923 ticks; the bots (gap seeker, random tapper, PlannerBot) and
  SurvivalSearch choose the same taps as GDScript.
- **Planner:** `fastsim-rs speed` printed the same taps fingerprint as C#
  `fastsim rl review speed` (seeds 1..16, cap 20000: `eabaebfe531e3f7e`, same
  deaths, points and arrival-memo hits on both).
- **Human tiers and yardstick:** `yardstick run` on gap, honest, human:normal and
  human:good gave the same JSON and the same `comparison.md` as C#.
- **Checks:** the same verdicts and summary numbers as C#.

The C# comparisons were made before C# was removed; now parity with `sim/` is
the only gate.

## Speed (Ryzen 9 9950X, 4 threads, the PC busy with other sessions)

A historical comparison with the C# FastSim, before its removal.

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
A beam node costs about 125 ns (C# took about 400 ns). The next large win is the
speed review's shared hazard timeline (step bird-independent hazards once per
search depth): it needs a split step and a per-hazard proof of independence.

## Porting rules

How to port a `sim/` change (GDScript -> Rust, line by line), the check's bot
tests and how to play one room variant: `tools/fastsim-rs/PORTING.md`.
