class_name RoomDef
extends RefCounted
## What one room kind is: when it can appear, how its walls, gravity and speed
## work, and which hazards it builds. Defined in code in RoomCatalog (gameplay
## data must be versioned with the sim, not edited as a resource).

enum WallMode { STATIC, TIDE, BLINK }
enum Speed { NORMAL, FAST, SLOW }

var id := ""
## starter, mid, late, bonus, seasonal (for the picker's odds and the views).
var group := "starter"
## Lowest score at which the room can be picked.
var from_score := 0
## Relative pick chance among the rooms allowed at a score.
var weight := 10
## Season the room belongs to (Seasons.*), or Seasons.NONE for all year.
var season := Seasons.NONE
## Cosmetic variant for the painters ("pumpkin" draws Bramble Ball as a pumpkin).
var skin := ""

# Walls
var spikes := true
var extra_spikes := 0
var gap := 4
var max_spikes := SimConfig.MAX_SPIKES
var wall_mode := WallMode.STATIC
## Walls step inward with every point scored in this room.
var squeeze := false

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


func _init(p_id: String, p_group: String, p_from: int) -> void:
	id = p_id
	group = p_group
	from_score = p_from


func with(p_hazards: Array[Callable]) -> RoomDef:
	hazards = p_hazards
	return self
