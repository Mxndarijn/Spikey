extends TestCase
## Exit portal looks (cosmetic): the 12 vortex styles in the catalog, the
## equipped portal in the save, the Portals section of Customize, and drawing
## every style.

const TEST_PATH := "user://test_portal_styles_profile.json"
const IDS: Array[String] = [
	"match_world",
	"classic_spiral",
	"candy_swirl",
	"mint_breeze",
	"dotted",
	"ripple",
	"galaxy",
	"ink_swirl",
	"rainbow",
	"flame",
	"pixel",
	"golden",
]
const PRICES: Array[int] = [0, 0, 200, 200, 250, 300, 300, 350, 400, 400, 450, 600]


class PortalCanvas:
	extends Control
	var style: PortalStyle
	var theme_def: ThemeDef
	var open_amount := 1.0
	var time := 0.0

	func _draw() -> void:
		style.draw_portal(self, Vector2(6, 120), 48.0, 0, open_amount, time, theme_def)
		style.draw_portal(
			self, Vector2(354, 260), 48.0, 1, open_amount, time, theme_def, UiTokens.SUCCESS
		)
		style.draw_portal(
			self, Vector2(354, 420), 48.0, 1, open_amount, time, theme_def, UiTokens.ACTION
		)


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func test_the_twelve_styles_and_their_prices() -> void:
	assert_eq(Catalog.ids(Catalog.PORTAL), IDS, "Match my world first, then the shop")
	for i in IDS.size():
		assert_eq(Shop.price(Catalog.PORTAL, IDS[i]), PRICES[i], "%s's price" % IDS[i])
	assert_eq(Shop.starters(Catalog.PORTAL), ["match_world", "classic_spiral"], "two free portals")
	var match_world := Catalog.portal(PortalStyle.DEFAULT_ID)
	assert_true(match_world != null and match_world.follows_world, "the default follows the world")
	if match_world != null:
		assert_eq(match_world.display_name, "Match my world")
	var kinds := {}
	for p in Catalog.portals():
		kinds[p.kind] = true
	for kind in [
		PortalStyle.SPIRAL,
		PortalStyle.DOTS,
		PortalStyle.RINGS,
		PortalStyle.GALAXY,
		PortalStyle.PIXEL
	]:
		assert_true(kinds.has(kind), "a %s style" % kind)


func test_every_portal_has_a_unique_id_name_and_blurb() -> void:
	var seen: Array[String] = []
	for p in Catalog.portals():
		assert_false(p.id in seen, "%s is unique" % p.id)
		seen.append(p.id)
		assert_eq(Catalog.display_name(Catalog.PORTAL, p.id), p.display_name)
		assert_false(p.blurb.is_empty(), "%s has a line for the popup" % p.id)
		assert_eq(p.follows_world, p.id == PortalStyle.DEFAULT_ID, "%s's colours" % p.id)
		if not p.follows_world:
			assert_false(p.arms.is_empty(), "%s has arm colours" % p.id)


## Safe, so never in the spike colour: every colour a style draws with, in every
## world, for normal, Calm and Wild exits.
func test_no_portal_colour_is_a_spike_colour() -> void:
	var overrides: Array[Color] = [Color(0, 0, 0, 0), UiTokens.SUCCESS, UiTokens.ACTION]
	for world in Catalog.worlds():
		for p in Catalog.portals():
			for o in overrides:
				var c := p.colors(world, o)
				var all: Array[Color] = [c["base"], c["rim"], c["eye"]]
				all.append_array(c["arms"])
				all.append_array(c["touch"])
				for col in all:
					assert_ne(col, world.spike, "%s in %s" % [p.id, world.id])


func test_match_my_world_uses_the_world_and_its_rim_touch() -> void:
	var p := Catalog.portal(PortalStyle.DEFAULT_ID)
	var sunset := Catalog.world("sunset")
	var c := p.colors(sunset)
	assert_true(sunset.sky_top in c["arms"], "arms in the world's sky")
	assert_false(c["touch"].is_empty(), "sunset adds its sun ticks")
	assert_ne(c["arms"], p.colors(Catalog.world("lava"))["arms"], "each world its own vortex")
	for world in Catalog.worlds():
		assert_false(p.colors(world)["touch"].is_empty(), "%s has a rim touch" % world.id)
	var calm := p.colors(sunset, UiTokens.SUCCESS)
	assert_ne(calm["arms"], c["arms"], "Calm recolours the arms")
	assert_eq(calm["base"], c["base"], "but keeps the disc")
	var golden := Catalog.portal("golden")
	assert_true(golden.colors(sunset)["touch"].is_empty(), "fixed styles have no world touch")


func test_profile_saves_the_equipped_portal() -> void:
	var p := Profile.new()
	assert_true(p.owns(Catalog.PORTAL, PortalStyle.DEFAULT_ID), "Match my world from the start")
	assert_true(p.owns(Catalog.PORTAL, "classic_spiral"), "and Classic Spiral")
	assert_eq(p.equipped_portal(), PortalStyle.DEFAULT_ID, "Match my world in use")
	assert_false(p.equip(Catalog.PORTAL, "galaxy"), "can't use a portal you don't own")
	p.coins = 1000
	assert_eq(Shop.buy(p, Catalog.PORTAL, "galaxy"), Shop.Result.OK)
	assert_eq(p.coins, 700)
	assert_true(p.equip(Catalog.PORTAL, "galaxy"))
	assert_true(p.save(TEST_PATH), "saved")
	var back := Profile.load_or_new(TEST_PATH)
	assert_eq(back.equipped_portal(), "galaxy", "the equipped portal survives a reload")
	assert_true(back.owns(Catalog.PORTAL, "galaxy"))
	assert_eq(PortalStyle.equipped(back).id, "galaxy")
	DirAccess.remove_absolute(TEST_PATH)


