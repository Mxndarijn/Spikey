extends TestCase
## The run's HUD reads in every world: white glyphs in an ink-900 halo, so one
## of the two always stands out from the sky, the spikes and the props behind
## it (3:1, large text and icons), and the corner buttons and the coin counter
## keep clear of the wall spikes' reach.

const HUD_SCENE := "res://game/ui/hud.tscn"
const MIN_HUD := 3.0
const HUD_LABELS: Array[String] = ["HudScore", "HudCoin", "HudLabel"]


func test_fill_or_halo_stands_out_from_every_world_colour() -> void:
	for w in ThemeCatalog.all():
		var behind: Array[Color] = w.all_sky_stops()
		behind.append_array([w.spike, w.spike_edge, w.prop, w.hill_far, w.hill_near, w.cloud])
		for c in behind:
			var best := maxf(
				Contrast.ratio(UiTheme.HUD_FILL, c), Contrast.ratio(UiTheme.HUD_HALO, c)
			)
			assert_true(best >= MIN_HUD, "%s: HUD %.2f:1 on %s" % [w.id, best, c.to_html(false)])


## The HUD looks the same in every world: night rooms change the room text,
## never the HUD's halo styles.
func test_hud_labels_are_the_same_in_every_world() -> void:
	for w in ThemeCatalog.all():
		var t := UiTheme.room_theme(w)
		for type_name in HUD_LABELS:
			assert_eq(t.get_color("font_color", type_name), UiTheme.HUD_FILL, type_name)
			assert_eq(t.get_color("font_outline_color", type_name), UiTheme.HUD_HALO, type_name)
			assert_true(t.get_constant("outline_size", type_name) > 0, "%s has a halo" % type_name)


func test_running_hud_uses_the_halo() -> void:
	var hud: Hud = load(HUD_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(hud)
	assert_eq(hud._score.theme_type_variation, &"HudScore", "score")
	assert_eq(hud.countdown.theme_type_variation, &"HudScore", "countdown")
	assert_eq(hud._run_coins._label.theme_type_variation, &"HudCoin", "coins")
	for b: Button in [hud._pause_button, hud._back_button]:
		assert_eq(b.theme_type_variation, &"HudButton", b.name)
		assert_true(b.get_node("Halo") is HaloIcon, "%s draws its icon in the halo" % b.name)
	hud.free()


## Pause (and back) on the left, the coin counter on the right: their glyphs
## and halos end CORNER_GAP px before the wall spikes' reach.
func test_corners_clear_the_wall_spikes() -> void:
	var reach := float(SimConfig.SPIKE_DEPTH) / SimConfig.SUB
	var hud: Hud = load(HUD_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(hud)
	hud.room_rect = Rect2(Vector2.ZERO, ScreenLayout.ROOM)
	hud.show_running()
	var pause := hud._pause_button
	var icon := float(pause.get_theme_constant("icon_max_width"))
	var glyph_left := pause.position.x + (pause.size.x - icon) / 2.0 - UiTheme.HALO_ICON
	assert_true(glyph_left >= reach + Hud.CORNER_GAP, "pause icon starts at %.1f px" % glyph_left)
	# The counter is pinned by its right edge and grows leftward.
	var coins := hud._run_coins
	assert_eq(coins.grow_horizontal, Control.GROW_DIRECTION_BEGIN, "grows away from the wall")
	var right := hud._root.size.x * coins.anchor_right + coins.offset_right + UiTheme.HALO_SMALL
	assert_true(
		right <= ScreenLayout.ROOM.x - reach - Hud.CORNER_GAP, "coins end at %.1f px" % right
	)
	hud.free()
