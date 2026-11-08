# Audio plan

Status: in the game (8 Nov 2026). `game/audio/audio_director.gd` plays every sound
and the layered music; `game/audio/music_track.gd` lists the tracks. Listen to everything on the Sound Board:
https://claude.ai/artifact/YYSHtQng8M5wGXyTQzNHr5

## Style

Based on the user's example pack (`Flapping_Cage_sounds`, 11 OGG files, reference only;
see Licences). The examples are soft, rounded casual-mobile sound design, not harsh
8-bit chiptune:

- Quick gameplay sounds last 0.12 to 0.19 s with 10 to 55 ms attacks.
- Transitions last 0.5 to 2.4 s and use swells and filter sweeps (rising = go,
  falling = slow down).
- Tones are smooth (sine/triangle) with pitch bends; noise is always filtered.
- The example levels are uneven (peaks −3 to −17 dBFS). Ours are normalized per
  category.

| Example | Length | What it is | Likely event |
| --- | --- | --- | --- |
| Flap.ogg | 0.19 s | band-passed noise 300 Hz–1 kHz, two strokes | flap |
| Hit.ogg | 0.16 s | low tone dipping 400 → 200 Hz and back | wall bounce |
| Hit1.ogg | 0.19 s | click + sub thud, loudest (−3 dBFS) | death |
| Coin.ogg | 0.13 s | tonal, partials 2.3 / 5.5 / 8 kHz | coin |
| AchievementSound.ogg | 0.57 s | 3–10 kHz glitter swelling to 0.3 s | milestone |
| DoorOpen.ogg | 1.6 s | grinding mechanical rumble | exit opens |
| DoorPass.ogg | 2.1 s | noisy burst then ringing partials | through exit |
| Slowmo.ogg | 2.4 s | filter sinking from 10 kHz to bass | calm / slow |
| Speedup.ogg | 0.91 s | low rumble with rising hiss | wild / fast |
| Teleport1.ogg | 0.54 s | two sweeps crossing in an X | teleport |
| Teleport2.ogg | 0.92 s | 880 Hz tone with warble | teleport hum |

## Sound per event

All files are `assets/audio/sfx/<name>.ogg`, 44.1 kHz mono, rendered by
`assets/audio/src/spikey_synth.py`. "Peak" is the normalized peak in dBFS.

| Event | Trigger | File | Peak | Sound |
| --- | --- | --- | --- | --- |
| Flap / tap | sim `FLAP` | `flap` | −6 | feathery fwip, two wing strokes; random pitch ±4% |
| Wall bounce, +1 | sim `BOUNCE` | `bounce` | −5 | rounded boop with dip-then-rise; pitch climbs a major-pentatonic step per bounce in a room (`pitch_scale = 2^(step/12)`, steps 0 2 4 7 9 12 14 16, then hold), resets on new room |
| Coin pickup | sim `COIN` | `coin` | −6 | bright two-note bling B5 → E6 |
| Coin reaches counter | game: fly-in tween ends | `coin_counter` | −12 | tiny glassy tick, +1 semitone per coin in a burst |
| Spike death | sim `DEATH`, bird not at top/bottom | `death_spike` | −3 | pop-thud: click, falling sub, crunch, squeak |
| Ceiling/floor death | sim `DEATH`, bird at top/bottom bound | `death_wall` | −4 | woody bonk + sad slide whistle |
| Exit portal opens | sim `EXIT_OPEN` (normal exit) | `portal_open` | −6 | rising hiss + C-E-G-C sparkle |
| Calm/Wild fork appears | sim `EXIT_OPEN` with fork exits | `fork_appear` | −6 | low bell + high bell |
| Through a portal | sim `ROOM_CHANGE` | `portal_pass` | −5 | warp whoosh, crossing sweeps, A5 ring |
| Took Calm exit | `ROOM_CHANGE` into a calm room | `fork_calm` | −7 | sinking slow-motion F chord (plays instead of `portal_pass`) |
| Took Wild exit | `ROOM_CHANGE` into a wild room | `fork_wild` | −5 | rising power-up into A-major stab (instead of `portal_pass`) |
| New room | first frame of the new room | `new_room` | −8 | air puff + strummed C-major pluck |
| Combo / milestone | every 10 points, new best | `milestone` | −6 | sparkle swell with fast high notes |
| UI tap | any button | `ui_tap` | −10 | soft rising pop |
| UI back / close | back, close | `ui_back` | −10 | falling pop |
| UI confirm / equip | equip, play, OK | `ui_confirm` | −8 | two notes up a fifth |
| Locked / not enough coins | tap on locked item | `ui_locked` | −9 | two muted low buzzes |
| Purchase | buying a cosmetic | `purchase` | −5 | coin cascade + G-major chord |
| Rewarded-ad revive | revive accepted | `revive` | −5 | rising shimmer glide + bell chord |

The exact synth recipe for each sound is in its function in `spikey_synth.py`
(`sfx_<name>`), and summarised on the Sound Board.

