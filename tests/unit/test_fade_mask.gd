extends TestCase
## Scroll lists fade out at the bottom instead of stopping in a hard line.


func test_mask_is_opaque_above_the_strip_and_clear_at_the_bottom() -> void:
	var scroll := ScrollContainer.new()
	var mask := FadeMask.new(scroll)
	mask.size = Vector2(300, 400)
	assert_eq(mask.clip_children, CanvasItem.CLIP_CHILDREN_ONLY)
	assert_eq(mask.alpha_at(0.0), 1.0, "top is opaque")
	assert_eq(mask.alpha_at(400.0 - FadeMask.FADE), 1.0, "opaque down to the strip")
	assert_true(mask.alpha_at(400.0 - FadeMask.FADE / 2.0) < 1.0, "fading in the strip")
	assert_eq(mask.alpha_at(400.0), 0.0, "clear at the bottom")
	mask.free()


func test_strip_is_at_most_half_a_short_box() -> void:
	var mask := FadeMask.new(ScrollContainer.new())
	mask.size = Vector2(300, 40)
	assert_eq(mask.fade_height(), 20.0)
	mask.free()


func test_mask_takes_the_scrolls_sizing_and_fills_with_it() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 120)
	var mask := FadeMask.new(scroll)
	assert_eq(mask.size_flags_vertical, Control.SIZE_EXPAND_FILL)
	assert_eq(mask.custom_minimum_size, Vector2(0, 120))
	assert_eq(scroll.get_parent(), mask)
	assert_eq(mask.mouse_filter, Control.MOUSE_FILTER_IGNORE, "taps reach the list")
	mask.free()
