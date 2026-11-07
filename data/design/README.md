# Design data

The game's look comes from the Spike Cage Design Kit
(https://claude.ai/artifact/2nzQWN24GGt8WCpsoJFGd8).

| File | What | Edit by |
|---|---|---|
| `tokens.json` | Copy of the kit's `project/tokens.json`: UI tokens, launch worlds, type, spacing, sizes | Change the kit, then copy its file here |
| `room_palettes.json` | Extra times of day per world (rooms cycle through them) | Hand |
| `extra_worlds.json` | Worlds beyond the kit's 8-world page limit: paid, seasonal | Hand |

After any change, regenerate and check:

```
godot --headless --path . -s res://tools/import_design_kit.gd
powershell -ExecutionPolicy Bypass -File tools/check.ps1
```

The importer writes `game/style/ui_tokens.gd` (UiTokens) and
`data/themes/<id>.tres` (one ThemeDef per world). Don't edit those by hand.
`tests/unit/test_design_kit.gd` fails when they are out of date, when a world
misses a token, or when a world's spike color is below 3:1 against any of its
sky stops.
