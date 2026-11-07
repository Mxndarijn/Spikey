# Backlog

Ideas agreed on but not scheduled yet. Move an item into a phase when we start it.

## Bird trails (cosmetic shop item)

- A basic trail is in: `TrailView` draws whatever `TrailStyle` it is given
  (`game/cosmetics/trail_style.gd`). Two styles exist in code: Sunset Ribbon
  (default) and Spark Dots.
- Later: each trail becomes a `.tres` in `data/trails/`, players unlock or buy
  them in the shop (coins, rank, events, optional purchase), and the equipped
  trail is saved in the profile.
- Trail ideas: ribbon, sparkle dots, feathers, bubbles (Deep Sea), embers
  (Lava Forge), snowflakes (Ice Cavern), sprinkles (Sugar Rush), stardust
  (Star Station), rainbow, paper confetti (fits Fold), seasonal event trails.
- Likely needs more kinds than RIBBON/DOTS: textured ribbon, particle trail
  (GPUParticles2D/CPUParticles2D with a texture), sprite stamps.
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
- One shared UI `Theme` resource (`assets/ui/spike_cage_theme.tres`) so every
  screen picks up the same buttons, fonts and panels.
- Add a display font that matches Sunset Glow (rounded, heavy, like the
  mockups) under `assets/fonts/`, checking its license allows commercial use.
- Later, the same SVG approach for character and spike art, with
  `game/style/` procedural drawing kept as the fallback.
- Add to the check: the planned screenshot comparison of key screens (menu,
  each theme, game over) once these screens have real art.
