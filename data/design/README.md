# Design data

The game's look comes from the Flapjaw Design Kit
(https://claude.ai/artifact/2nzQWN24GGt8WCpsoJFGd8).

| File | What | Edit by |
|---|---|---|
| `tokens.json` | Copy of the kit's `project/tokens.json`: UI tokens, launch worlds, type, spacing, sizes | Change the kit, then copy its file here |
| `room_palettes.json` | Extra times of day per world (rooms cycle through them) | Hand |
| `extra_worlds.json` | Worlds beyond the kit's 8-world page limit: paid, seasonal | Hand |
| `world_scenes.json` | Scene colours per world for the flat layered rooms (sun ring, cloud, three hill layers, props, ink, paper, where the sky blend ends, night) | Hand |

Each world's landscape is painted by `game/run/scenes/worlds/<id>.gd` (design
canvas "Worlds v4"); a world without one gets `generic.gd`, built from its
tokens. Fixed scene colours are constants there and never a world's spike colour.

After any change, regenerate and check:

```
godot --headless --path . -s res://tools/import_design_kit.gd
powershell -ExecutionPolicy Bypass -File tools/check.ps1
```

The importer writes `game/style/ui_tokens.gd` (UiTokens) and
`data/themes/<id>.tres` (one ThemeDef per world). Don't edit those by hand.
`tests/unit/test_design_kit.gd` fails when they are out of date, when a world
misses a token, when a world's spike color is below 3:1 against any of its
sky stops or anything its scene draws behind the spikes, or when a scene
covers the score area.
