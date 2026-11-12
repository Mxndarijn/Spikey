class_name SimCopy
extends RefCounted
## Deep copies a GameSim (state, room, hazards, RNGs), so the sim can try a
## room arrival on a copy (ArrivalCheck) without touching the real run, and
## planners and searches in tests can try many futures.
## RoomDefs and Callables are shared (they never change during a run).
##
## It runs thousands of times per second, so it is quick: the copy starts from
## a blank GameSim (no room built only to be thrown away), and each class's
## fields are listed once, then copied straight. Every script variable is
## copied, so a field added later is copied too (tests/unit/test_sim_copy.gd).

## How a field is copied.
enum Mode { VALUE, SHALLOW, DEEP }

## Script instance id -> its fields, [name, Mode] pairs, worked out on first
## use. (Keyed by id, so the cache doesn't keep scripts alive at exit.)
static var _plans := {}


static func copy(sim: GameSim) -> GameSim:
	var out := GameSim.new(sim.seed_value, sim.season, GameSim.FOR_COPY)
	var memo := {sim.get_instance_id(): out}
	_copy_fields(sim, out, memo)
	return out


## Deep copies a room (its hazards too), for a revive (GameSim._entry_room).
static func copy_room(room: RoomRuntime) -> RoomRuntime:
	return _copy_object(room, {}) as RoomRuntime


## Copies an RNG (its state), for a revive (GameSim._entry_rng).
static func copy_rng(rng: SimRng) -> SimRng:
	return _copy_object(rng, {}) as SimRng


static func _copy_fields(src: Object, dst: Object, memo: Dictionary) -> void:
	for field: Array in _plan(src.get_script()):
		var name: StringName = field[0]
		match field[1]:
			Mode.VALUE:
				dst.set(name, src.get(name))
			Mode.SHALLOW:
				dst.set(name, src.get(name).duplicate())
			_:
				dst.set(name, _copy_value(src.get(name), memo))


## The fields of a script and how each is copied.
static func _plan(script: Script) -> Array:
	var id := script.get_instance_id()
	if _plans.has(id):
		return _plans[id]
	var plan := []
	for p in script.get_script_property_list():
		if not (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		plan.append([StringName(p.name), _mode(p)])
	_plans[id] = plan
	return plan


static func _mode(p: Dictionary) -> Mode:
	match p.type:
		TYPE_OBJECT, TYPE_DICTIONARY:
			return Mode.DEEP
		TYPE_ARRAY:
			# A typed array of plain values only needs its own copy.
			var plain := ["int", "bool", "String", "StringName"]
			if p.hint == PROPERTY_HINT_ARRAY_TYPE and p.hint_string in plain:
				return Mode.SHALLOW
			return Mode.DEEP
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_BYTE_ARRAY:
			return Mode.SHALLOW
		TYPE_NIL:
			# Untyped: whatever it holds.
			return Mode.DEEP
	return Mode.VALUE


static func _copy_value(v: Variant, memo: Dictionary) -> Variant:
	match typeof(v):
		TYPE_OBJECT:
			return _copy_object(v, memo)
		TYPE_ARRAY:
			var arr: Array = v
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
