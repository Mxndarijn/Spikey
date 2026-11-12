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
##    straight on); every 50 points a Calm/Wild fork: Wild pays more and its next room is harder.
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
##     ARRIVAL_TRIES tries, ArrivalCheck: two simple players must live) so a
##     player who only holds height for ARRIVAL_BLIND ticks (then 0.75 s) can
##     still live. Out of a portal Floating Isles keeps a 200 px lane clear,
##     Pinwheel and Saw Ring move off the bird's height, Ghost Doors time
##     their fade for it and Bee Line keeps its bees off its way. Ghost Doors
##     sit 40 px lower.
## 19: ARRIVAL_BLIND 1 s. Out of a portal: the bird stays ARRIVAL_EDGE off
##     the ceiling and floor lines; Bee Line, Bat Loop, Lantern Swing and
##     Ghost Doors time themselves to the path of a player holding height
##     (FairLanes.arrival_path); a wall the bird reaches while still reading
##     (fast or narrow rooms) keeps that player's hops free of spikes; the
##     picker skips rooms at heights they can't take (RoomDef.arrival_skip:
##     Shutter Gates, Stalactite Run, Caterpillar Crawl, Crab Walk, Gift Drop
##     and Bubble Lift near the ceiling, Shutter Gates near the floor, Bee
##     Line and Lantern Swing in the middle).
## 20: room variants almost everywhere, drawn at room start (and forceable for
##     tools: GameSim.forced_variant). New variants for Bramble Ball, Pinwheel
##     (smaller wheel), Spike Rain, Lantern Swing, Updraft (Twin and Up & Down
##     skip high portal arrivals), Stalker Rail kept as is, and 54 more across
##     28 rooms (walls, isles and doors, crawlers and balls, machines and drops,
##     orbits and projectiles, coins and bubbles). Saw Ring grows and shrinks in
##     1.5 s. Double Trouble pairs follow combo rules (the piston slams inside
##     the pinwheel's band, beams skip a turn while the ball is in their row,
##     1 s warnings, Saw Ring + Spike Rain replaces Saw Ring + Stalker, only
##     pairs that fit the bird's height out of a portal). Five new rooms:
##     Crosswind, Spike Belt, Locked Out, Lava Rise, Echo. The free run stays
##     near the bird in rooms whose hazards are only in variants.
## 21: Locked Out is harder: a lockdown adds wall spikes, the lock gives up after
##     8 bounces, new Three keys and Four keys variants (keys placed from the
##     seed, every key reachable) and a key chain; Two keys is retired. A revive
##     restarts the room as the bird entered it, at its portal, and plans the
##     exit again, instead of rebuilding the room from the RNG.
const GAMEPLAY_VERSION := 21
## How often a run can be revived.
const MAX_REVIVES := 1
const TICKS_PER_SECOND := 60
## Every beam (Beam Gates, the Watcher) and every boss tell (the Crusher's slam,
## jaw and crates, the Saw King's hops and ring) warns this long first: 2 s.
const WARN_TICKS := 2 * TICKS_PER_SECOND
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

# Exits: every POINTS_PER_ROOM points an exit opens on the right wall
# (EXIT_WALL). Fly into it to reach the next room: the bird comes out of the
# opposite wall, still flying the same way. Every FORK_EVERY points there are
# two exits, Calm and Wild. Both lead to the same door (FORK_DOOR_Y) of the same
# next room, so every player meets the same map again; Wild pays WILD_COINS and
# plays that one room with WILD_SPIKES more on each wall after the first.
## The wall every exit and ghost is on: 1, right. Every room starts with the
## bird heading there (out of a portal in the left wall), and the Bumper Cloud
## turning the bird back never moves it, so every player of a seed leaves each
## room the same way.
const EXIT_WALL := 1
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
## The height of the door both fork exits lead to: the room behind a fork is
## laid out for this height whichever exit the bird took.
const FORK_DOOR_Y := FORK_SPLIT_Y
## Coins for taking the Wild exit.
const WILD_COINS := 5
## Extra spikes per wall in the room behind a Wild exit (every wall after the
## arrival's, so the arrival layout is the same for Calm and Wild).
const WILD_SPIKES := 3
## Boss rooms: the exit at every BOSS_EVERY points leads into one (RoomDef.boss,
## RoomCatalog.pick_boss). A boss room's exit opens after BOSS_POINTS bounces
## there (none at the usual POINTS_PER_ROOM), and a boss's exit is the fork
## (ExitPlanner.is_fork). Out of its portal the room waits BOSS_HOLD ticks.
const BOSS_EVERY := 100
const BOSS_POINTS := 20
const BOSS_HOLD := 90
## Coins paid when a boss breaks, by tier (score / BOSS_EVERY: 1, 2, 3 and up).
const BOSS_COINS: Array[int] = [15, 20, 25]
## Ticks (1 s) of a frozen wait (SimState.arrival_hold: the bird and room
## wait, taps ignored) after a revive.
const ARRIVAL_HOLD := 60
## Ticks (0.5 s) of the same frozen wait out of every portal: the room is laid
## out from the seed alone (SimState.anchor_y), not for the bird's own height,
## so the player gets half a second to look before the bird flies on. It counts
## toward ARRIVAL_BLIND (ArrivalCheck steps through it). Where no layout is fair
## for every bird in the exit, the wait is ARRIVAL_BLIND (GameSim._arrival_retries).
const PORTAL_HOLD := 30
## Out of a portal the room is laid out so a player who doesn't react for
## ARRIVAL_BLIND ticks (only holding height) can still live ARRIVAL_FOLLOW
## ticks after that; up to ARRIVAL_TRIES layouts are tried (ArrivalCheck).
const ARRIVAL_BLIND := 60
const ARRIVAL_FOLLOW := 120
const ARRIVAL_TRIES := 16
## Out of a portal the bird comes out at least this far from the ceiling and
## floor lines (it may have flown through the very top or bottom of the exit):
## a player holding height hops about 60 px, plus the bird, plus a margin.
const ARRIVAL_EDGE := 84 * SUB

# Safety cap for replays (30 minutes of play).
const MAX_TICKS := 60 * 60 * 30


## A boss room's tier for the score it was entered at: 1 at the first
## BOSS_EVERY points, 2 at the second, 3 from the third on.
static func boss_tier(entry_score: int) -> int:
	return clampi(entry_score / BOSS_EVERY, 1, BOSS_COINS.size())


static func slot_center_y(slot: int) -> int:
	return SLOT_TOP + slot * SLOT_SIZE + SLOT_SIZE / 2