func test_old_and_odd_saves_fall_back_to_match_my_world() -> void:
	var old := Profile.from_dict({"owned": {"trail": ["world_ribbon"]}, "equipped": {}})
	assert_eq(old.equipped_portal(), PortalStyle.DEFAULT_ID, "saves from before portals")
	for gone in ["cloud_hole", "ink_splat", "feather_ring", "breakout_crack", "ripple_mirror"]:
		var odd := Profile.from_dict(
			{"owned": {"portal": ["cloud_hole", gone]}, "equipped": {"portal": gone}}
		)
		assert_eq(odd.equipped_portal(), PortalStyle.DEFAULT_ID, "%s falls back" % gone)
		assert_eq(odd.equipped_id(Catalog.PORTAL), PortalStyle.DEFAULT_ID, "in the save too")
		assert_eq(PortalStyle.equipped(odd).id, PortalStyle.DEFAULT_ID)
		assert_true(odd.owns(Catalog.PORTAL, PortalStyle.DEFAULT_ID))


func test_customize_has_a_portals_section() -> void:
	var holder := Control.new()
	holder.theme = UiTheme.get_theme()
	holder.size = Vector2(UiTokens.SIZE_VIEWPORT_W, UiTokens.SIZE_VIEWPORT_H)
	_tree().root.add_child(holder)
	var p := Profile.new()
	p.coins = 400
	var c := CollectionScreen.new(p, CollectionScreen.Mode.SHOP, Catalog.PORTAL)
	holder.add_child(c)
	assert_eq(c.title_text(), "Portals", "the Portals list")
	assert_eq(c.kind, Catalog.PORTAL, "opened on it")
	assert_eq(c.item_ids(), Catalog.ids(Catalog.PORTAL), "Match my world first, then the shop")
	assert_eq(c.selected_id(), PortalStyle.DEFAULT_ID, "the portal in use is picked")
	assert_eq(c.action_label(), ["In use", false])
	var statuses := {}
	for card in c._cards:
		statuses[card.item_id] = card.status_text()
	assert_eq(statuses[PortalStyle.DEFAULT_ID], "In use")
	assert_eq(statuses["galaxy"], "300")
	c._tap("galaxy")
	assert_true(c.is_popup_open(), "tapping opens the popup")
	assert_eq(c.preview_portal_id(), "galaxy", "the preview shows the tapped portal")
	assert_eq(c._popup_thumb.portal.id, "galaxy", "and so does the popup picture")
	assert_eq(c.action_label(), ["Unlock for 300", true])
	c._on_action()
	assert_eq(p.equipped_portal(), "galaxy", "bought and put to use")
	assert_eq(p.coins, 100)
	c._tap("golden")
	assert_eq(c.action_label(), ["Need 500 more coins", false])
	c._show_kind(Catalog.FLYER)
	assert_eq(c.preview_portal_id(), "galaxy", "other tabs preview the portal in use")
	holder.free()


## Every style draws closed, opening, open and overshooting, for normal, Calm
## and Wild exits, in every world (any logged error fails the test), and as a
## shop picture.
func test_every_portal_draws_open_and_opening() -> void:
	var canvas := PortalCanvas.new()
	canvas.size = Vector2(UiTokens.SIZE_VIEWPORT_W, UiTokens.SIZE_VIEWPORT_H)
	_tree().root.add_child(canvas)
	for world in Catalog.worlds():
		canvas.theme_def = world
		for p in Catalog.portals():
			if world != ThemeCatalog.default_theme() and not p.follows_world:
				continue
			canvas.style = p
			for open in [0.0, 0.05, 0.6, 1.1]:
				canvas.open_amount = open
				canvas.time += 0.37
				canvas.queue_redraw()
				await _tree().process_frame
	for p in Catalog.portals():
		var thumb := ItemThumb.new()
		thumb.world = ThemeCatalog.default_theme()
		thumb.portal = p
		thumb.dimmed = true
		thumb.size = Vector2(84, 60)
		_tree().root.add_child(thumb)
		await _tree().process_frame
		thumb.free()
	assert_true(canvas.is_inside_tree(), "drew every style")
	canvas.free()


## Every style is the same size: the disc spans the exit's height and sits
## against the wall, whatever is drawn inside it.
func test_every_portal_is_the_same_size() -> void:
	var half := SimConfig.EXIT_HALF / float(SimConfig.SUB)
	var top := PortalPainter.R + 8.0
	assert_eq(top, PortalPen.OUTER, "the rim is the disc's edge")
	var k := half / PortalPainter.REF_HALF
	var reach := (
		PortalPainter.DISC_DEPTH * k + PortalPen.OUTER * PortalPen.SQUASH * half / PortalPen.OUTER
	)
	assert_true(reach < 38.0, "clear of the Calm/Wild tag (%.1f px from the wall)" % reach)
