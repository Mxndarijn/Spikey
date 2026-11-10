class_name SimClone
extends RefCounted
## Deep copies a GameSim (state, room, hazards, RNGs), so a planner can try
## "what if I tap now?" without touching the real run. Test/tool code only.
## RoomDefs and Callables are shared (they never change during a run).
##
## The bots copy the sim thousands of times a second, so the core objects
## (GameSim, SimState, RoomRuntime, SimRng) are copied field by field by hand;
## hazards (many kinds, few per room) go through the generic copy below.
## test_sim_clone checks that the hand-copied field lists still match the
## classes, so a new sim field cannot be silently left out.

## Fields copied by hand, per class. Must list every script variable.
const GAME_SIM_FIELDS: Array[StringName] = [
	&"seed_value", &"season", &"practice_room", &"state", &"room", &"events", &"_rng"
]
const ROOM_FIELDS: Array[StringName] = [
	&"def",
	&"index",
	&"t",
	&"ticks",
	&"points",
	&"variant",
	&"hazards",
	&"tide_left",
	&"tide_right",
	&"tide_salt",
	&"blink_left",
	&"blink_right",
]
const RNG_FIELDS: Array[StringName] = [&"_s0", &"_s1", &"_s2", &"_s3"]

## Script -> its script variable names. get_property_list() is slow (about
## 30 us an object).
static var _fields := {}


static func copy(sim: GameSim) -> GameSim:
	# The first room is the cheapest to build; every field is replaced below.
	var out := GameSim.new(sim.seed_value)
	out.season = sim.season
	out.practice_room = sim.practice_room
	out.state = sim.state.copy()
	out.events = sim.events.duplicate()
	out._rng = copy_rng(sim._rng)
	var memo := {sim.get_instance_id(): out}
	out.room = _copy_room(sim.room, memo)
	return out


static func copy_rng(rng: SimRng) -> SimRng:
	var out := SimRng.new()
	out._s0 = rng._s0
	out._s1 = rng._s1
	out._s2 = rng._s2
	out._s3 = rng._s3
	return out


static func _copy_room(src: RoomRuntime, memo: Dictionary) -> RoomRuntime:
	var dst := RoomRuntime.new()
	memo[src.get_instance_id()] = dst
	dst.def = src.def
	dst.index = src.index
	dst.t = src.t
	dst.ticks = src.ticks
	dst.points = src.points
	dst.variant = src.variant
	dst.tide_left = src.tide_left
	dst.tide_right = src.tide_right
	dst.tide_salt = src.tide_salt
	dst.blink_left = src.blink_left
	dst.blink_right = src.blink_right
	var hazards: Array[Hazard] = []
	hazards.resize(src.hazards.size())
	for i in src.hazards.size():
		hazards[i] = _copy_object(src.hazards[i], memo)
	dst.hazards = hazards
	return dst


## Every script variable name of `o`'s class, cached.
static func field_names(o: Object) -> Array[StringName]:
	var script: Script = o.get_script()
	var cached: Variant = _fields.get(script)
	if cached != null:
		return cached
	var names: Array[StringName] = []
	for p in o.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(StringName(p.name))
	_fields[script] = names
	return names


## The old, fully generic deep copy (slow). Kept so tests can check the fast
## copy against it.
static func copy_generic(sim: GameSim) -> GameSim:
	var out := GameSim.new(sim.seed_value, sim.season, sim.practice_room)
	var memo := {sim.get_instance_id(): out}
	_copy_fields(sim, out, memo)
	return out


static func _copy_fields(src: Object, dst: Object, memo: Dictionary) -> void:
	for name: StringName in field_names(src):
		dst.set(name, _copy_value(src.get(name), memo))


static func _copy_value(v: Variant, memo: Dictionary) -> Variant:
	match typeof(v):
		TYPE_OBJECT:
			return _copy_object(v, memo)
		TYPE_ARRAY:
			var arr: Array = v
			# Typed arrays of plain values (Array[int] and the like) hold
			# nothing to deep copy.
			var typed := arr.get_typed_builtin()
			if typed != TYPE_NIL and typed != TYPE_OBJECT and typed != TYPE_ARRAY:
				if typed != TYPE_DICTIONARY:
					return arr.duplicate(false)
			var out := arr.duplicate(false)
			for i in out.size():
				out[i] = _copy_value(arr[i], memo)
			return out
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var out := {}
			for k: Variant in d:
				out[k] = _copy_value(d[k], memo)
			return out
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_BYTE_ARRAY:
			return v.duplicate()
	return v


static func _copy_object(o: Object, memo: Dictionary) -> Variant:
	if o == null:
		return null
	# Shared, read-only data.
	if o is RoomDef or o is Resource or o is Script:
		return o
	var id := o.get_instance_id()
	if memo.has(id):
		return memo[id]
	var script: Script = o.get_script()
	if script == null:
		return o
	var copy: Object = script.new()
	memo[id] = copy
	_copy_fields(o, copy, memo)
	return copy
