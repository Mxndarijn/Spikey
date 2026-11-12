extends TestCase
## Hazard.warnings(): the tells on screen as boxes with an eta and a duration,
## the bots' one shared reading of them. Every room variant is played for a
## while; each warning must count down one step a tick and then come true
## (the hazard kills somewhere in its box inside the announced window), and
## asking for warnings must never change the sim.

const TICKS := 420
## Probe spacing inside a warning's box.
const GRID := 10 * SimConfig.SUB
## Kinds (Hazard.kind) whose warnings must be seen and come true in the catalog.
const MUST_TELL: Array[String] = [
	"beam", "piston", "dart", "drop", "crate_drop", "bubble", "firework"
]

var _shown := {}
var _true := {}
var _false := {}
var _late: Array[String] = []


func test_warnings_count_down_and_come_true() -> void:
	_shown.clear()
	_true.clear()
	_false.clear()
	_late.clear()
	var defs := RoomCatalog.all()
	for index in defs.size():
		var def: RoomDef = defs[index]
		if def.variants.is_empty():
			_play(index, def, "")
		for v: RoomVariant in def.variants:
			_play(index, def, v.id)
	assert_eq(_late.size(), 0, "eta must drop by one a tick: %s" % ", ".join(_late.slice(0, 5)))
	for kind: String in MUST_TELL:
		assert_true(_shown.get(kind, 0) > 0, "%s shows warnings" % kind)
		var ok: int = _true.get(kind, 0)
		var bad: int = _false.get(kind, 0)
		# A slam or crate that an exit's mouth stops (ExitZone) never lands: rare.
		assert_true(ok >= 1 and bad * 10 <= ok, "%s warnings come true (%d of %d)" % [kind, ok, ok + bad])


func test_warnings_change_nothing() -> void:
	var defs := RoomCatalog.all()
	for index in defs.size():
		var def: RoomDef = defs[index]
		var sim := GameSim.new(900 + index, def.season, index, "")
		for tick in 150:
			if sim.is_over():
				break
			var before := sim.checksum()
			var w := sim.warnings()
			assert_eq(w.size() % Hazard.WARN_SIZE, 0, def.id)
			if sim.checksum() != before:
				assert_true(false, "warnings() changed the sim in %s" % def.id)
				return
			sim.step(_hover(sim))


## Taps to stay near the height the room began at.
func _hover(sim: GameSim) -> bool:
	if not sim.state.started:
		return true
	var g := sim.room.gravity
	return (sim.state.y - SimConfig.BIRD_START_Y) * g > 0 and sim.state.vy * g >= 0


func _play(index: int, def: RoomDef, variant: String) -> void:
	var sim := GameSim.new(500 + 7 * index + variant.length(), def.season, index, variant)
	# Warnings on screen last tick: key -> eta. Waiting to come true: [hazard, box.., from, to].
	var last := {}
	var open: Array = []
	for tick in TICKS:
		if sim.is_over() or sim.state.room_index != 0:
			break
		var now := {}
		var hazards := sim.room.hazards
		for i in hazards.size():
			var h: Hazard = hazards[i]
			if not h.alive:
				continue
			var w := PackedInt64Array()
			h.warnings(sim, w)
			for k in range(0, w.size(), Hazard.WARN_SIZE):
				var key := "%d:%d:%d:%d:%d:%d" % [i, w[k], w[k + 1], w[k + 2], w[k + 3], w[k + 6]]
				var eta := w[k + 4]
				now[key] = eta
				if last.has(key):
					var was: int = last[key]
					if eta != was - 1 and not (eta == 0 and was == 0):
						_late.append("%s/%s %s %d -> %d" % [def.id, variant, h.kind, was, eta])
					continue
				_shown[h.kind] = _shown.get(h.kind, 0) + 1
				if w[k + 6] == Hazard.WARN_KILL and eta > 0:
					var t := sim.state.tick
					open.append(
						[h, w[k], w[k + 1], w[k + 2], w[k + 3], t + eta - 1, t + eta + w[k + 5] + 1]
					)
		last = now
		for j in range(open.size() - 1, -1, -1):
			var o: Array = open[j]
			var h: Hazard = o[0]
			if sim.state.tick < o[5]:
				continue
			if _kills_in(sim, h, o[1], o[2], o[3], o[4]):
				_true[h.kind] = _true.get(h.kind, 0) + 1
				open.remove_at(j)
			elif sim.state.tick > o[6]:
				_false[h.kind] = _false.get(h.kind, 0) + 1
				open.remove_at(j)
		sim.step(_hover(sim))


## True if `h` kills a bird somewhere in the box right now.
func _kills_in(sim: GameSim, h: Hazard, x0: int, y0: int, x1: int, y1: int) -> bool:
	var keep_x := sim.state.x
	var keep_y := sim.state.y
	var hit := false
	var y := maxi(y0, SimConfig.KILL_TOP + SimConfig.BIRD_RADIUS)
	var bottom := mini(y1, SimConfig.KILL_BOTTOM - SimConfig.BIRD_RADIUS)
	while y <= bottom and not hit:
		var x := x0
		while x <= x1 and not hit:
			sim.state.x = x
			sim.state.y = y
			hit = h.kills(sim)
			x += GRID
		y += GRID
	sim.state.x = keep_x
	sim.state.y = keep_y
	return hit
