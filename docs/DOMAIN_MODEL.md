# Spike Cage — Domain Model

Class diagrams for the whole game, split by the same layers as
[ARCHITECTURE.md](ARCHITECTURE.md). Arrows only point inward: content and meta
know about the sim, the sim knows about nothing else.

Rendered images: [diagrams/](diagrams/). The Mermaid source below is the
source of truth; re-export the SVGs when you change it.

## Three words that are easy to mix up

| Term | Layer | Decided by | Changes gameplay? | Example |
|---|---|---|---|---|
| **Room kind** | `sim/` | The run seed (RNG) | Yes: gap size, spike count, obstacles, boss | "Narrow", "Saw Hall", "Boss: Crusher" |
| **Theme** (world) | `data/` + `game/` | The player, in the theme menu | No | Jungle Canopy, Ice Cavern |
| **Room palette** | `data/` + `game/` | The room index inside the chosen theme | No | Sunset Glow's Dusk, Dawn, Noon |

So one run in Ice Cavern can visit room kinds Open → Narrow → Saw Hall, each
drawn with the next Ice Cavern palette and Ice Cavern's spike and obstacle skins.
A room kind never knows which theme draws it.

## 1. Gameplay core (`sim/`)

Integers only, no Nodes, no engine time. Everything here is part of the
gameplay rules and is covered by `GAMEPLAY_VERSION`.

```mermaid
classDiagram
direction TB
class GameSim {
  +int seed_value
  +SimState state
  +Array~SimEvent~ events
  +step(tap bool) void
  +is_over() bool
  +checksum() int
}
class SimState {
  +int tick
  +bool started
  +bool alive
  +DeathCause death_cause
  +BirdState bird
  +RoomState room
  +int score
  +int coins_collected
  +copy() SimState
  +checksum() int
}
class BirdState {
  +int x
  +int y
  +int vx
  +int vy
}
class RoomState {
  +int index
  +int kind_id
  +int left_spikes
  +int right_spikes
  +Array~ObstacleState~ obstacles
  +Array~PickupState~ pickups
}
class RoomKind {
  <<const data>>
  +int id
  +int gap_slots
  +int extra_spikes
  +int obstacle_budget
  +Array~ObstacleType~ allowed_obstacles
  +bool is_boss
}
class RoomCatalog {
  <<static>>
  +kinds() Array~RoomKind~
  +next_kind(rng, current, score) RoomKind
}
class RoomGenerator {
  <<static>>
  +generate_wall(rng, score, kind) int
  +spawn_obstacles(rng, score, kind) Array~ObstacleState~
  +spawn_pickups(rng, score, kind) Array~PickupState~
}
class ObstacleState {
  <<abstract>>
  +ObstacleType type
  +int x
  +int y
  +step(tick int) void
  +hits(bird BirdState) bool
}
class SpikeBlock
class Saw
class MovingBar
class Laser
class PickupState {
  +PickupType type
  +int x
  +int y
  +bool taken
}
class SimEvent {
  <<enum>>
  START
  FLAP
  BOUNCE
  SCORE
  ROOM_CHANGE
  PICKUP
  REVIVE
  DEATH
}
class SimRng {
  +next_u32() int
  +next_below(n) int
}
class Replay {
  +int gameplay_version
  +int seed_value
  +PackedInt32Array taps
  +PackedInt32Array revive_ticks
  +int score
  +int end_tick
  +int checksum
  +simulate(seed, taps)$ GameSim
  +verify() Dictionary
}
GameSim *-- SimState
GameSim *-- SimRng
GameSim ..> RoomCatalog : picks next room
GameSim ..> RoomGenerator : builds room
GameSim ..> SimEvent : emits
SimState *-- BirdState
SimState *-- RoomState
RoomState o-- ObstacleState
RoomState o-- PickupState
RoomState ..> RoomKind : kind_id
RoomCatalog o-- RoomKind
RoomGenerator ..> SimRng
ObstacleState <|-- SpikeBlock
ObstacleState <|-- Saw
ObstacleState <|-- MovingBar
ObstacleState <|-- Laser
Replay ..> GameSim : re-simulates
```

Notes:

