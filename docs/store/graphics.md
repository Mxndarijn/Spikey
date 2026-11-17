# Store graphics

What Google Play (and later the App Store) needs, and how to make each from what the repo has.
Nothing here has been rendered: screenshots and frames are made only when the user asks
(CLAUDE.md, `docs/RENDERING.md`). Look and colours follow the Flapjaw Design Kit
(https://claude.ai/artifact/2nzQWN24GGt8WCpsoJFGd8): Archivo, its tokens, `spike` 3:1 against
the sky.

## Google Play

| Asset | Required | Spec | Source / how |
| --- | --- | --- | --- |
| **App icon** | Yes | 512 x 512 PNG, 32-bit with alpha, max 1 MB. Play adds the rounded mask and shadow: fill the full square, no rounded corners or drop shadow of your own. | `icon.svg` (1024, Buzz the Bee on a zigzag between spike rows on a sunset sky) exported at 512. Inkscape: `inkscape icon.svg -w 512 -h 512 -o icon_512.png`, or any SVG export. Check it reads at 48 px: the spike rows may need to be thicker at that size. |
| **Feature graphic** | Yes | 1024 x 500, JPEG or 24-bit PNG (no alpha), max 15 MB. Shown above the listing and in promotions; keep text and the bee inside the middle 80% (Play crops the edges on some devices) and avoid small text. | Compose: a world's sky gradient (design kit world tokens), a row of spikes top and bottom, Buzz mid-flap left of centre with its trail, "Flapjaw" in Archivo Black-weight on the right. A design tool (Figma, the Canva connector, or an HTML page at 1024x500 exported to PNG) is quickest. Can also be cut from a rendered frame (below) plus the wordmark. |
| **Phone screenshots** | At least 2, up to 8 | PNG or JPEG, 9:16 portrait, each side 320–3840 px, long side at most 2x the short side. **Use 1080 x 1920**: with 4 or more screenshots of at least 1080 px Play may show the app in "featured" and recommendation spots. | See "Making the screenshots". |
| 7" and 10" tablet screenshots | No (only if you mark tablet support) | Same rules | Skip for now; the game is portrait phone. |
| Promo video | No | A YouTube URL, landscape or portrait, ads off on the video | A rendered run (`tools/render_run.ps1 -Out`), 30 s, cut to the best rooms, with the music. Optional, later. |

### Suggested screenshot set (portrait, 1080 x 1920)

Order matters: the first two or three show in search results. Each one gets a short caption bar
in the top 15% (Archivo, UI tokens, 2-5 words), the game shot below.

1. **Mid-run in a busy room**: Buzz between saws or lava, trail behind it, score in the HUD.
   Caption: "Tap to flap" / "Tik om te flappen".
2. **A boss room or a striking themed world** (neon, aurora): "Rooms that keep changing" /
   "Kamers die steeds veranderen".
3. **Duel live**: the rival's see-through bird with its name tag next to yours: "Duel live" /
   "Duel live".
4. **Battle screen**: the round list with the score, "Your turn": "Battle a friend" /
   "Daag een vriend uit".
5. **Daily Run board** with names and prize diamonds: "One map a day for everyone" /
   "Eén kaart per dag voor iedereen".
6. **Shop / cosmetics** showing flyers and worlds: "Looks only, never pay-to-win" /
   "Alleen uiterlijk, nooit pay-to-win".

Use made-up player names on boards (sample leaderboard, `services/sample_leaderboard.gd`),
never real players' names. Bots in shots keep their BOT tag.

### Making the screenshots

All three ways draw on the GPU, so they run only when the user asks for screenshots.

- **Game shots from a run (best for 1, 2):** record a good run as a run file (a bot's from
  FastSim-RS `planrun`, see `docs/RENDERING.md`), check it headless
  (`tools/render_run.ps1 -Run run.json -Check`, always fine), then render frames:
  `tools/render_run.ps1 -Run run.json -Frames <dir> -Resolution 1080x1920` and pick the
  frames. The world is 360x640 (9:16), so 1080x1920 is an exact 3x scale. Pick a loadout and
  world in the run file for variety.
- **Menus (4, 5, 6):** `tools/screenshot.ps1 -Out <file>.png -Resolution 1080x1920 -Screen home`
  (or `leaderboard`). It opens a hidden-position Godot window briefly. The Battle, Duel and
  shop screens aren't `-Screen` options yet: adding them to `tools/capture_screen.gd` is a small
  follow-up, or take those on a phone.
- **On a phone:** play a debug build, screenshot natively (a 1080-wide Android phone gives
  1080 x 2400; crop to 1080 x 1920 or keep it, 2400/1080 is under 2x so it's allowed).
  Fastest for the Duel shot, which needs a live rival.

Then add the caption bars in a design tool and export PNG. Keep the source files (for example
`docs/store/graphics/` as SVG or the design tool's link) so the Dutch set is a text swap.

### Localised graphics

Play lets each language have its own screenshots and feature graphic. Make the English set
first; the Dutch set only differs in the caption text (above). Without a Dutch set, Dutch users
see the English one.

## App Store (later)

| Asset | Spec |
| --- | --- |
| App icon | 1024 x 1024 PNG, **no alpha**, no rounded corners (Apple masks it). The Godot iOS preset slot `icons/icon_1024x1024` is still empty in `export_presets.cfg`. |
| iPhone screenshots | Required size today: 6.9" display, 1320 x 2868 (or 1290 x 2796) portrait, 1 to 10. Apple scales them down for smaller phones. Render at 1320x2868 (not 9:16: pad the sky or crop the HUD area, the world is 9:16). |
| iPad screenshots | Only if the build supports iPad (13", 2064 x 2752). Mark the app iPhone-only to skip. |
| App preview video | Optional, 15–30 s, the device's resolution. |
| Text | Name 30, subtitle 30, promotional text 170, description 4000, keywords 100 characters. `listing_*.md` covers name and description; subtitle suggestion "Tap, flap, dodge the spikes" (27) / "Tik, flap, ontwijk de spikes" (28). |

## Found while checking

- `export_presets.cfg`: all Android launcher icon slots (`main_192x192`, the adaptive
  foreground, background and monochrome 432x432) and the iOS 1024 icon are empty, so the builds
  fall back to `icon.svg`. Android 8+ then shows the full square shrunk inside a white circle on
  many launchers. Making the adaptive layers (Buzz on a transparent 432 foreground with the
  centre 66% safe zone, the sky as background, a one-colour monochrome) is a follow-up before
  the store build.
