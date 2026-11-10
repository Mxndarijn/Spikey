class_name SimCopy
extends RefCounted
## Deep copies a GameSim (state, room, hazards, RNGs), so the sim can try a
## room arrival on a copy (ArrivalCheck) without touching the real run.
## RoomDefs and Callables are shared (they never change during a run).


static func copy(sim: GameSim) -> GameSim:
	var out := GameSim.new(sim.seed_value, sim.season, sim.practice_room)
	var memo := {sim.get_instance_id(): out}
	_copy_fields(sim, out, memo)
	return out


static func _copy_fields(src: Object, dst: Object, memo: Dictionary) -> void:
	for p in src.get_property_list():
		if not (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var name: String = p.name
		dst.set(name, _copy_value(src.get(name), memo))


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
