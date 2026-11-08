# Spikey

Tap to flap, bounce from wall to wall, don't touch the spikes. Built with
Godot 4.6 for iOS and Android, with leaderboards verified by replaying every
run on the server.

- Architecture: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Rules for contributors and AI agents: [CLAUDE.md](CLAUDE.md)

## Play

Open the folder in Godot 4.6 and press **F5**. Click or press Space to flap,
Esc or P to pause.

## Check

```powershell
powershell -ExecutionPolicy Bypass -File tools/check.ps1
```

Runs lint and format checks, a headless import, a load check of every
script and scene, and all tests (unit, golden replays, bot simulations).
Set `$env:GODOT` or put the path to the Godot console executable in
`tools/godot_path.txt`. Lint needs `pip install --user "gdtoolkit==4.*"`.

## Layout

```
sim/      deterministic game core (integers only), shared with the server
game/     scenes, drawing, input, HUD
server/   headless run verifier
tests/    test runner, unit tests, golden replays, bot simulations
tools/    check script, CI helpers, golden-replay generator
docs/     architecture
```
