extends TestCase
## Bumper Cloud: a cloud turning the bird back is not a wall bounce. Wall spikes
## change only when the bird bounces off a wall (GameSim._walls_after_bounce),
## once per bounce, so a cloud hit never takes spikes off a wall.

const STEPS := 2400


static func _cloud_sim(seed_value: int, variant: String) -> GameSim:
	var index := RoomCatalog.index_of("cloud")
	return GameSim.new(seed_value, RoomCatalog.all()[index].season, index, variant)


## The height of the cloud nearest the bird, so the bird flies into clouds.
static func _cloud_y(sim: GameSim) -> int:
	var best := SimConfig.KILL_TOP
	var best_d := -1
	for h in sim.room.hazards:
		if h.kind != "bumper":
			continue
		var d := absi(h.x - sim.state.x)
		if best_d < 0 or d < best_d:
			best_d = d
			best = h.y
	return best


## Plays the cloud room (the bird can't die, it chases the clouds' height) and
## returns every step at which a wall's spikes changed with no wall drawn:
## "seed/variant tick side".
static func _walls_changed_off_bounce(seed_value: int, variant: String) -> Array[String]:
	var out: Array[String] = []
	var sim := _cloud_sim(seed_value, variant)
	var room := sim.state.room_index
	sim.step(true)
	for tick in STEPS:
		var left := sim.state.left_spikes
		var right := sim.state.right_spikes
		var walls := sim.room.walls
		sim.state.alive = true
		var tap := sim.state.y > _cloud_y(sim) and sim.state.vy > 0
		sim.step(tap)
		if sim.state.room_index != room:
			break
		if sim.room.walls != walls:
			continue
		if sim.state.left_spikes != left:
			out.append("%d/%s %d left" % [seed_value, variant, tick])
		if sim.state.right_spikes != right:
			out.append("%d/%s %d right" % [seed_value, variant, tick])
	return out


func test_a_cloud_hit_never_changes_a_wall() -> void:
	var bad: Array[String] = []
	for variant in ["one", "two"]:
		for seed_value in range(1, 13):
			bad.append_array(_walls_changed_off_bounce(seed_value, variant))
	assert_eq(bad.size(), 0, "walls changed with no bounce: %s" % ", ".join(bad.slice(0, 12)))


func test_a_turn_back_keeps_the_wall_the_bird_heads_to() -> void:
	var sim := _cloud_sim(3, "one")
	sim.step(true)
	var cloud: Hazard = sim.room.hazards[0]
	sim.state.left_spikes = 0b101
	sim.state.right_spikes = 0b110
	# Heading right, left of the cloud: turned back to the left wall.
	sim.state.vx = SimConfig.SPEED_X
	sim.state.x = cloud.x - 10 * SimConfig.SUB
	sim.state.y = cloud.y
	sim.bump_bird_from(cloud.x, cloud.y)
	assert_true(sim.state.vx < 0, "turned back")
	assert_eq(sim.state.left_spikes, 0b101, "the wall it heads to keeps its spikes")
	assert_eq(sim.state.right_spikes, 0b110, "the other wall too")
	# Heading left, right of the cloud: turned back to the right wall.
	sim.state.x = cloud.x + 10 * SimConfig.SUB
	sim.bump_bird_from(cloud.x, cloud.y)
	assert_true(sim.state.vx > 0, "turned back again")
	assert_eq(sim.state.right_spikes, 0b110, "the right wall keeps its spikes")
	assert_eq(sim.state.left_spikes, 0b101, "the left wall keeps its spikes")
