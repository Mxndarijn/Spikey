class_name DebugPage
extends VBoxContainer
## The debug screen inside the settings sheet: what the app, the ads and the
## notifications are doing right now, with buttons to try each of them on a
## real phone, plus pickers that practise one room or replay a seed. It opens
## from the Debug row in the settings, or by tapping the "Settings" title
## TAPS_TO_OPEN times (both in any build).
##
## Everything here is safe in a release build: nothing gives coins, points or
## revives. Only developer mode shows "Give free revives back" and "Revive
## Pass on or off".
## The rows refresh twice a second while the page shows. "Copy everything"
## puts the whole report on the clipboard, to paste into a message.

## A profile field changed (main saves).
signal changed
## The room picker: practise room `id` with `variant` ("" = random).
signal practice_requested(id: String, variant: String)
## The seed picker: play the run with seed `seed_value` in `season` again, as practice.
signal seed_requested(seed_value: int, season: int)

const APP := "App"
const ADS := "Ads"
const PUSH := "Notifications"
const ROOMS := "Rooms"
const SEED := "Play a seed"
const SECTIONS: Array[String] = [APP, ADS, PUSH]
## Taps on the settings title that open this page.
const TAPS_TO_OPEN := 7
const REFRESH_S := 0.5
const NAME_WIDTH := 104
const TEXT_SIZE := 13

var _profile: Profile
var _services: AppServices
var _since := 0.0
## Section name -> the box with its rows.
var _boxes := {}
## Section name -> the line under its buttons that says what a button did.
var _notes := {}
var _test_ads := SettingSwitch.new("Google test ads", "Asks for test ads, not real ones")
## Developer mode only (null otherwise).
var _picker: RoomPicker
var _seed_picker: SeedPicker


func _init(profile: Profile, services: AppServices) -> void:
	_profile = profile
	_services = services
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := SmoothScroll.new()
	add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", UiTokens.SPACE_2)
	scroll.add_child(list)
	# The room picker comes first, in every build: it's what playtests use most.
	list.add_child(_section(ROOMS))
	_picker = RoomPicker.new()
	_picker.name = "RoomPicker"
	_picker.play_pressed.connect(practice_requested.emit)
	list.add_child(_picker)
	list.add_child(_section(SEED))
	_seed_picker = SeedPicker.new()
	_seed_picker.name = "SeedPicker"
	_seed_picker.play_pressed.connect(seed_requested.emit)
	list.add_child(_seed_picker)
	for section in SECTIONS:
		list.add_child(_section(section))
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 2)
		list.add_child(box)
		_boxes[section] = box
		if section == ADS:
			_test_ads.name = "TestAds"
			_test_ads.set_pressed_no_signal(profile.settings.test_ads)
			_test_ads.toggled.connect(_on_test_ads)
			list.add_child(_test_ads)
		list.add_child(_buttons(section))
		var note := _text("", &"InkLabel")
		note.name = section + "Note"
		note.visible = false
		list.add_child(note)
		_notes[section] = note
	_services.ads.rewarded_closed.connect(_on_ad_closed)
	refresh()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_since += delta
	if _since >= REFRESH_S:
		_since = 0.0
		refresh()


## Rebuilds every row from the services' state right now.
func refresh() -> void:
	for section in SECTIONS:
		var box := _boxes[section] as VBoxContainer
		for old in box.get_children():
			box.remove_child(old)
			old.queue_free()
		for row: Array in rows(section):
			box.add_child(_row(str(row[0]), str(row[1])))


## A section's [name, value] rows.
func rows(section: String) -> Array:
	match section:
		ADS:
			return _ads_rows()
		PUSH:
			return _push_rows()
	return _app_rows()


## Everything on the page as plain text.
func report() -> String:
	var lines := PackedStringArray(["Flapjaw debug"])
	for section in SECTIONS:
		lines.append("")
		lines.append(section)
		for row: Array in rows(section):
			lines.append("  %s: %s" % [row[0], row[1]])
		var said := note(section)
		if not said.is_empty():
			lines.append("  Last action: %s" % said)
	return "\n".join(lines)


