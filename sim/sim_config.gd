class_name SimConfig
extends RefCounted
## Gameplay constants for the deterministic simulation.
##
## Changing ANY value here changes gameplay: bump GAMEPLAY_VERSION and
## regenerate the golden replays (tools/make_golden.gd).
## All lengths are integer sub-units (SUB per logical pixel); speeds are per tick.

## 2: coins (one spawns on a wall bounce when none is out).
## 3: the room system (RoomCatalog): many room kinds with hazards, seasons.
## 4: floatier flap: 300 px/s up, 750 px/s^2 gravity (apex after ~0.4 s, ~60 px).
## 5: exit portals: rooms change by flying through an exit (the bird flies
##    straight on); every 50 points a Calm/Wild fork picks the route.
## 6: room tuning from playtests (fairer gates, stalactites, saw ring, beams,
##    updraft, pads); the bird comes out of a portal in the opposite wall and
##    keeps flying the same way; the open first room never comes back.
const GAMEPLAY_VERSION := 6
const TICKS_PER_SECOND := 60
const SUB := 64

# World: 360 x 640 logical pixels.
const WORLD_W := 360 * SUB
const WORLD_H := 640 * SUB

# Bird. Same hitbox for every character.
const BIRD_RADIUS := 14 * SUB
const BIRD_START_X := 180 * SUB
const BIRD_START_Y := 300 * SUB
const SPEED_X := 4 * SUB
## A flap SETS vy (never adds), so every tap gives the same ~60 px hop that peaks
## after ~0.4 s, however fast the bird was falling. 750 px/s^2 = 13 sub/tick^2.
const GRAVITY := 13
## 300 px/s = 5 px/tick.
const FLAP_VY := -5 * SUB
const MAX_FALL_VY := 12 * SUB

# Ceiling and floor are always deadly: the bird dies when its edge passes these lines.
const KILL_TOP := 34 * SUB
const KILL_BOTTOM := 606 * SUB

# Side walls: SLOT_COUNT spike slots stacked from SLOT_TOP.
const SLOT_TOP := 60 * SUB
const SLOT_SIZE := 40 * SUB
const SLOT_COUNT := 13
const SPIKE_DEPTH := 26 * SUB
const SPIKE_HALF_BASE := 15 * SUB

# Progression.
const POINTS_PER_ROOM := 10
const BASE_SPIKES := 2
const POINTS_PER_EXTRA_SPIKE := 6
const MAX_SPIKES := 8

# Coins: at most one in the room. A wall bounce places one at a random spot in
# this box (clear of the wall spikes, ceiling and floor) when none is out.
const COIN_RADIUS := 12 * SUB
const COIN_MIN_X := 80 * SUB
const COIN_MAX_X := 280 * SUB
const COIN_MIN_Y := 90 * SUB
const COIN_MAX_Y := 550 * SUB

# Exits: every POINTS_PER_ROOM points an exit opens on the wall the bird is
# heading to. Fly into it to reach the next room: the bird comes out of the
# opposite wall, still flying the same way. Every FORK_EVERY points there are
# two exits, Calm and Wild, and the one taken sets the route until the next fork.
const EXIT_HALF := 48 * SUB
const EXIT_MIN_Y := 110 * SUB
const EXIT_MAX_Y := 530 * SUB
## Fork exits: one above this line, one below it.
const FORK_SPLIT_Y := 320 * SUB
const FORK_EVERY := 50
## Coins for taking the Wild exit.
const WILD_COINS := 3

# Safety cap for replays (30 minutes of play).
const MAX_TICKS := 60 * 60 * 30


static func slot_center_y(slot: int) -> int:
	return SLOT_TOP + slot * SLOT_SIZE + SLOT_SIZE / 2
