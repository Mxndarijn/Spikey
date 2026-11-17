class_name BattleKit
extends RefCounted
## Small pieces Battle's screens share (docs/DUEL_MODE.md, screens B1 to B7, K1
## and K2): the ink BOT pill every bot's name carries, a battle's row in the
## list, the strip of round squares, and the paper card over the dimmed room.


## The small ink "BOT" pill: shown wherever a bot's name is, always.
static func bot_pill() -> Label:
	var pill := UiKit.label("BOT", &"OnInkLabel")
	pill.name = "BotPill"
	pill.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_TAG)
	var ink := UiTheme.flat(UiTokens.PRIMARY, UiTokens.RADIUS_PILL, 0)
	ink.content_margin_left = UiTokens.SPACE_2
	ink.content_margin_right = UiTokens.SPACE_2
	ink.content_margin_top = 1
	ink.content_margin_bottom = 1
	pill.add_theme_stylebox_override("normal", ink)
	pill.add_theme_color_override("font_color", UiTokens.ON_PRIMARY)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return pill


## The rival's name, with the BOT pill for a bot.
static func rival_name(
	view: BattleView, variation: StringName = &"SmallNameLabel"
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", UiTokens.SPACE_2)
	var label := UiKit.label(view.rival_label(), variation, false)
	label.name = "Name"
	row.add_child(label)
	if view.rival_bot:
		row.add_child(bot_pill())
	return row


## A battle in the list: the rival and what happens next at the left, the
## score at the right, a paper pill to tap.
static func row(view: BattleView) -> Button:
	var b := Button.new()
	b.name = "Battle%d" % view.id
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 64)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := UiTheme.flat(UiTokens.PANEL, UiTokens.RADIUS_M - 4, 0)
	var down := box.duplicate() as StyleBoxFlat
	down.bg_color = UiTokens.PANEL_RAISED
	for state in ["normal", "hover", "disabled", "focus"]:
		b.add_theme_stylebox_override(state, box)
	for state in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(state, down)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = UiTokens.SPACE_4
	line.offset_right = -UiTokens.SPACE_4
	line.add_theme_constant_override("separation", UiTokens.SPACE_3)
	b.add_child(line)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	line.add_child(col)
	col.add_child(rival_name(view))
	var status := UiKit.label(view.status_line(), &"MutedLabel", false)
	status.name = "Status"
	status.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_CAPTION)
	status.clip_text = true
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(status)
	var score := UiKit.label("%d–%d" % [view.wins_me, view.wins_them], &"NameLabel")
	score.name = "Score"
	score.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_HEADING)
	score.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(score)
	return b


## The rounds as squares, oldest first: won (gold), lost (ink), draw (edge),
## not decided yet (paper with an edge).
static func rounds_strip(view: BattleView) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.name = "Rounds"
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	for r: Dictionary in view.rounds:
		var w := str(r.get("winner", "")) if r.get("winner") is String else ""
		var cell := PanelContainer.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.custom_minimum_size = Vector2(32, 32)
		var fill := UiTokens.PANEL
		var text := ""
		var color := UiTokens.ON_PANEL
		match w:
			"me":
				fill = UiTokens.ACTION
				text = "W"
			"them":
				fill = UiTokens.PRIMARY
				text = "L"
				color = UiTokens.ON_PRIMARY
			"draw":
				fill = UiTokens.EDGE
				text = "="
		var box := UiTheme.flat(fill, UiTokens.RADIUS_S, 0)
		if w.is_empty():
			box.border_color = UiTokens.EDGE
			box.set_border_width_all(2)
		cell.add_theme_stylebox_override("panel", box)
		var l := UiKit.label(text, &"SmallNameLabel")
		l.add_theme_color_override("font_color", color)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cell.add_child(l)
		flow.add_child(cell)
	return flow


## A paper card in the middle of the dimmed room, `side` px from the edges;
## returns [the whole overlay, the card's column]. The dimmed room closes it.
static func card_over_scrim(on_scrim: Callable, side: int = 20) -> Array:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var scrim := ColorRect.new()
	scrim.color = UiTokens.SCRIM
	ScrimBleed.attach(scrim)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.gui_input.connect(
		func(event: InputEvent) -> void:
			if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
				on_scrim.call()
	)
	root.add_child(scrim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", side)
	margin.add_theme_constant_override("margin_right", side)
	root.add_child(margin)
	var card := PanelContainer.new()
	card.theme_type_variation = &"BigPanel"
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	margin.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTokens.SPACE_3)
	card.add_child(col)
	return [root, col]
