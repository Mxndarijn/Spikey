# Backlog

Ideas agreed on but not scheduled yet. Move an item into a phase when we start it.

## Bird trails (cosmetic shop item)

- Ten trails are in (`TrailStyle` in `game/cosmetics/trail_style.gd`, drawn by
  `TrailPainter` for both the room and the shop picture): World Ribbon (free),
  Spark Dots, Bubble Stream, Rainbow Ribbon, Leaf Swirl, Pixel Trail, Confetti,
  Comet Tail, Star Dust, Music Notes (a note per flap). Kinds: RIBBON, DOTS,
  STRIPES, COMET, STAMPS (bubble, confetti, sparkle, leaf, note, pixel).
- Later: each trail as a `.tres` in `data/trails/`; unlocks by rank or events.
- More ideas: feathers, snowflakes, seasonal event trails.
- Rule: trails are cosmetic only. They never affect the hitbox, the sim or
  replays, and they must stay readable (never cover spikes; respect
  reduced-flashing in accessibility settings).

## UI art as SVG / images

- Game over, pause, menus, buttons, score pills and shop cards should use
  designed art instead of the plain Godot controls they use now.
- Plan: draw them as SVGs (sharp at any phone resolution, small files, easy for
  AI and humans to edit), stored in `assets/ui/`. Godot imports SVGs as
  textures. Use them as `StyleBoxTexture` / `NinePatchRect` backgrounds and
  `TextureRect` icons so panels can stretch without distortion.
- One shared UI `Theme` resource (`assets/ui/spikey_theme.tres`) so every
  screen picks up the same buttons, fonts and panels.
- Add a display font that matches Sunset Glow (rounded, heavy, like the
  mockups) under `assets/fonts/`, checking its license allows commercial use.
- Later, the same SVG approach for character and spike art, with
  `game/style/` procedural drawing kept as the fallback.
- Add to the check: the planned screenshot comparison of key screens (menu,
  each theme, game over) once these screens have real art.

## Design kit in the game

- The design kit (https://claude.ai/artifact/2nzQWN24GGt8WCpsoJFGd8) is the
  source for colors, fonts, sizes and components. Wired in: see
  `data/design/README.md` (importer, UiTokens, UiTheme, ThemeDef per world,
  contract and sync tests). T switches world in-game until the picker exists.
- Still to do:
  - Fonts are bundled (Baloo 2, Nunito, variable, `assets/fonts/`). Before
    release: ship the OFL texts with the app (export filter `*.txt` or an
    in-game credits/licenses screen), since the license asks for that.
  - Done: room palettes (times of day) for every world, two or three each,
    in `data/design/room_palettes.json`, all checked by the contrast tests.
  - Done: home screen, shop (flyers,
    worlds, trails) with coins, game over with medal, coins earned and Home.
  - Done: particles per world (`RoomView.MOTE_KIND`: dust, pollen, snow,
    embers, bubbles, sprinkles, stars, leaves, sand, petals, rain, fireflies).
  - Color-blind spikes and reduced flashing settings (`RoomView.flash_enabled`).
  - Paid and seasonal worlds go in `data/design/extra_worlds.json`. Six are in
    (Autumn Grove, Desert Dusk, Cherry Blossom, Neon City, Haunted Moon,
    Winter Fest). Their `season` field (October, December) is not used yet:
    showing seasonal worlds only in their month needs the server date.

## Menus and shop (next)

- Done: coins are collected in runs (gameplay version 2): a wall bounce places
  one coin at a random spot when none is out. Verified with the replay. Old note:
  score. Coin pickups in rooms (Phase 2) need a gameplay version bump.
- Prices live in `meta/shop.gd`; free items are starters (a first start gets
  the first free flyer and the default world, with no pickers).
- Hats, skins per flyer, rewarded-ad revive, settings screen (haptics, sound,
  accessibility), credits/licenses screen.
- Twelve flyers are in: the launch six plus Pip, Mochi, Tock, Lulu, Puff and
  Bubbles. More characters from the game plan page can join as data files in
  `data/flyers/` with art in `assets/flyers/<id>/`.
