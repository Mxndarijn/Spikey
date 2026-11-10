extends TestCase
## SimCopy: a copy has every field of the sim, shares nothing that changes,
## and plays on exactly like the original.

## Ticks played before copying, and after it.
const BEFORE := 150
const AFTER := 200


## A practice run in room `index`, played for `ticks` with a simple tap pattern
## (dying is fine: a dead sim is copied too).
static func played(index: int, ticks: int) -> GameSim:
	var def: RoomDef = RoomCatalog.all()[index]
	var sim := GameSim.new(1000 + index, def.season, index)
	for i in ticks:
		sim.step(_tap(i))
	return sim


static func _tap(i: int) -> bool:
	return i % 23 == 0 or i % 37 == 5


func test_copy_matches_the_original_in_every_room() -> void:
	for index in RoomCatalog.all().size():
		var sim := played(index, BEFORE)
		var copy := SimCopy.copy(sim)
		var id: String = RoomCatalog.all()[index].id
		var diffs: Array[String] = []
		_compare(sim, copy, id, diffs, {})
		assert_true(diffs.is_empty(), "%s: %s" % [id, ", ".join(diffs.slice(0, 5))])


func test_copy_plays_on_like_the_original() -> void:
	for index in RoomCatalog.all().size():
		var sim := played(index, BEFORE)
		var copy := SimCopy.copy(sim)
		var id: String = RoomCatalog.all()[index].id
		for i in AFTER:
			sim.step(_tap(BEFORE + i))
			copy.step(_tap(BEFORE + i))
		var diffs: Array[String] = []
		_compare(sim, copy, id, diffs, {})
		assert_true(diffs.is_empty(), "%s after %d ticks: %s" % [id, AFTER, ", ".join(diffs)])


func test_playing_the_copy_leaves_the_original_alone() -> void:
	for index in RoomCatalog.all().size():
		var sim := played(index, BEFORE)
		var twin := played(index, BEFORE)
		var copy := SimCopy.copy(sim)
		for i in AFTER:
			copy.step(i % 9 == 0)
		var diffs: Array[String] = []
		_compare(sim, twin, RoomCatalog.all()[index].id, diffs, {})
		assert_true(diffs.is_empty(), "original changed: %s" % ", ".join(diffs))


## Every script variable of a hazard, base class ones included, is copied.
func test_every_field_is_copied() -> void:
	var seen := {}
	for index in RoomCatalog.all().size():
		var sim := played(index, 1)
		var objects: Array[Object] = [sim, sim.state, sim.room]
		objects.append_array(sim.room.hazards)
		for o in objects:
			var script: Script = o.get_script()
			if seen.has(script):
				continue
			seen[script] = true
			var planned := {}
			for field: Array in SimCopy._plan(script):
				planned[String(field[0])] = true
			for p in o.get_property_list():
				if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
					assert_true(
						planned.has(p.name), "%s.%s is copied" % [script.resource_path, p.name]
					)
	assert_true(seen.size() > 20, "many classes checked (%d)" % seen.size())


## Two sims hold equal values, and no object of one is used by the other
## (except shared read-only data).
static func _compare(
	a: Variant, b: Variant, path: String, out: Array[String], seen: Dictionary
) -> void:
	if typeof(a) != typeof(b):
		out.append("%s: type" % path)
		return
	match typeof(a):
		TYPE_OBJECT:
			if a == null or b == null:
				if a != b:
					out.append("%s: null" % path)
				return
			if a is RoomDef or a is Resource or a is Script:
				if a != b:
					out.append("%s: other shared data" % path)
				return
			if a == b:
				out.append("%s: same object in both" % path)
				return
			if seen.has(a.get_instance_id()):
				return
			seen[a.get_instance_id()] = true
			if a.get_script() != b.get_script():
				out.append("%s: script" % path)
				return
			for p in a.get_property_list():
				if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
					_compare(a.get(p.name), b.get(p.name), path + "." + p.name, out, seen)
		TYPE_ARRAY:
			if is_same(a, b) and not a.is_read_only():
				out.append("%s: same array in both" % path)
				return
			if a.size() != b.size():
				out.append("%s: size %d, %d" % [path, a.size(), b.size()])
				return
			for i in a.size():
				_compare(a[i], b[i], "%s[%d]" % [path, i], out, seen)
		TYPE_DICTIONARY:
			if a.keys() != b.keys():
				out.append("%s: keys" % path)
				return
			for k: Variant in a:
				_compare(a[k], b[k], "%s[%s]" % [path, k], out, seen)
		_:
			if a != b:
				out.append("%s: %s, %s" % [path, a, b])