## What the last button of `section` said, or "".
func note(section: String) -> String:
	return (_notes[section] as Label).text


## The room picker.
func room_picker() -> RoomPicker:
	return _picker


## The seed picker.
func seed_picker() -> SeedPicker:
	return _seed_picker


## For tests: taps the button with this node name.
func press(button: String) -> void:
	(find_child(button, true, false) as Button).pressed.emit()


func _app_rows() -> Array:
	var version := str(ProjectSettings.get_setting("application/config/version", "?"))
	var kind := "debug" if OS.is_debug_build() else "release"
	var window := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	return [
		["Version", "%s (%s build)" % [version, kind]],
		["Gameplay", "version %d" % SimConfig.GAMEPLAY_VERSION],
		["Engine", "Godot %s" % str(Engine.get_version_info().get("string", "?"))],
		["Device", "%s, %s %s" % [OS.get_model_name(), OS.get_name(), OS.get_version()]],
		["Screen", "%d x %d" % [window.x, window.y]],
		[
			"Safe area",
			"%d x %d at %d, %d" % [safe.size.x, safe.size.y, safe.position.x, safe.position.y]
		],
		["Language", OS.get_locale()],
		["Speed", "%d frames per second" % int(Engine.get_frames_per_second())],
		["Day", DailyRevives.today()],
		["Best score", str(_profile.best_score)],
	]


func _ads_rows() -> Array:
	var ads := _services.ads
	var out: Array = ads.debug_rows()
	var left := _profile.revives.left(DailyRevives.today())
	out.append(["Free revives", "%d of %d left today" % [left, DailyRevives.PER_DAY]])
	var has_pass := DiamondPacks.has_revive_pass(_profile)
	out.append(["Revive Pass", "owned" if has_pass else "not owned"])
	return out


func _push_rows() -> Array:
	var push := _services.push
	var out: Array = push.debug_rows()
	out.append(["Board alerts", "on" if _profile.settings.board_alerts else "off"])
	out.append(["Asked permission", "yes" if _profile.push_asked else "not yet"])
	return out


func _buttons(section: String) -> Control:
	var flow := HFlowContainer.new()
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.add_theme_constant_override("h_separation", UiTokens.SPACE_2)
	flow.add_theme_constant_override("v_separation", UiTokens.SPACE_2)
	match section:
		APP:
			flow.add_child(_action("CopyAll", "Copy everything", _copy_all))
		ADS:
			flow.add_child(_action("LoadAd", "Load an ad", _load_ad))
			flow.add_child(_action("ShowAd", "Show the ad", _show_ad))
			flow.add_child(_action("AdChoicesForm", "Ad choices", _ad_choices))
			flow.add_child(_action("UseRevives", "Use up free revives", _use_revives))
			if DevMode.enabled():
				flow.add_child(_action("GiveRevives", "Give free revives back", _give_revives))
				flow.add_child(_action("TogglePass", "Revive Pass on or off", _toggle_pass))
		PUSH:
			flow.add_child(_action("TestPush", "Send a test notification", _test_push))
			flow.add_child(_action("AskPush", "Ask for permission", _ask_push))
			flow.add_child(_action("FetchToken", "Fetch the token", _fetch_token))
	return flow


func _say(section: String, text: String) -> void:
	var l := _notes[section] as Label
	l.text = text
	l.visible = not text.is_empty()


func _copy_all() -> void:
	# The note goes first, so the copied text does not report itself.
	_say(APP, "")
	DisplayServer.clipboard_set(report())
	_say(APP, "Copied. Paste it into a message")


func _load_ad() -> void:
	var ads := _services.ads
	ads.preload_rewarded()
	_say(ADS, "An ad is loaded" if ads.is_ready() else "Asked for an ad")
	refresh()


func _show_ad() -> void:
	var ads := _services.ads
	if not ads.is_ready():
		_say(ADS, "No ad is loaded")
		return
	_say(ADS, "Showing the ad")
	# No game sound under the ad, as in a run; _on_ad_closed turns it back on.
	AudioServer.set_bus_mute(0, true)
	ads.show_rewarded()


