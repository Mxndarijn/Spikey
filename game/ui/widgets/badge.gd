class_name Badge
extends RefCounted
## A small gold tag with ink text (ink on gold 10:1): a count ("2"), "UPDATE",
## a rank ("#14"). Gold is the kit's highlight, so a badge always means "this
## wants you".


static func make(text: String) -> Label:
	var l := UiKit.label(text, &"OnInkLabel")
	l.name = "Badge"
	l.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_TAG)
	l.add_theme_color_override("font_color", UiTokens.ON_ACTION)
	l.add_theme_constant_override("line_spacing", 0)
	var gold := UiTheme.flat(UiTokens.ACTION, UiTokens.RADIUS_PILL, 0)
	gold.content_margin_left = 6
	gold.content_margin_right = 6
	gold.content_margin_top = 0
	gold.content_margin_bottom = 0
	l.add_theme_stylebox_override("normal", gold)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
