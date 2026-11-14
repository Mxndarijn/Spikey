extends TestCase
## Every button and label on the settings sheet shows its whole text on the
## narrowest phone (360 x 640): nothing trimmed to "...", nothing wider than its
## box, on the main page and on About. Checked on every world's room theme, with
## and without Ad choices, in developer mode (the most rows). The game ships in
## English only, so the shipped strings are the ones checked.


func test_settings_text_fits_on_every_world() -> void:
	DevMode.override = 1
	for world: ThemeDef in Catalog.worlds():
		for ad_choices: bool in [false, true]:
			await _check(world, ad_choices)
	DevMode.override = -1


func _check(world: ThemeDef, ad_choices: bool) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var holder := Control.new()
	holder.theme = UiTheme.room_theme(world)
	holder.size = Vector2(UiTokens.SIZE_VIEWPORT_W, UiTokens.SIZE_VIEWPORT_H)
	tree.root.add_child(holder)
	var p := Profile.new()
	var services := AppServices.offline(p)
	if ad_choices:
		var ads := FakeAds.new()
		ads.privacy_required = true
		services.ads = ads
	var sheet := SettingsSheet.new(p, services)
	holder.add_child(sheet)
	var where := "%s%s" % [world.id, " +ads" if ad_choices else ""]
	for about: bool in [false, true]:
		sheet.show_about(about)
		await tree.process_frame
		await tree.process_frame
		_page_fits(sheet, where + (" about" if about else ""))
	holder.free()


func _page_fits(sheet: SettingsSheet, where: String) -> void:
	for c in sheet.find_children("*", "Control", true, false):
		var control := c as Control
		if not control.is_visible_in_tree():
			continue
		if control is Button and (control as Button).text != "":
			_button_fits(control as Button, where)
		elif control is Label and (control as Label).text != "":
			_label_fits(control as Label, where)


func _button_fits(b: Button, where: String) -> void:
	var font := b.get_theme_font("font")
	var font_size := b.get_theme_font_size("font_size")
	var text_w := font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var need := text_w
	var box := b.get_theme_stylebox("normal")
	if box != null:
		need += box.get_margin(SIDE_LEFT) + box.get_margin(SIDE_RIGHT)
	if b.icon != null:
		var icon_w := float(b.icon.get_width())
		var cap := b.get_theme_constant("icon_max_width")
		if cap > 0:
			icon_w = minf(icon_w, cap)
		need += icon_w + b.get_theme_constant("h_separation")
	assert_true(
		need <= b.size.x + 0.5,
		"%s: button '%s' needs %d px, has %d" % [where, b.text, need, b.size.x]
	)
	# A caption inside the row starts after the row's own name.
	var text_end := text_w + (box.get_margin(SIDE_LEFT) if box != null else 0.0)
	for child in b.get_children():
		if child is Label and (child as Label).visible:
			assert_true(
				(child as Label).position.x >= text_end,
				"%s: '%s' covers the name '%s'" % [where, (child as Label).text, b.text]
			)


func _label_fits(l: Label, where: String) -> void:
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
		assert_true(
			l.get_visible_line_count() >= l.get_line_count(),
			"%s: label '%s' hides lines" % [where, l.text]
		)
		return
	var font := l.get_theme_font("font")
	var font_size := l.get_theme_font_size("font_size")
	var w := font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	assert_true(
		w <= l.size.x + 0.5, "%s: label '%s' needs %d px, has %d" % [where, l.text, w, l.size.x]
	)
