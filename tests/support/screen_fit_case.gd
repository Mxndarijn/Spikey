class_name ScreenFitCase
extends TestCase
## Shared checks for the screen-fit tests: a screen laid out on the narrowest
## (360 x 640) phone may not need more room than it has.


## setup runs once the screen is in the tree (to show a board, open a dialog).
func _fits(screen: Control, label: String, setup: Callable = Callable()) -> void:
	var holder := Control.new()
	holder.theme = UiTheme.get_theme()
	holder.size = Vector2(UiTokens.SIZE_VIEWPORT_W, UiTokens.SIZE_VIEWPORT_H)
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	holder.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if setup.is_valid():
		setup.call()
	var need := 0.0
	for child in screen.get_children():
		if child is Control:
			need = maxf(need, (child as Control).get_combined_minimum_size().y)
	# Any shown control counts, also one under a plain Control (popups).
	var wide := 0.0
	for c in screen.find_children("*", "Control", true, false):
		if (c as Control).is_visible_in_tree() and not _scrolls_sideways(c):
			wide = maxf(wide, (c as Control).get_combined_minimum_size().x)
	# Nothing may be pushed past the side edges either (cards, tabs, pills).
	assert_true(
		wide <= UiTokens.SIZE_VIEWPORT_W,
		"%s needs %d px of width, the screen has %d" % [label, wide, UiTokens.SIZE_VIEWPORT_W]
	)
	assert_true(
		need <= UiTokens.SIZE_VIEWPORT_H,
		"%s needs %d px of height, the screen has %d" % [label, need, UiTokens.SIZE_VIEWPORT_H]
	)
	holder.free()


## Inside a sideways scroll a row may be wider than the screen.
static func _scrolls_sideways(c: Node) -> bool:
	var up := c.get_parent()
	while up != null:
		if up is ScrollContainer and (up as ScrollContainer).horizontal_scroll_mode != 0:
			return true
		up = up.get_parent()
	return false


func _profile() -> Profile:
	var p := Profile.new()
	p.coins = 12345
	p.best_score = 87
	p.onboarded = true
	for kind in ItemKind.ALL:
		var id: String = Catalog.ids(kind)[0]
		p.grant(kind, id)
		p.equip(kind, id)
	return p
