extends TestCase
## Flyers, trails and ambient particles match their design boards ("Six new
## flyers", "Eight new trails", "Ambient particles per world", "Six new
## worlds") and never borrow a world's spike colour.

const BOARD_TRAILS := [
	"rainbow_ribbon",
	"bubble_stream",
	"comet_tail",
	"confetti",
	"star_dust",
	"leaf_swirl",
	"music_notes",
	"pixel_trail",
]


func _spike_colours() -> Dictionary:
	var out := {}
	for t in ThemeCatalog.all():
		out[t.spike.to_html(false)] = t.id
	return out


func _trail_colours(t: TrailStyle) -> Array[Color]:
	var out: Array[Color] = [t.head_color, t.tail_color, t.preview_color]
	for c in t.colors:
		out.append(c)
	return out


## Spikes are the only thing drawn in a world's spike colour.
func test_no_trail_or_particle_colour_is_a_spike_colour() -> void:
	var spikes := _spike_colours()
	for t in Catalog.trails():
		for c in _trail_colours(t):
			var hex := c.to_html(false)
			assert_false(spikes.has(hex), "%s uses %s, the %s spike" % [t.id, hex, spikes.get(hex)])
	var fixed: Array = [
		TrailPainter.INK,
		TrailPainter.NOTE_DOT,
		TrailPainter.LEAF_VEIN,
		TrailPainter.STAR_DOT,
	]
	fixed.append_array(RoomView.SPRINKLE_COLORS)
	for c: Color in fixed:
		var hex := c.to_html(false)
		assert_false(spikes.has(hex), "drawing colour %s is the %s spike" % [hex, spikes.get(hex)])


func test_every_board_trail_is_in_the_shop() -> void:
	for id in BOARD_TRAILS:
		var t := Catalog.trail(id)
		assert_true(t != null, "%s is in the catalog" % id)
		assert_true(Shop.price(Catalog.TRAIL, id) > 0, "%s has a price" % id)


func test_board_prices() -> void:
	var trails := {
		"rainbow_ribbon": 300,
		"bubble_stream": 250,
		"comet_tail": 400,
		"confetti": 350,
		"star_dust": 400,
		"leaf_swirl": 300,
		"music_notes": 500,
		"pixel_trail": 300,
	}
	for id: String in trails:
		assert_eq(Shop.price(Catalog.TRAIL, id), trails[id], "%s price" % id)
	var flyers := {"pip": 350, "mochi": 400, "tock": 450, "lulu": 300, "puff": 350, "bubbles": 500}
	for id: String in flyers:
		assert_eq(Shop.price(Catalog.FLYER, id), flyers[id], "%s price" % id)


## Distance-stamped trails leave several stamps over their life at flying speed,
## so the trail reads as a stream like the board, not one or two dots.
func test_stamp_trails_leave_a_stream() -> void:
	var speed := float(SimConfig.SPEED_X) / SimConfig.SUB * SimConfig.TICKS_PER_SECOND
	for t in Catalog.trails():
		if t.kind != TrailStyle.Kind.STAMPS or t.stamp_on_flap:
			continue
		var stamps := speed * t.lifetime / t.spacing
		assert_true(stamps >= 4.0, "%s leaves %.1f stamps" % [t.id, stamps])
		assert_true(stamps <= 14.0, "%s is not a solid smear (%.1f stamps)" % [t.id, stamps])


func test_board_trail_shapes() -> void:
	assert_eq(TrailStyle.rainbow_ribbon().colors.size(), 6, "six rainbow bands")
	assert_eq(TrailStyle.rainbow_ribbon().taper, 0.0, "rainbow keeps its width and only fades")
	assert_eq(TrailStyle.confetti().colors.size(), 5, "five party colours")
	assert_true(TrailStyle.bubble_stream().grow > 2.0, "bubbles grow as they fade")
	assert_true(TrailStyle.bubble_stream().rise > 0.0, "bubbles rise")
	assert_true(TrailStyle.confetti().rise < 0.0 and TrailStyle.confetti().spin > 0.0, "confetti")
	assert_true(TrailStyle.leaf_swirl().rise < 0.0 and TrailStyle.leaf_swirl().spin > 0.0, "leaf")
	assert_true(TrailStyle.music_notes().stamp_on_flap, "a note on every flap")


func test_sparkle_has_curved_sides() -> void:
	var pts := TrailPainter.sparkle_points(Vector2.ZERO, 10.0)
	var far := 0.0
	var near := 10.0
	for p in pts:
		far = maxf(far, p.length())
		near = minf(near, p.length())
	assert_true(is_equal_approx(far, 10.0), "tips reach the radius")
	assert_true(near < 4.0, "sides curve in toward the centre")


func test_music_note_appears_on_flap() -> void:
	var bird := Node2D.new()
	var view := TrailView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(bird)
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	view.bind(bird, TrailStyle.music_notes(), ThemeCatalog.all()[0])
	view.on_flap()
	assert_eq(view._points.size(), 0, "no note before the run starts")
	view.start()
	view.on_flap()
	view.on_flap()
	assert_eq(view._points.size(), 2, "one note per flap")
	view.free()
	bird.free()


## Every world draws its own particle at board size and opacity: at least as
## many as the boards' density, never fainter than 0.4.
func test_particles_read_at_phone_scale() -> void:
	assert_true(RoomView.MOTES.size() >= 16, "enough particles for a 360 x 640 room")
	for a: float in RoomView.MOTE_ALPHAS:
		assert_true(a >= 0.4 and a <= 0.85, "particle opacity %.2f in the board's range" % a)
	var kinds := {}
	for id: String in RoomView.MOTE_KIND:
		kinds[RoomView.MOTE_KIND[id]] = true
	assert_eq(kinds.size(), RoomView.MOTE_MOTION.size(), "every particle kind is used by a world")


func test_snow_big_flakes_fall_slower() -> void:
	var s: Array = RoomView.SNOW_SPEED
	assert_true(s[0] > s[1] and s[1] > s[2], "small flakes fall fastest")


## The flap pose is its own art, so a flap visibly changes the flyer.
func test_every_flyer_has_distinct_idle_and_flap_art() -> void:
	assert_eq(Catalog.flyers().size(), 12, "six launch flyers plus six new ones")
	for f in Catalog.flyers():
		assert_true(f.idle != null and f.flap != null, "%s has both poses" % f.id)
		assert_ne(f.idle.resource_path, f.flap.resource_path, "%s flap is its own art" % f.id)
		assert_ne(
			f.idle.get_image().get_data(), f.flap.get_image().get_data(), "%s poses differ" % f.id
		)


func test_bird_view_shows_flap_pose_after_a_flap() -> void:
	var bird := BirdView.new()
	bird.set_character(Catalog.flyer("puff"))
	assert_false(bird._flap_timer > 0.0, "idle before a flap")
	bird.on_flap()
	assert_true(bird._flap_timer > 0.0, "flap pose right after a flap")
	bird.free()
