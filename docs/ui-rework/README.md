# UI rework (2026-11-17)

- `before/`: every screen on v0.1.4, before the rework (the mode carousel, the All modes sheet).
- `after/<world>/`: every screen after the rework at 390 x 844 on Winter Fest (the lightest sky), Sunset Glow and
  Neon City (the darkest): Home's solid Play bar (the user's pick), the mode sheet, solid two-tone surfaces that read
  on every world. Battle is paused (GameModes.battle_enabled), so its screens are not shot.
- Shots: `tools/capture_ui.ps1 -Out <dir> -World <id>` (every screen) and `tools/capture_home.gd` (Home's states).
  They open a game window: only when screenshots are asked for.
- The layout rules the screens keep are tested by `tests/unit/test_layout_qa.gd` (LayoutQa): nothing outside the
  room or near the spike rows, text fits, no hand-placed overlaps.
