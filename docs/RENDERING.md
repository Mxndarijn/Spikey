# Rendering a run

**To render a run: write a run file, then call `tools/render_run.ps1`.**
This is the one way to turn a recorded run (a bot's or a player's) into a
video or frames. Don't write another format or another drawing path.

```
powershell -ExecutionPolicy Bypass -File tools/render_run.ps1 -Run run.json -Check              # safe: headless, draws nothing
powershell -ExecutionPolicy Bypass -File tools/render_run.ps1 -Run run.json -Out run.mp4         # video (only when the user asked)
powershell -ExecutionPolicy Bypass -File tools/render_run.ps1 -Run run.json -Frames run_frames   # PNG per tick (only when the user asked)
```

## Rules

- **`-Check` is always safe**: headless Godot, nothing drawn, no window. Use
  it freely, for example to prove a bot's run file is right.
- **Rendering (`-Out`, `-Frames`) only when the user asked for it in that
  conversation.** It draws for real on the GPU. It does that on a separate,
  hidden Windows desktop, so no window shows on the user's screen or taskbar
  and nothing takes focus, but it still uses the GPU and CPU. Sound is muted.
- One Godot process at a time. Take a CPU slot first if your setup hands them
  out.

## What it does

1. **Check** (always, headless): `tools/render_run.gd` loads the run file,
   refuses it if anything is off (format, `gameplay_version` other than
   `SimConfig.GAMEPLAY_VERSION`, an unknown loadout id or setting), then plays
   it in the real game (`main.tscn`, the leaderboard replay path
   `main.play_replay`) one sim tick per frame. At the end the game's sim must
   match the sim replay (`Replay.verify`) and the file's claimed `score`,
   `coins`, `end_tick` and `checksum`. Any difference fails.
2. **Film** (unless `-Check`): the same script again in Godot's Movie Maker
   mode (`--write-movie`, `--fixed-fps 60`), so every frame is one tick, with
   the run file's look and settings. It runs the check again on that run too.
   A run of empty frames (nothing drawn) fails. ffmpeg joins the PNGs into an
   mp4 (H.264, 60 fps).

The game uses a throwaway profile (`RunRender.PROFILE_PATH`, removed after)
and no server, so the player's save and the leaderboards never change.

Options: `-Resolution 540x960` (frame size; the world is 360x640, 9:16),
`-HoldSeconds 1.5` (keep filming after the crash), `-Driver opengl3_angle`
(if `opengl3` gives empty frames), `-Summary out.json` (the result below).

Exit code 0: the run matched (and was rendered). 1: mismatch, bad file or
empty frames, with the reason printed. 2: setup problem (no Godot, no
ffmpeg, no run file).

The summary JSON: `{ok, reason, score, coins, end_tick, checksum, frames,
gameplay_version}`.

## The run file

JSON. A `Replay.to_dict()` (`sim/replay.gd`) plus the look. Read and written
by `RunFile` (`meta/run_file.gd`); FastSim-RS writes the same with
`tools/fastsim-rs/fastsim/src/bots/run_file.rs`.

| key | | |
|---|---|---|
| `format` | required | `"flapjaw_run"` |
| `format_version` | required | `1` (`RunFile.FORMAT_VERSION`) |
| `gameplay_version` | required | `SimConfig.GAMEPLAY_VERSION` the run was played on |
| `seed` | required | the run seed |
| `season` | | `Seasons.*`, default `-1` (none) |
| `taps` | required | ticks the bot tapped on, strictly ascending |
| `revives` | | ticks of revives (the tick the sim stood at when it died) |
| `score`, `coins`, `end_tick`, `checksum` | `score`, `end_tick` required | the result the run claims; checked. `checksum` 0 skips that one check |
| `name` | | shown on the replay chip: "Replay: name, score" |
| `loadout` | | `ItemKind` -> id: `flyer`, `world`, `trail`, `portal`, `music`, `crash`, `plate`. Ids from `Catalog.ids(kind)`. A kind left out uses the game's default |
| `settings` | | look switches: `color_blind_spikes`, `reduced_flashing`, `large_buttons` (default off) |

Because it is a leaderboard run too, `main.play_replay(run_file.to_dict())`
plays it in the game.

```json
{
  "format": "flapjaw_run", "format_version": 1, "gameplay_version": 20,
  "seed": 4242, "season": -1, "taps": [0, 31, 58], "revives": [],
  "score": 14, "coins": 2, "end_tick": 1244, "checksum": 4270989426,
  "name": "tier 3",
  "loadout": {"flyer": "...", "world": "..."},
  "settings": {"color_blind_spikes": false}
}
```

### From a GDScript bot

```gdscript
var replay := SimBots.play(seed_value, SimBots.gap_seeker)   # or Replay.from_sim(sim, taps, revives)
RunFile.from_replay(replay, {ItemKind.WORLD: "ice"}, "my bot").save_file("C:/runs/bot.run.json")
```

### From a FastSim-RS bot (Rust)

Record each tick you tap on (and each revive) while the bot plays, then hand
the sim as it ended to `RunFile::write` (`RunFile::make` takes a loadout and
settings too):

```rust
let mut taps = Vec::new();
while !sim.is_over() && sim.state.tick < SimConfig::MAX_TICKS {
    let tap = bot(&sim);
    if tap {
        taps.push(sim.state.tick);
    }
    sim.step(tap);
}
RunFile::write("C:/runs/bot.run.json", &sim, &taps, &[], "tier 3")?;
// with a look: RunFile::make(&sim, &taps, &[], &[("world", "ice")], "tier 3", &[])
```

FastSim-RS must match `sim/` (parity is part of the check), so its runs replay
in Godot tick for tick. `tools/fastsim.ps1 -Mode runfile -Seed 7 -Out run.json`
writes an example (a gap seeker run).

## What it shows, and what it doesn't

The world is exactly what the player saw: the same scene, views and painters,
fed tick by tick from the same sim. The overlay is the replay one: the replay
chip and score, and "<name> scored N" at the end, not the live HUD and Game
over screen. The replay scrubber (timeline and controls) is off in renders. A revive plays on at once (no revive offer or 3-2-1 countdown;
those were menu time, not run ticks). No sound is recorded.

## Why a hidden desktop

Godot's `--headless` has no renderer (it draws nothing), and on Windows any
real rendering needs a window. A window on a hidden desktop
(`tools/render/hidden_desktop.cs`: `CreateDesktop` + `CreateProcess` with
that desktop) is never shown, keeps the real painters and needs nothing
installed besides Godot and ffmpeg. If it ever stops drawing there, the
fallback is Linux under WSL with Xvfb and a Linux Godot (software OpenGL).

## Tests

`tests/unit/test_run_file.gd` (headless): the format round trip and its
errors, `RunFile.check()`, `RunRender`'s loud failures, and the real game
playing a run file to the same end with its look. `tests/unit/test_fastsim_checks.gd`
pins FastSim-RS's `GAMEPLAY_VERSION` and its run file keys to the GDScript ones.

## Frames of every room variant

For a visual review of the rooms (only when the user asked for frames):
`tools/capture_variants.ps1 -Out <folder> [-World <world id>] [-Rooms id,id]`
plays each room variant as a debug-picker practice run with the planner bot on
a hidden desktop (like `render_run.ps1`) and saves JPGs at fixed sim ticks
(`<room>__<variant>__t<tick>.jpg`). The practice seed comes from the room and
variant, so two builds show the same moments (before/after a painter change).
Take the GPU lock around it.
