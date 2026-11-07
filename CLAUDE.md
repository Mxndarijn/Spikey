# Spike Cage

Godot 4.6, GDScript, portrait mobile arcade game (tap to flap, bounce wall to
wall, avoid spikes). Read `docs/ARCHITECTURE.md` before structural changes.

## Workflow

- The AI writes code + tests. A change is done only when the check passes:
  `powershell -ExecutionPolicy Bypass -File tools/check.ps1`
  (filter tests: `-TestFilter replay`). Fix failures and rerun; never skip a check.
- The user playtests at each milestone. Keep changes small and testable.
- Godot path: `$env:GODOT` or `tools/godot_path.txt` (untracked, local machine).
- Never pop up a game window on the user's PC. Tests and tools run with
  `--headless`. To see the game, use `tools/screenshot.ps1 -Out <png>`: it renders
  off-screen, without focus, and closes itself. Never launch the game visibly
  unless the user asks.

## Hard rules

- `sim/` is the deterministic core. Integers only (sub-units, `SimConfig.SUB`),
  no floats, `Vector2`, built-in random, `Time`/`OS`/`Engine`, Nodes or cosmetic
  data. `tests/unit/test_sim_purity.gd` enforces this.
- Gameplay rules live only in `sim/`. `game/` reads sim state and events and
  never changes them.
- Any change to movement, collision, generation or RNG draw order: bump
  `SimConfig.GAMEPLAY_VERSION`, then regenerate goldens with
  `godot --headless --path . -s res://tools/make_golden.gd`. Never regenerate
  goldens to make an unintended change pass.
- Every character shares one hitbox. Characters, hats, themes and spike skins
  are cosmetic only.
- Monetization is cosmetic only plus an optional rewarded-ad revive. Nothing
  pay-to-win.
- Static typing everywhere. Format with `gdformat --line-length 100`.
- Tests: `tests/**/test_*.gd`, extend `TestCase`, methods named `test_*`.
  Any logged error fails the test.
