class_name SimConfig
extends RefCounted
## Gameplay constants for the deterministic simulation.
##
## Changing ANY value here changes gameplay: bump GAMEPLAY_VERSION and
## regenerate the golden replays (tools/make_golden.gd).
## All lengths are integer sub-units (SUB per logical pixel); speeds are per tick.

const GAMEPLAY_VERSION := 1
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
const GRAVITY := 32
const FLAP_VY := -8 * SUB
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

# Safety cap for replays (30 minutes of play).
const MAX_TICKS := 60 * 60 * 30


static func slot_center_y(slot: int) -> int:
	return SLOT_TOP + slot * SLOT_SIZE + SLOT_SIZE / 2
