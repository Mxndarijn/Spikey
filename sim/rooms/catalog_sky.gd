extends RefCounted
## Rooms batch: sky and bonus rooms (air, bubbles and things that fall from the
## ceiling). Order is part of the rules (see RoomCatalog).
## Also home to two hazards used by seasonal rooms: mover.gd (Bat Loop, Bee
## Line) and firework.gd (Firework Burst).

const Updraft := preload("res://sim/hazards/updraft.gd")
const Bubble := preload("res://sim/hazards/bubble.gd")
const Drop := preload("res://sim/hazards/drop.gd")
const OrchardSpawner := preload("res://sim/hazards/orchard_spawner.gd")
const KeepyBall := preload("res://sim/hazards/keepy_ball.gd")

const SUB := SimConfig.SUB


static func defs() -> Array[RoomDef]:
	var out: Array[RoomDef] = []

	# Updraft: the middle lane pushes the bird up.
	var updraft := RoomDef.new("updraft", "mid", 60)
	updraft.hazards.append(func() -> Hazard: return Updraft.new())
	out.append(updraft)

	# Bubble Lift: rising bubbles carry the bird until a tap pops them.
	var bubbles := RoomDef.new("bubbles", "mid", 50)
	for lane in 3:
		bubbles.hazards.append(_bubble.bind(lane))
	out.append(bubbles)

	# Spike Rain: a mark on the ceiling, then a spiked drop falls down that column.
	var rain := RoomDef.new("rain", "late", 70)
	rain.weight = 8
	rain.hazards.append(_drop.bind(30, 10 * SUB, 25))
	rain.hazards.append(_drop.bind(70, 10 * SUB, 25))
	out.append(rain)

	# Orchard Drop: coins fall in columns, now and then a thorny pinecone too.
	var orchard := RoomDef.new("orchard", "bonus", 30)
	orchard.weight = 4
	orchard.max_spikes = 2
	orchard.bounce_coin = false
	orchard.skin = "pinecone"
	orchard.hazards.append(func() -> Hazard: return OrchardSpawner.new())
	orchard.hazards.append(_drop.bind(90, 6 * SUB, 140))
	out.append(orchard)

	# Keepy-Uppy: bump the soft ball to keep it up; every bump pays a coin.
	var keepy := RoomDef.new("keepy", "bonus", 40)
	keepy.weight = 4
	keepy.max_spikes = 3
	keepy.hazards.append(func() -> Hazard: return KeepyBall.new())
	out.append(keepy)

	return out


static func _bubble(lane: int) -> Hazard:
	return Bubble.new(lane)


static func _drop(delay: int, speed: int, gap: int) -> Hazard:
	return Drop.new(delay, speed, gap)
