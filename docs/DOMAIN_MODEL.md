# Flapjaw — Domain Model

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
class Profile {
  +int coins
  +int diamonds
  +Dictionary owned
  +Dictionary equipped
  +PlayerSettings settings
  +DailyRevives revives
  +record_run(score, coins) int
  +save(path) bool
  +load_or_new(path)$ Profile
}
class PlayerSettings {
  +int music_volume
  +bool haptics
  +bool color_blind_spikes
  +is_on(Switch) bool
  +set_on(Switch, bool) void
}
class DailyRevives {
  +left(day) int
  +use(day) bool
}
class SafeFile {
  +write_json(path, data)$ bool
  +read_json(path)$ Variant
}
class ItemKind {
  <<ids>>
  +ALL
  +STARTERS
  +DEFAULTS
}
class Economy {
  +gold_for(diamonds)$ int
  +daily_prize(rank)$ int
}
class Catalog {
  <<game/cosmetics>>
  +flyers() Array
  +portal(id) PortalStyle
  +repair(profile)$ bool
}
class Shop {
  <<game/cosmetics>>
  +price(kind, id)$ int
  +diamond_price(kind, id)$ int
}
class Checkout {
  <<game/cosmetics>>
  +buy(kind, id) Result
  +convert(diamonds) bool
}
class SupabaseClient {
  +ensure_session() bool
  +call_db(function, body) Dictionary
}
class LeaderboardService {
  +request_board(id) void
  +submit_run(score, replay) void
}
class WalletService {
  +spend(amount, reason, ref) bool
  +claim() int
}
class StoreService
class AdsService
class PushService
class AppServices {
  <<game/app>>
}
class RunChecker {
  <<server>>
  +check(run) Verdict
}
Profile *-- PlayerSettings
Profile *-- DailyRevives
Profile ..> SafeFile : saves through
Profile ..> ItemKind : starters
Checkout ..> Shop
Checkout ..> WalletService : premium items, converting
Checkout ..> Profile
Catalog ..> Profile : repair()
LeaderboardService <|-- SupabaseLeaderboard
WalletService <|-- SupabaseWallet
SupabaseLeaderboard ..> SupabaseClient
SupabaseWallet ..> SupabaseClient
PushService ..> SupabaseClient
AppServices o-- LeaderboardService
AppServices o-- WalletService
AppServices o-- StoreService
AppServices o-- AdsService
AppServices o-- PushService
AppServices o-- Checkout
RunChecker ..> Replay : replays with the same sim/
```

Notes:

- `Profile` is the save file (`user://profile.json`). `SafeFile` writes it to a
  temp file first and keeps the last good one as `.bak`; a broken save loads the
  backup and is kept aside, never overwritten. The `version` field goes through
  `Profile._migrate()`, and keys a newer build wrote are written back as they
  were. Equipped ids are stored as saved; `Catalog.repair()` swaps looks that
  no longer exist.
- `meta/` knows nothing about how things look: ids only (`ItemKind`). What an
  id looks like is `Catalog`, its price `Shop`, buying it `Checkout`.
- Coins earned in a run come from the sim (`SimState.coins`, checked by
  `Replay.verify()`), so rewards and leaderboards use the same verified numbers.
- Every service base class is also its offline stand-in (no boards, the local
  wallet, a closed store, no ads, no push). `AppServices` picks the real one
  when the build and setup allow it and hands the set to the screens.
- A diamond spend carries a request id, so a lost answer can be asked again
  without a second charge (`supabase/migrations/20261110140000_spend_requests.sql`).
- Planned: server-issued one-time seeds, and frozen copies of older sims
  (for example `sim/versions/g1/`) so old runs keep verifying after an update.

## Today

| Piece | Where |
|---|---|
| Bird and room state | Flat fields on `SimState`; the live room is `RoomRuntime` |
| Room kinds | `RoomDef` batches in `sim/rooms/catalog_*.gd`, picked by `RoomCatalog.pick_next` |
| Obstacles, pickups | One `Hazard` subclass each in `sim/hazards/` |
| Fairness | `FairLanes` (start and arrival lanes), `ArrivalCheck`, `ExitPlanner`, hazard hooks |
| Look | `ThemeDef` `.tres` per world (generated), `WorldScene` per world, a painter per hazard |
| Cosmetics | Style + painter pairs in `game/cosmetics/`, owned and equipped via `Profile` |
| Meta, services, server | `meta/`, `services/`, `server/run_checker.gd` (see section 3) |
