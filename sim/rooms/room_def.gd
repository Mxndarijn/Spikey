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
## Lowest score at which the room can be picked: the first score of `pace`
## (RoomPacing.apply sets it).
var from_score := 0
## Out of a portal the room isn't picked when the bird comes in at a height
## in one of these ranges (sub-units, from and to in pairs): a player holding
## height there for SimConfig.ARRIVAL_BLIND ticks (it hops about 60 px up)
## runs into the hazards however they are timed. Empty = any height.
var arrival_skip := PackedInt32Array()
## Not used by the picker any more (RoomPacing gives every room its curve).
var weight := 10
## Relative pick chance over the score (RoomPacing): score, weight pairs.
## Empty = never picked by RoomCatalog.pick_next.
var pace := PackedInt32Array()
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
## Whether a wall bounce scores a point (Buttons: only its presses do).
var bounce_points := true
## Whether the usual coin appears on a wall bounce.
var bounce_coin := true
## Coin Garden: a bounce adds a coin even when one is already out.
var bounce_coin_stacks := false
## A boss room (SimConfig.BOSS_EVERY): never picked by the usual picker, only
## by RoomCatalog.pick_boss; its exit opens after SimConfig.BOSS_POINTS bounces.
var boss := false

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


## The room's pick weight at `score` (RoomPacing.weight of its curve).
func weight_at(score: int) -> int:
	return RoomPacing.weight(pace, score)


## Whether the room can be picked for a bird coming out of a portal at `y`:
## not a height it skips, and (with variants) at least one variant fits.
func fits_arrival(y: int) -> bool:
	for i in range(0, arrival_skip.size(), 2):
		if y >= arrival_skip[i] and y < arrival_skip[i + 1]:
			return false
	return variants.is_empty() or not arrival_variants(y).is_empty()


## Indexes of the variants that can be drawn out of a portal at `y`
## (RoomVariant.arrival_skip).
func arrival_variants(y: int) -> Array[int]:
	var out: Array[int] = []
	for i in variants.size():
		if variants[i].fits_arrival(y):
			out.append(i)
	return out


## Whether an arrival here can draw another variant than a generated one the
## room seed drew (GameSim._arrival_retries' second pass): two or more variants,
## one of them generated.
func has_generated_choice() -> bool:
	if variants.size() < 2:
		return false
	for v in variants:
		if v.kind == RoomVariant.Kind.GENERATED:
			return true
	return false


## Whether the room or any of its variants skips some heights out of a portal.
func skips_heights() -> bool:
	if not arrival_skip.is_empty():
		return true
	for v in variants:
		if not v.arrival_skip.is_empty():
			return true
	return false
