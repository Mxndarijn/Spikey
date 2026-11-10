class_name RoomDef
extends RefCounted
## What one room kind is: when it can appear, how its walls, gravity and speed
## work, and which hazards it builds. Defined in code in RoomCatalog (gameplay
## data must be versioned with the sim, not edited as a resource).

enum WallMode { STATIC, TIDE, BLINK }
enum Speed { NORMAL, FAST, SLOW }

## Heights out of a portal for rooms with something deadly near the ceiling
## all the time (arrival_skip): a hop from 170 px peaks about 110 px down,
## clear of it.
const CEILING_ARRIVAL := 170 * SimConfig.SUB

var id := ""
## starter, mid, late, bonus, seasonal (for the picker's odds and the views).
var group := "starter"
## Lowest score at which the room can be picked.
var from_score := 0
## Out of a portal the room isn't picked when the bird comes in at a height
## in one of these ranges (sub-units, from and to in pairs): a player holding
## height there for SimConfig.ARRIVAL_BLIND ticks (it hops about 60 px up)
## runs into the hazards however they are timed. Empty = any height.
var arrival_skip := PackedInt32Array()
## Relative pick chance among the rooms allowed at a score.
var weight := 10
## Season the room belongs to (Seasons.*), or Seasons.NONE for all year.
var season := Seasons.NONE

# Walls
var spikes := true
var extra_spikes := 0
var gap := 4
var max_spikes := SimConfig.MAX_SPIKES
var wall_mode := WallMode.STATIC
## Walls step inward with every point scored in this room.
var squeeze := false
## Both walls slide this far in when the room starts (Narrow), sub-units.
var inset := 0
## The free run on a new wall and the next exit stay within this of the bird's
## height (sub-units). 0 = the usual rule: RoomRules.GAP_REACH for the free run
## in rooms with hazards, anywhere otherwise.
var reach := 0

# Movement
var gravity_sign := 1
var speed := Speed.NORMAL
## Whether the usual coin appears on a wall bounce.
var bounce_coin := true
## Coin Garden: a bounce adds a coin even when one is already out.
var bounce_coin_stacks := false

## Factories (Callables returning a Hazard), built at room start in order.
var hazards: Array[Callable] = []
## Alternatives: one of these lists is picked by the RNG and added (Double Trouble).
var combos: Array = []
## Ways the room can turn out: one is drawn by the RNG at room start. Empty =
## the room is always the same.
var variants: Array[RoomVariant] = []


func _init(p_id: String, p_group: String, p_from: int) -> void:
	id = p_id
	group = p_group
	from_score = p_from


func with(p_hazards: Array[Callable]) -> RoomDef:
	hazards = p_hazards
	return self


## Whether the room can be picked for a bird coming out of a portal at `y`.
func fits_arrival(y: int) -> bool:
	for i in range(0, arrival_skip.size(), 2):
		if y >= arrival_skip[i] and y < arrival_skip[i + 1]:
			return false
	return true