func _on_ad_closed(result: int) -> void:
	AudioServer.set_bus_mute(0, false)
	match result:
		AdsService.Result.EARNED:
			_say(ADS, "The ad was watched to the end")
		AdsService.Result.DISMISSED:
			_say(ADS, "The ad was closed early")
		_:
			_say(ADS, "The ad could not be shown")
	refresh()


func _ad_choices() -> void:
	_services.ads.show_privacy_options()
	_say(ADS, "Asked for Google's ad choices form")


func _use_revives() -> void:
	var day := DailyRevives.today()
	while _profile.revives.use(day):
		pass
	_say(ADS, "No free revives left today: the next crash offers the ad")
	changed.emit()
	refresh()


func _give_revives() -> void:
	_profile.revives.used = 0
	_say(ADS, "Free revives are back")
	changed.emit()
	refresh()


## Developer mode only: owns the Revive Pass or not, to try both offers
## without a store. A sync with the server can bring a bought pass back.
func _toggle_pass() -> void:
	if DiamondPacks.has_revive_pass(_profile):
		_profile.packs_bought.erase(DiamondPacks.REVIVE_PASS)
		_say(ADS, "No Revive Pass: revives count and ads show again")
	else:
		_profile.packs_bought.append(DiamondPacks.REVIVE_PASS)
		_say(ADS, "Revive Pass on: every revive offer is free")
	changed.emit()
	refresh()


func _on_test_ads(on: bool) -> void:
	_profile.settings.test_ads = on
	changed.emit()
	_services.ads.use_unit(AdsService.revive_unit(OS.get_name(), on or OS.is_debug_build()))
	_say(ADS, "Test ads from now on" if on else "Real ads from now on")
	refresh()


func _test_push() -> void:
	_say(PUSH, "Asking the server")
	_say(PUSH, await _services.push.send_test())


func _ask_push() -> void:
	var push := _services.push
	if not push.is_available():
		_say(PUSH, "Push is not in this build")
		return
	_profile.push_asked = true
	changed.emit()
	push.request_permission()
	_say(PUSH, "Asked the phone for permission")
	refresh()


func _fetch_token() -> void:
	var push := _services.push
	if not push.is_available():
		_say(PUSH, "Push is not in this build")
		return
	push.start()
	_say(PUSH, "Asked the phone for its token")


func _section(text: String) -> Label:
	var l := UiKit.label(text, &"MutedLabel", false)
	l.add_theme_font_override("font", GameFonts.ui(800))
	return l


## One line: the name in a fixed column, the value wrapping beside it.
func _row(row_name: String, value: String) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", UiTokens.SPACE_2)
	var n := _text(row_name, &"MutedLabel")
	n.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	n.custom_minimum_size = Vector2(NAME_WIDTH, 0)
	row.add_child(n)
	row.add_child(_text(value, &"InkLabel"))
	return row


func _text(text: String, variation: StringName) -> Label:
	var l := UiKit.label(text, variation, false)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", TEXT_SIZE)
	return l


## A small pill button: ink on the edge colour, white on ink while pressed.
func _action(node_name: String, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.theme_type_variation = &"PlainButton"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, UiTokens.SIZE_TAP_MIN)
	b.add_theme_font_size_override("font_size", TEXT_SIZE + 1)
	var idle := UiTheme.flat(UiTokens.EDGE, UiTokens.RADIUS_PILL, UiTokens.SPACE_3)
	var down := UiTheme.flat(UiTokens.INK_LINE, UiTokens.RADIUS_PILL, UiTokens.SPACE_3)
	for state in ["normal", "hover", "disabled"]:
		b.add_theme_stylebox_override(state, idle)
	for state in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(state, down)
	for state in ["font_color", "font_hover_color"]:
		b.add_theme_color_override(state, UiTokens.ON_PANEL)
	for state in ["font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(state, UiTokens.ON_PRIMARY)
	b.pressed.connect(on_press)
	return b
