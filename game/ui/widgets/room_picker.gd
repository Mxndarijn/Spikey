class_name RoomPicker
extends VBoxContainer
## On the debug page, in every build: every room kind, read live from
## RoomCatalog and grouped like the Rooms screen (seasonal rooms too). Tap a
## room, then Random or one of its variants, then Play: a practice run of that
## room with that variant (GameSim.forced_variant). Rooms without variants
## just play. The last pick is kept while the app runs, so "Play again"
## retries it in one tap.

## Play pressed: practise room `id` with variant `variant` ("" = random).
signal play_pressed(id: String, variant: String)

const RANDOM := ""
const FONT_SIZE := UiTokens.FONT_SIZE_LABEL

## The last room and variant played from the picker, for "Play again".
static var last_room := ""
static var last_variant := RANDOM

## The picked room id ("" = none yet) and variant id (RANDOM = drawn).
var room_id := ""
var variant := RANDOM

var _rooms := ButtonGroup.new()
var _variant_group := ButtonGroup.new()
## Group id -> the flow with its room buttons.
var _flows := {}
## The picked room's variant buttons and Play; sits under that room's group.
var _choice := VBoxContainer.new()
var _variants := HFlowContainer.new()
var _play: Button
var _again: Button


func _init() -> void:
	add_theme_constant_override("separation", UiTokens.SPACE_2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_again = _pill("PlayAgain", "", false)
	_again.pressed.connect(play_again)
	add_child(_again)
	for group in RoomInfo.GROUPS:
		var defs := RoomInfo.rooms_in(group)
		if defs.is_empty():
			continue
		add_child(_heading(str(RoomInfo.GROUP_NAMES.get(group, group))))
		var flow := _flow()
		for def in defs:
			var b := _pill("Room_" + def.id, RoomInfo.name_of(def.id), true)
			b.button_group = _rooms
			b.pressed.connect(pick.bind(def.id))
			flow.add_child(b)
		add_child(flow)
		_flows[group] = flow
	_choice.name = "Choice"
	_choice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice.add_theme_constant_override("separation", UiTokens.SPACE_2)
	_choice.add_child(_heading("Variant"))
	_variants = _flow()
	_variants.name = "Variants"
	_choice.add_child(_variants)
	_play = _play_button()
	_choice.add_child(_play)
	_choice.visible = false
	add_child(_choice)
	_show_again()
	if RoomCatalog.find(last_room) != null:
		pick(last_room, last_variant)


## Every room id the picker lists, in screen order.
func listed_rooms() -> Array[String]:
	var out: Array[String] = []
	for group in RoomInfo.GROUPS:
		for def in RoomInfo.rooms_in(group):
			out.append(def.id)
	return out


## The variant choices shown for the picked room: RANDOM first, then each id.
## Empty for a room without variants (it just plays).
func variant_choices() -> Array[String]:
	var out: Array[String] = []
	var def := RoomCatalog.find(room_id)
	if def == null or def.variants.is_empty():
		return out
	out.append(RANDOM)
	out.append_array(variant_ids(def))
	return out


## The variant ids of room `def`, in catalog order.
static func variant_ids(def: RoomDef) -> Array[String]:
	var out: Array[String] = []
	for v in def.variants:
		out.append(v.id)
	return out


## Picks a room (and a variant of it; an unknown one falls back to RANDOM).
func pick(id: String, p_variant: String = RANDOM) -> void:
	var def := RoomCatalog.find(id)
	if def == null:
		return
	room_id = id
	var b := find_child("Room_" + id, true, false) as Button
	if b != null:
		b.set_pressed_no_signal(true)
	for old in _variants.get_children():
		_variants.remove_child(old)
		old.queue_free()
	var choices := variant_choices()
	if choices.is_empty():
		_variants.add_child(_note("No variants: it just plays"))
	for v in choices:
		var chip := _pill("Variant_" + (v if v != RANDOM else "random"), _variant_name(v), true)
		chip.button_group = _variant_group
		chip.pressed.connect(choose_variant.bind(v))
		_variants.add_child(chip)
	choose_variant(p_variant if p_variant in choices else RANDOM)
	# Under the picked room's group, so it shows next to what was tapped.
	var flow := _flows.get(RoomInfo.group(def)) as Control
	if flow != null:
		move_child(_choice, flow.get_index() + 1)
	_choice.visible = true


func choose_variant(v: String) -> void:
	variant = v
	var chip := (
		_variants.find_child("Variant_" + (v if v != RANDOM else "random"), false, false) as Button
	)
	if chip != null:
		chip.set_pressed_no_signal(true)
	_play.text = "Play %s" % choice_text(room_id, variant)


## "Bramble Ball · split", "Bramble Ball · random", or just the name.
static func choice_text(id: String, v: String) -> String:
	var def := RoomCatalog.find(id)
	if def == null:
		return ""
	var room_name := RoomInfo.name_of(id)
	if def.variants.is_empty():
		return room_name
	return "%s · %s" % [room_name, _variant_name(v)]


## Plays the picked room and variant, and keeps them for "Play again".
func play() -> void:
	if room_id.is_empty():
		return
	last_room = room_id
	last_variant = variant
	_show_again()
	play_pressed.emit(room_id, variant)


## Plays the last pick again.
func play_again() -> void:
	if RoomCatalog.find(last_room) == null:
		return
	pick(last_room, last_variant)
	play()


func _show_again() -> void:
	var known := RoomCatalog.find(last_room) != null
	_again.visible = known
	if known:
		_again.text = "Play again: %s" % choice_text(last_room, last_variant)


static func _variant_name(v: String) -> String:
	return "Random" if v == RANDOM else v


func _heading(text: String) -> Label:
	var l := UiKit.label(text, &"MutedLabel", false)
	l.add_theme_font_override("font", GameFonts.ui(800))
	l.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_CAPTION)
	return l