CC0 fallbacks if we ever want a recorded sound instead (all CC0 1.0):
Kenney [Interface Sounds](https://kenney.nl/assets/interface-sounds),
[UI Audio](https://kenney.nl/assets/ui-audio),
[Digital Audio](https://kenney.nl/assets/digital-audio),
[Impact Sounds](https://kenney.nl/assets/impact-sounds),
[Casino Audio](https://kenney.nl/assets/casino-audio),
[Sci-fi Sounds](https://kenney.nl/assets/sci-fi-sounds),
[Music Jingles](https://kenney.nl/assets/music-jingles); freesound.org files tagged
[CC0](https://freesound.org/browse/tags/cc0/) (check each file's licence).

## Music

### Chosen design: one track per pick, layers follow the run

Players choose a **track** in Customize. Each track is four stems of the same length
(pad, bass, drums, lead) that play in sync; the game, not the player, turns stems on
and off as the run builds. This suits short runs: the music grows with the score
inside a 30-second run, and every loop is short (13.7–20.9 s), so nothing feels
repetitive within one run.

Rejected alternatives:
- Player-toggled layers: too fiddly for a mobile arcade game and hard to show in a shop card.
- Many tracks per world: more content to make and sell; can be added later on top
  of this design (a world can list several tracks).

Layer rules (fade 0.4 s; stems stay in sync because they share a start time and length):

| Moment | pad | bass | drums | lead | volume |
| --- | --- | --- | --- | --- | --- |
| Menu, Customize | on | – | – | on | −4 dB |
| Run start | on | on | – | – | 0 |
| 10 points (first portal) | on | on | on | – | 0 |
| 25 points | on | on | on | on | 0 |
| Calm room | on | on | – | on | −1 dB |
| Wild room | on | on | on | on | +1 dB |
| Death | (keep) | | | | low-pass to ~400 Hz, −5 dB; revive restores |

### Customize: Music tab

- A **Music** tab next to Flyers, Worlds, Trails and Portals. Each item is a card
  with a preview button (plays the full mix in the card), price and Equip.
- **Match my world** (free, default) plays the track mapped to the equipped world.
- **Shuffle owned** picks a random owned track each run (cosmetic randomness only,
  never from the sim RNG).
- Tracks are cosmetic shop items like any other; prices below follow `meta/shop.gd`
  world prices.

### Starter tracks

All are 8 bars, rendered by `spikey_synth.py` into
`assets/audio/music/<id>/<id>_{pad,bass,drums,lead}.ogg`. Loops are sample-exact:
note tails past the loop end are wrapped to the start.

| Track | Price | Mood | Tempo · key | Stems | Loop | Match my world |
| --- | --- | --- | --- | --- | --- | --- |
| Candy Hop (`candy_hop`) | free | bright, bouncy main theme | 120 BPM · C major | sine pad, triangle octave bass, kick/clap/hats, square pluck | 16.00 s (705600 samples) | Sugar Rush, Blossom, Sunset Glow |
| Bubble Drift (`bubble_drift`) | 300 | calm, floaty | 92 BPM · F lydian | sine pad, sine bass, shaker/rim/soft kick, marimba + echo | 20.87 s (920348) | Deep Sea, Ice Cavern, Winterfest |
| Jungle Bounce (`jungle_bounce`) | 300 | playful, swung | 104 BPM · D dorian | saw pad, syncopated bass, log drums/shaker/clap, kalimba | 18.46 s (814154) | Jungle Canopy, Autumn, Desert |
| Lava Rush (`lava_rush`) | 400 | driving, tense | 140 BPM · A minor | dark pad, 16th saw bass, four-on-floor kit, saw riff | 13.71 s (604800) | Lava Forge, Haunted |
| Star Arcade (`star_arcade`) | 400 | retro chiptune | 128 BPM · E minor | 12.5% pulse arpeggio, triangle bass, noise drums, pulse lead | 15.00 s (661500) | Star Station, Neon |

Full mixes measure about −17.5 to −19 LUFS integrated and peak at −3 dBFS. More
tracks: write a new entry in `TRACKS` in the synth script, or use CC0 loops from
[OpenGameArt's CC0 music collection](https://opengameart.org/content/cc0-music-0)
(stems would then be one "full" stem; layering needs separate stems).

### Settings

- Music volume and Sound volume sliders (0–100, perceptual: gain = (v/100)²), each
  with an on/off switch, saved with the other settings. Haptics stay separate.
- iOS: use the ambient audio session so the silent switch is respected and the
  player's own music can keep playing; while other audio plays, mute our music.

## Implementation

Built as below, except: the buses are created in code by `AudioDirector` (no bus
layout file), the stems loop through their import settings, and every button gets
`ui_tap` (or `ui_back` when its name has back, close or home in it) automatically.
Screens call `AudioDirector.ui("confirm")`, `AudioDirector.sound("purchase")` and
so on for the rest. Tests: `tests/unit/test_audio.gd`.

- Buses: `Master` → `Music` (with a LowPassFilter effect for death), `SFX`, `UI`.
  Default levels: Music −6 dB, SFX 0 dB, UI −2 dB.
- One `AudioDirector` in `game/` reads `GameSim.events` each step and plays sounds;
  it never writes to the sim. Death type comes from the bird's position at the
  `DEATH` event.
- SFX: a small pool of `AudioStreamPlayer`s (about 8 voices); cap `flap` and `bounce`
  to 2 voices each so fast taps don't pile up.
- Music: `AudioStreamSynchronized` (Godot 4.3+) with the four stems; set each stem's
  volume for the layer rules. Import stems with loop on, SFX with loop off.
- Music choice, shuffle and settings live in `meta/` save data, like other cosmetics.

## Licences

| Asset | Source | Licence |
| --- | --- | --- |
| `assets/audio/sfx/*.ogg`, `assets/audio/music/**/*.ogg` | rendered by `assets/audio/src/spikey_synth.py`, written for this project | owned by the project, no third-party rights, no credit needed |
| `assets/audio/src/spikey_synth.py` | written for this project | project code |
| User's example pack `Flapping_Cage_sounds` (outside the repo) | unknown: no metadata, no licence file | reference only; never ship, never copy into `assets/` |
| Kenney packs (fallback, not in the repo) | kenney.nl | CC0 1.0 |
| freesound.org / OpenGameArt (fallback, not in the repo) | per file | only files marked CC0 |

Open question for the user: where does the example pack come from? If it is from a
paid asset pack the user owns, its licence might allow shipping some sounds, but
nothing depends on that: the synthesized set already covers every event.
