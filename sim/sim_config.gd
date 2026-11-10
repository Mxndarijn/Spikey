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
## 7: a wall with an open exit has spikes everywhere except the opening(s);
##    the bird comes out of a portal flying level (no speed up or down).
## 8: Coin Garden allows up to three spikes per wall (was one).
## 9: Tide Spikes slide out to 1.5 times a normal spike (was 1 times).
## 10: exits sit on a spike slot's center, and the whole spike-free gap around
##     one leads through (no more bouncing between the portal and a spike).
##     Stalactite Run: out of a portal, the gap ahead stays at the bird's
##     height (it no longer moves up to 40 px before the player sees the room).
## 11: Coin Garden: every bounce adds a coin, even when one is already out.
## 12: out of a portal the bird waits ARRIVAL_HOLD ticks with the new room
##     frozen (taps ignored), so the player sees the room before flying on.
## 13: no points for bouncing while an exit is open (no farming points by
##     turning back off the Bumper Cloud).
## 14: each exit is planned one point early (on the 9th of every 10) and
##     shown as a ghost on the wall it will open on; no spikes in its slots.
## 15: revive (GameSim.revive): once per run a dead bird arrives in the same
##     room again as if through a portal. Runs without one play as in 14.
## 16: room rework from playtests. Narrow is a narrow cage (walls slide 50 px
##     in; free run and exit stay near the bird) instead of smaller gaps. Room
##     variants drawn at room start: Tide Spikes normal / big / small, Bumper
##     Cloud one or two clouds (Heart Bumpers always two). Hazards can keep an
##     exit off heights they block (Hazard.blocks_exit): Floating Isles,
##     Shutter Gates (wider gap too) and Caterpillar Crawl always leave a way
##     to the wall and the portal.
## 17: out of a portal the room ran in slow motion for a second instead of
##     the frozen wait (a revive still waits ARRIVAL_HOLD); Shutter Gates
##     times its gap to be at the bird's height when it reaches the nearer
##     gate.
## 18: no slow motion out of a portal: the room is laid out (up to
##     ARRIVAL_TRIES tries, ArrivalCheck) so a player who only holds height
##     for ARRIVAL_BLIND ticks can still live; Floating Isles keeps a longer
##     lane (200 px) clear in front of the bird, and Pinwheel's hub moves
##     off the bird's height.
const GAMEPLAY_VERSION := 18
## How often a run can be revived.
const MAX_REVIVES := 1
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
## Exits sit on a slot center, so the opening is that slot and one either side
## and the nearest spikes are two slots away. A bird whose center reaches the
## wall within EXIT_FIT of the exit goes through: that is the whole gap up to
## the next spike's base.
const EXIT_FIT := 2 * SLOT_SIZE - SPIKE_HALF_BASE
const EXIT_MIN_Y := 110 * SUB
const EXIT_MAX_Y := 530 * SUB
## Fork exits: one above this line, one below it.
const FORK_SPLIT_Y := 320 * SUB
const FORK_EVERY := 50
## Coins for taking the Wild exit.
const WILD_COINS := 3
## Ticks (1 s) of a frozen wait (SimState.arrival_hold: the bird and room
## wait, taps ignored) after a revive.
const ARRIVAL_HOLD := 60
## Out of a portal the room is laid out so a player who doesn't react for
## ARRIVAL_BLIND ticks (only holding height) can still live ARRIVAL_FOLLOW
## ticks after that; up to ARRIVAL_TRIES layouts are tried (ArrivalCheck).
const ARRIVAL_BLIND := 45
const ARRIVAL_FOLLOW := 90
const ARRIVAL_TRIES := 8

# Safety cap for replays (30 minutes of play).
const MAX_TICKS := 60 * 60 * 30


static func slot_center_y(slot: int) -> int:
	return SLOT_TOP + slot * SLOT_SIZE + SLOT_SIZE / 2