- **Room flow**: on every 10th point `GameSim` asks `RoomCatalog.next_kind()`
  (never the same kind twice; a boss kind every 50 points), then
  `RoomGenerator` fills a fresh `RoomState`. On every wall bounce only the
  opposite wall's spike mask is regenerated.
- **Obstacles** move on integer paths driven by `tick` alone, so they replay
  exactly. Each type does its own integer collision against `BirdState` using
  `SimMath`. New obstacle types are added as subclasses plus a view (section 2).
- **Pickups** (coins, feathers, stars) live in the sim so collected coins are
  replay-verifiable, and the `PICKUP` event tells the view to play the effect.
- **Revive** is an input like a tap: `Replay.revive_ticks` records it so the
  server can replay it. One per run.
- **Draw order is a rule**: `RoomGenerator` must always draw from `SimRng` in the
  same order (wall, then obstacles, then pickups). Reordering is a gameplay change.

## 2. Content and presentation (`data/`, `game/`)

Content is Godot `Resource` classes saved as `.tres` files, so new characters,
themes, hats and trails are data, not code. None of it reaches the sim.

```mermaid
classDiagram
direction TB
class ThemeDef {
  <<Resource>>
  +String id
  +String display_name
  +Array~RoomPalette~ palettes
  +SpikeSkin spike_skin
  +Dictionary obstacle_skins
  +PackedScene background
  +AudioStream music
  +UnlockRule unlock
}
class RoomPalette {
  <<Resource>>
  +String name
  +Array~Color~ sky
  +Color sun
  +Color spike
}
class SpikeSkin {
  <<Resource>>
  +String shape
  +String render_style
  +Texture2D texture
}
class ObstacleSkin {
  <<Resource>>
  +ObstacleType type
  +PackedScene view_scene
}
class CharacterDef {
  <<Resource>>
  +String id
  +String display_name
  +PackedScene art
  +Array~String~ fits_themes
  +UnlockRule unlock
}
class CosmeticDef {
  <<abstract Resource>>
  +String id
  +String display_name
  +Slot slot
  +UnlockRule unlock
}
class SkinDef {
  +String character_id
  +Dictionary colors
}
class HatDef {
  +Texture2D texture
  +Vector2 anchor_offset
}
class TrailStyle {
  +Kind kind
  +float lifetime
  +float width
  +Color head_color
  +Color tail_color
}
class UnlockRule {
  <<Resource>>
  +Kind kind
  +int amount
  +String ref_id
}
class Loadout {
  +String character_id
  +String skin_id
  +String hat_id
  +String trail_id
  +String theme_id
}
class RunController {
  +GameSim sim
  +SimState prev_state
  +new_run(seed) void
  +request_tap() void
  +set_paused(v) void
}
class RoomView {
  +bind(run, theme) void
}
class ObstacleView {
  <<abstract>>
  +sync(state ObstacleState) void
}
class BirdView {
  +bind(run, character, loadout) void
}
class TrailView {
  +bind(bird, style) void
}
class FeedbackPlayer {
  +on_event(e SimEvent) void
}
ThemeDef *-- RoomPalette
ThemeDef *-- SpikeSkin
ThemeDef o-- ObstacleSkin
ThemeDef --> UnlockRule
CharacterDef --> UnlockRule
CosmeticDef <|-- SkinDef
CosmeticDef <|-- HatDef
CosmeticDef <|-- TrailStyle
CosmeticDef --> UnlockRule
RunController ..> GameSim : steps
RoomView ..> RunController : reads state
RoomView ..> ThemeDef : draws with
RoomView o-- ObstacleView
ObstacleSkin ..> ObstacleView : instantiates
BirdView ..> CharacterDef
BirdView ..> HatDef
TrailView ..> TrailStyle
FeedbackPlayer ..> RunController : listens
Loadout ..> ThemeDef
Loadout ..> CharacterDef
Loadout ..> CosmeticDef
```

Notes:

- `RoomView` picks the palette with `theme.palettes[room.index % size]` and
  creates one `ObstacleView` per `ObstacleState`, using the theme's
  `ObstacleSkin` for that type. That's how the wooden beam becomes a steel
  girder in Star Station.
