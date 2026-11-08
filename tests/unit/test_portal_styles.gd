extends TestCase
## Exit portal looks (cosmetic): the catalog entries, the equipped portal in
## the save, the Portals section of Customize, and drawing every style.

const TEST_PATH := "user://test_portal_styles_profile.json"


class PortalCanvas:
	extends Control
	var style: PortalStyle
	var theme_def: ThemeDef
	var open_amount := 1.0
	var time := 0.0

	func _draw() -> void:
		style.draw_portal(self, Vector2(16, 120), 48.0, 0, open_amount, time, theme_def)
		style.draw_portal(
			self, Vector2(344, 300), 48.0, 1, open_amount, time, theme_def, UiTokens.SUCCESS
		)


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func test_cloud_hole_is_the_free_default() -> void:
	var ids := Catalog.ids(Catalog.PORTAL)
	assert_eq(ids[0], PortalStyle.DEFAULT_ID, "Cloud Hole comes first")
	assert_eq(ids, ["cloud_hole", "ink_splat", "feather_ring", "breakout_crack", "ripple_mirror"])
	var cloud := Catalog.portal(PortalStyle.DEFAULT_ID)
	assert_true(cloud != null, "Cloud Hole is in the catalog")
	if cloud == null:
		return
	assert_eq(cloud.display_name, "Cloud Hole")
	assert_eq(cloud.kind, PortalStyle.CLOUD)
	assert_true(Shop.is_free(Catalog.PORTAL, PortalStyle.DEFAULT_ID), "free")
	assert_eq(Shop.starters(Catalog.PORTAL), [PortalStyle.DEFAULT_ID], "the only free portal")
	var sunset := Catalog.world("sunset")
	assert_eq(cloud.tint(sunset), sunset.world_accent, "normal exits in the world's accent")


func test_every_portal_has_an_id_kind_and_price() -> void:
	var seen: Array[String] = []
	var kinds: Array[String] = []
	for p in Catalog.portals():
		assert_false(p.id in seen, "%s is unique" % p.id)
		seen.append(p.id)
		assert_false(p.kind in kinds, "%s has its own look" % p.id)
		kinds.append(p.kind)
		assert_true(Shop.price(Catalog.PORTAL, p.id) >= 0, "%s has a price" % p.id)
		assert_eq(Catalog.display_name(Catalog.PORTAL, p.id), p.display_name)
		assert_false(p.blurb.is_empty(), "%s has a line for the popup" % p.id)
	for world in Catalog.worlds():
		for p in Catalog.portals():
			assert_ne(
				p.tint(world), world.spike, "%s never in %s's spike colour" % [p.id, world.id]
			)


func test_profile_saves_the_equipped_portal() -> void:
	var p := Profile.new()
	assert_true(
		p.owns(Catalog.PORTAL, PortalStyle.DEFAULT_ID), "Cloud Hole is owned from the start"
	)
	assert_eq(p.equipped_portal(), PortalStyle.DEFAULT_ID, "and in use")
	assert_false(p.equip(Catalog.PORTAL, "ink_splat"), "can't use a portal you don't own")
	p.coins = 1000
	assert_eq(Shop.buy(p, Catalog.PORTAL, "ink_splat"), Shop.Result.OK)
	assert_true(p.equip(Catalog.PORTAL, "ink_splat"))
	assert_true(p.save(TEST_PATH), "saved")
	var back := Profile.load_or_new(TEST_PATH)
	assert_eq(back.equipped_portal(), "ink_splat", "the equipped portal survives a reload")
	assert_true(back.owns(Catalog.PORTAL, "ink_splat"))
	assert_eq(PortalStyle.equipped(back).id, "ink_splat")
	DirAccess.remove_absolute(TEST_PATH)


func test_old_and_odd_saves_fall_back_to_the_default() -> void:
	var old := Profile.from_dict({"owned": {"trail": ["world_ribbon"]}, "equipped": {}})
	assert_eq(old.equipped_portal(), PortalStyle.DEFAULT_ID, "saves from before portals")
	var odd := Profile.from_dict(
		{"owned": {"portal": ["classic"]}, "equipped": {"portal": "classic"}}
	)
	assert_eq(PortalStyle.equipped(odd).id, PortalStyle.DEFAULT_ID, "old ids draw the default")


func test_customize_has_a_portals_section() -> void:
	var holder := Control.new()
	holder.theme = UiTheme.get_theme()
	holder.size = Vector2(UiTokens.SIZE_VIEWPORT_W, UiTokens.SIZE_VIEWPORT_H)
	_tree().root.add_child(holder)
	var p := Profile.new()
	p.coins = 400
	var c := CollectionScreen.new(p, CollectionScreen.Mode.SHOP, Catalog.PORTAL)
	holder.add_child(c)
	var tab := c._tabs.get(Catalog.PORTAL) as Button
	assert_true(tab != null and tab.text == "Portals", "a Portals tab")
	assert_true(tab != null and tab.button_pressed, "opened on it")
	assert_eq(c.item_ids(), Catalog.ids(Catalog.PORTAL), "Cloud Hole (yours) first, then the shop")
	assert_eq(c.selected_id(), PortalStyle.DEFAULT_ID, "the portal in use is picked")
	assert_eq(c.action_label(), ["In use", false])
	var statuses := {}
	for card in c._cards:
		statuses[card.item_id] = card.status_text()
	assert_eq(statuses[PortalStyle.DEFAULT_ID], "In use")
	assert_eq(statuses["ink_splat"], "300")
	c._tap("ink_splat")
	assert_true(c.is_popup_open(), "tapping opens the popup")
	assert_eq(c.preview_portal_id(), "ink_splat", "the preview shows the tapped portal")
	assert_eq(c._popup_thumb.portal.id, "ink_splat", "and so does the popup picture")
	assert_eq(c.action_label(), ["Unlock for 300", true])
	c._on_action()
	assert_eq(p.equipped_portal(), "ink_splat", "bought and put to use")
	assert_eq(p.coins, 100)
	c._tap("breakout_crack")
	assert_eq(c.action_label(), ["Need 300 more coins", false])
	c._show_kind(Catalog.FLYER)
	assert_eq(c.preview_portal_id(), "ink_splat", "other tabs preview the portal in use")
	holder.free()


func test_loadout_card_names_the_portal() -> void:
	var p := Profile.new()
	p.grant(Catalog.FLYER, "buzz")
	p.equip(Catalog.FLYER, "buzz")
	var card := LoadoutCard.new(p)
	assert_eq(card.name_text(Catalog.PORTAL), "Cloud Hole")
	card.free()


func test_every_portal_draws_open_and_opening() -> void:
	var canvas := PortalCanvas.new()
	canvas.size = Vector2(UiTokens.SIZE_VIEWPORT_W, UiTokens.SIZE_VIEWPORT_H)
	canvas.theme_def = ThemeCatalog.default_theme()
	for p in Catalog.portals():
		canvas.style = p
		for open in [0.0, 0.05, 0.6, 1.1]:
			canvas.open_amount = open
			canvas.time += 0.37
			canvas.queue_redraw()
			if canvas.get_parent() == null:
				_tree().root.add_child(canvas)
			await _tree().process_frame
		var thumb := ItemThumb.new()
		thumb.world = canvas.theme_def
		thumb.portal = p
		thumb.dimmed = true
		thumb.size = Vector2(84, 60)
		_tree().root.add_child(thumb)
		await _tree().process_frame
		thumb.free()
	assert_true(canvas.is_inside_tree(), "drew every style")
	canvas.free()
