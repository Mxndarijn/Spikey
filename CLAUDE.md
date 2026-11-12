# Flapjaw

Godot 4.7, GDScript, portrait mobile arcade game (tap to flap, bounce wall to
wall, avoid spikes). Read `docs/ARCHITECTURE.md` before structural changes.

## Workflow

- The AI writes code + tests. A change is done only when the check passes:
  `powershell -ExecutionPolicy Bypass -File tools/check.ps1`
  (filter tests: `-TestFilter replay`). Fix failures and rerun; never skip a check.
- The user playtests at each milestone. Keep changes small and testable.
- Every feature or fix gets its own git worktree and branch, made from `main`
  (`git worktree add ../SpikeCage-<name> -b <name> main`). Never work in the
  main checkout: other sessions share it. Copy `tools/godot_path.txt` into the
  new worktree. Merge into `main` only when the check passes there.
- Godot path: `$env:GODOT` or `tools/godot_path.txt` (untracked, local machine).
- Never pop up a game window on the user's PC. Every Godot run is `--headless`
  (check script, tests, tools). On Windows, rendering always shows a window,
  even off-screen, so `tools/screenshot.ps1` runs only when the user asks for
  screenshots in that conversation.
- To render a run (a bot's or a player's) as video or frames: write a run file
  and call `tools/render_run.ps1` (`docs/RENDERING.md`). `-Check` is headless
  and always fine; rendering only when the user asks in that conversation.
- Working in a git worktree and merging it into `main`: once the merge is
  pushed, remove that worktree (`git worktree remove <path>`). Its branch stays
  unless the user says otherwise.

## Hard rules

- `sim/` is the deterministic core. Integers only (sub-units, `SimConfig.SUB`),
  no floats, `Vector2`, built-in random, `Time`/`OS`/`Engine`, Nodes or cosmetic
  data. `tests/unit/test_sim_purity.gd` enforces this.
- Gameplay rules live only in `sim/`. `game/` reads sim state and events and
  never changes them.
- Layers only point back: `sim/` -> `meta/` -> `services/` -> `game/`
  (`tests/unit/test_layers.gd`). `meta/` holds ids and money rules, never looks.
- Any change to movement, collision, generation or RNG draw order: bump
  `SimConfig.GAMEPLAY_VERSION`, then regenerate goldens with
  `godot --headless --path . -s res://tools/make_golden.gd`. Never regenerate
  goldens to make an unintended change pass.
- `tools/fastsim-rs` is a Rust copy of `sim/` for fast playtest bots
  (docs/FASTSIM_RS.md, `tools/fastsim.ps1`). Any change in `sim/` must be
  ported there line by line (`tools/fastsim-rs/PORTING.md`); the check's
  FastSim-RS parity step fails until it matches. Big bot sweeps use
  FastSim-RS, not Godot.
- Every character shares one hitbox. Characters, hats, themes and spike skins
  are cosmetic only.
- Monetization is cosmetic only plus an optional rewarded-ad revive. Nothing
  pay-to-win.
- Visual design follows the Flapjaw Design Kit
  (https://claude.ai/artifact/2nzQWN24GGt8WCpsoJFGd8, read its `project/README.md`
  and `project/tokens.json`): the font Archivo, its color, spacing, radius
  and size tokens. World tokens change with the theme picker; UI tokens never do.
  Every theme (free, paid or seasonal) must provide all world tokens and keep
  `spike` at 3:1 or more against every sky stop.
- Static typing everywhere. Format with `gdformat --line-length 100`.
- Tests: `tests/**/test_*.gd`, extend `TestCase`, methods named `test_*`.
  Any logged error fails the test.