- `BirdView` draws the character, skin and hat; `TrailView` draws the trail.
  All characters use the sim's one hitbox.
- `FeedbackPlayer` turns sim events into sound, haptics, particles and screen
  shake, using the player's sound pack and accessibility settings.
- UI screens (game over, pause, shop) use SVG art and one shared UI `Theme`
  (see [BACKLOG.md](BACKLOG.md)).

## 3. Meta, services and server (`meta/`, `services/`, `server/`)

```mermaid
classDiagram
direction TB
class Catalog {
  +themes() Array~ThemeDef~
  +characters() Array~CharacterDef~
  +cosmetics(slot) Array~CosmeticDef~
  +find(id) Resource
}
class Profile {
  +int version
  +Wallet wallet
  +Array~String~ owned_ids
  +Loadout loadout
  +Stats stats
  +Settings settings
  +Dictionary achievement_progress
  +save() void
  +load()$ Profile
}
class Wallet {
  +int coins
  +add(n, reason) void
  +spend(n, reason) bool
}
class Stats {
  +int best_score
  +int runs
  +int total_bounces
  +int rank_xp
}
class Settings {
  +bool haptics
  +String sound_pack
  +bool color_blind_spikes
  +bool reduced_flashing
  +bool large_tap_area
}
class Shop {
  +can_unlock(item) bool
  +unlock(item) bool
}
class AchievementTracker {
  +on_run_finished(replay, events) void
}
class RankSystem {
  +rank_for(xp) int
}
class EventCalendar {
  +active_events(server_date) Array
}
class SeedService {
  +request_seed() SeedTicket
  +daily_seed() SeedTicket
}
class LeaderboardClient {
  +submit(replay, ticket) SubmitResult
  +fetch(board) Array
}
class AdsService {
  +show_rewarded_revive() bool
}
class RunVerifier {
  <<server>>
  +verify(submission) Verdict
}
class SimVersionRegistry {
  <<server>>
  +sim_for(gameplay_version) Script
}
Profile *-- Wallet
Profile *-- Stats
Profile *-- Settings
Profile *-- Loadout
Shop ..> Catalog
Shop ..> Profile
AchievementTracker ..> Profile
RankSystem ..> Stats
EventCalendar ..> Catalog : seasonal items
LeaderboardClient ..> Replay : submits
LeaderboardClient ..> SeedService
RunVerifier ..> SimVersionRegistry
SimVersionRegistry ..> GameSim : one per gameplay version
RunVerifier ..> Replay
```

Notes:

- `Profile` is the save file (`user://profile.json`, with a `version` field for
  migrations). It is the only thing that changes when you buy or unlock
  something; `Catalog` is read-only content.
- Coins earned in a run come from the sim (`SimState.coins_collected`), so
  rewards and leaderboards use the same verified numbers.
- `SeedService` gives one-time seeds for ranked runs and the shared daily seed
  for the daily challenge room. Offline play uses a local seed and simply isn't
  submitted.
- `SimVersionRegistry` maps each allowed `gameplay_version` to a frozen copy of
  `sim/` (for example `sim/versions/g1/`), so old runs keep verifying after an
  update.

## Today vs target

| Piece | Today (Phase 1) | Target |
|---|---|---|
| Bird and room state | Flat fields on `SimState` | Split into `BirdState` + `RoomState` |
| Room kinds | `RoomRules.KINDS` (3 kinds) | `RoomKind` data in `RoomCatalog`, generation in `RoomGenerator` |
| Obstacles, pickups | None | `ObstacleState` subclasses, `PickupState` |
| Events | `GameSim.Event` | Same, plus `PICKUP`, `REVIVE` |
| Look | `SunsetPalette` dictionaries | `ThemeDef` / `RoomPalette` `.tres` files |
| Cosmetics | `TrailStyle` (2 styles in code) | `CosmeticDef` family in `data/`, owned via `Profile` |
| Meta, services, server registry | Not started | Phases 2–3 |

The first refactor (split `SimState`, rename `RoomRules`) should keep
behavior identical. The golden replays prove it: if they still pass without
regenerating, gameplay did not change and `GAMEPLAY_VERSION` stays the same.