func _note(text: String) -> Label:
	var l := UiKit.label(text, &"MutedLabel", false)
	l.add_theme_font_size_override("font_size", FONT_SIZE)
	return l


func _flow() -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.add_theme_constant_override("h_separation", UiTokens.SPACE_2)
	flow.add_theme_constant_override("v_separation", UiTokens.SPACE_2)
	return flow


## A pill as tall as a thumb: ink on the edge colour, white on ink when picked.
func _pill(node_name: String, text: String, toggle: bool) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.toggle_mode = toggle
	b.theme_type_variation = &"PlainButton"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, UiTokens.SIZE_TAP_MIN)
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	var idle := UiTheme.flat(UiTokens.EDGE, UiTokens.RADIUS_PILL, UiTokens.SPACE_3)
	var on := UiTheme.flat(UiTokens.INK_LINE, UiTokens.RADIUS_PILL, UiTokens.SPACE_3)
	for state in ["normal", "hover", "disabled"]:
		b.add_theme_stylebox_override(state, idle)
	for state in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(state, on)
	for state in ["font_color", "font_hover_color"]:
		b.add_theme_color_override(state, UiTokens.ON_PANEL)
	for state in ["font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(state, UiTokens.ON_PRIMARY)
	return b


## The full-width ink Play button.
func _play_button() -> Button:
	var b := Button.new()
	b.name = "PlayRoom"
	b.theme_type_variation = &"PlainButton"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, UiTokens.SIZE_BUTTON_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_theme_font_override("font", GameFonts.ui(800))
	b.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_BUTTON)
	var ink := UiTheme.flat(UiTokens.PRIMARY, UiTokens.RADIUS_PILL, UiTokens.SPACE_4)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		b.add_theme_stylebox_override(state, ink)
	for state in [
		"font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"
	]:
		b.add_theme_color_override(state, UiTokens.ON_PRIMARY)
	b.pressed.connect(play)
	return b
