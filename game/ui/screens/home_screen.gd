class_name HomeScreen
extends Control
## The main menu over the live room, calm and solid. Every element is a solid
## UI surface (UiTheme.solid: paper with an ink ring, ink with a paper ring), so
## it reads on every world's sky, light or night. From the top: Settings and
## the wallet in the corners, the "flapjaw" wordmark (white in an ink halo, as
## the run's HUD), the flyer, then the one big Play for the chosen mode (Classic
## by default) with the mode beside or under it (a tap there opens ModeSheet),
## one small battles pill (your turns, See all) and the bottom bar (Rooms,
## Style, Ranks with today's rank, Runs).
## Two layouts while the user picks (docs/ui-rework): BAR, a wide ink Play bar
## with a Mode button at its end; ROUND, a big round Play with the mode on a
## chip under it.

signal play_pressed
## Opens one kind's list in Customize directly (nothing on Home emits it now;
## main still listens, for shortcuts to a kind).
signal shop_pressed(tab: String)
## Style (the dock): opens Customize on "Your look".
signal customize_pressed
signal rooms_pressed
## The wallet (gold and diamonds, top right): opens the Wallet (the Shop).
signal store_pressed
## The Daily Run chosen in the mode tabs and started: opens the Daily Run.
signal daily_run_pressed
## Battle chosen and started: opens Battles.
signal battle_pressed
## Duel chosen and started: opens Duel.
signal duel_pressed
## Battle or Duel on an app older than the server's game: the store page.
signal update_pressed
## Runs (the dock): opens Your runs.
signal runs_pressed
## Ranks (the dock): opens the leaderboards.
signal leaderboard_pressed
## A setting changed in the settings sheet, or the chosen mode tab (already in
## the profile): main saves it and applies it.
signal settings_changed
## The debug page's room picker: practise `id` with `variant`.
signal practice_requested(id: String, variant: String)
## The debug page's seed picker: play seed `seed_value` in `season` as practice.
signal seed_requested(seed_value: int, season: int)

enum Layout { BAR, ROUND }

const PLAY_ICON := preload("res://assets/ui/icons/play.svg")
const SETTINGS_ICON := preload("res://assets/ui/icons/settings.svg")
const CHEVRON_ICON := preload("res://assets/ui/icons/chevron.svg")
## The wordmark: one word, wide Archivo 900, white in an ink halo.
const WORDMARK := "flapjaw"
const LOGO_TOP := 98.0
const LOGO_SIZE := 58
const LOGO_HALO := 10
const SIDE := float(UiTokens.SPACE_4)
## The bottom bar, its bottom 14px above the floor spike row.
const BAR_TOP := float(SimConfig.KILL_BOTTOM / SimConfig.SUB) - 14.0 - HomeBar.HEIGHT
## BAR layout: the flyer, the Play bar, the battles pill.
const BAR_FLYER := Vector2(180, 216)
const PLAY_BAR_TOP := 270.0
const PLAY_BAR_H := 88.0
const MODE_BUTTON := Vector2(70, 64)
const BAR_PILL_TOP := PLAY_BAR_TOP + PLAY_BAR_H + UiTokens.SPACE_4
## ROUND layout: the battles pill under the wordmark, the flyer, the round
## Play and the mode chip.
const ROUND_PILL_TOP := 170.0
const ROUND_FLYER := Vector2(180, 290)
const ROUND_PLAY := 128.0
const ROUND_PLAY_TOP := 342.0
const CHIP_TOP := ROUND_PLAY_TOP + ROUND_PLAY + UiTokens.SPACE_3
const CHIP_H := 42.0
const FLYER_BODY := 38.0
## The lost-spot line: a small paper pill above the bottom bar.
const NOTICE_H := 32.0

## Which layout Home draws (the user is picking between the two).
static var layout := Layout.BAR

var _profile: Profile
var _services: AppServices
var _logo: Label
var _flyer: FlyerArt
var _daily_rank := 0
var _settings: SettingsSheet
var _settings_button: Button
var _wallet: Wallet
var _prizes: DailyPrizePopup
var _notice: Label
var _mode := GameModes.CLASSIC
var _play: Button
var _play_text: Label
var _play_sub: Label
var _mode_button: Button
var _pill: BattlesPill
var _bar: HomeBar
var _sheet: ModeSheet
var _daily_info: DailyRunInfo
var _daily_result: DailyResultPopup
var _turns := 0
## GameModes.changes as last drawn: the server's version changed since.
var _seen_changes := -1


## daily_rank: the player's place on today's board, 0 for none yet.
func _init(profile: Profile, services: AppServices, daily_rank: int = 0) -> void:
	_profile = profile
	_services = services
	_daily_rank = daily_rank
	_mode = GameModes.find(profile.home_mode).id
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_settings_button = UiKit.disc_button(
		SETTINGS_ICON, "Settings", UiKit.Disc.PAPER, UiKit.ICON_BUTTON
	)
	_settings_button.name = "Settings"
	for state in ["normal", "hover", "disabled"]:
		_settings_button.add_theme_stylebox_override(state, UiTheme.solid(UiTokens.PANEL))
	for state in ["pressed", "hover_pressed"]:
		_settings_button.add_theme_stylebox_override(state, UiTheme.solid(UiTokens.PANEL_RAISED))
	_settings_button.pressed.connect(open_settings)
	UiKit.place_corner(self, _settings_button)
	_wallet = Wallet.new()
	_wallet.solid = true
	_wallet.show_balance(_profile)
	_wallet.name = "Coins"
	_wallet.pressed.connect(store_pressed.emit)
	add_child(_wallet)
	_wallet.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	_wallet.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_wallet.offset_left -= UiKit.CORNER.x
	_wallet.offset_right -= UiKit.CORNER.x
	var lift := (UiKit.ICON_BUTTON - UiTokens.SIZE_TAP_MIN) / 2.0
	_wallet.offset_top = UiKit.CORNER.y + lift
	_wallet.offset_bottom = UiKit.CORNER.y + lift + UiTokens.SIZE_TAP_MIN

	_logo = UiKit.label(WORDMARK, &"LogoLabel")
	_logo.name = "Logo"
	_logo.add_theme_font_size_override("font_size", LOGO_SIZE)
	_logo.add_theme_color_override("font_color", UiTokens.ON_SCRIM)
	_logo.add_theme_color_override("font_outline_color", UiTokens.INK_900)
	_logo.add_theme_constant_override("outline_size", LOGO_HALO)
	add_child(_logo)
	_logo.anchor_right = 1.0
	_logo.offset_top = LOGO_TOP
	_logo.offset_bottom = LOGO_TOP + _logo.get_combined_minimum_size().y

	var character := Catalog.flyer(_profile.equipped_id(ItemKind.FLYER))
	if character == null:
		character = Catalog.flyers()[0]
	_flyer = FlyerArt.new(character.idle, FLYER_BODY)
	_flyer.name = "Flyer"
	var box := _flyer.custom_minimum_size
	var at := BAR_FLYER if layout == Layout.BAR else ROUND_FLYER
	_flyer.position = at - Vector2(box.x / 2.0 + FLYER_BODY * 0.3, box.y / 2.0)
	_flyer.size = box
	add_child(_flyer)

	if layout == Layout.BAR:
		_build_bar()
	else:
		_build_round()
	_pill = BattlesPill.new()
	_pill.pressed.connect(_on_battles)
	add_child(_pill)
	_pill.anchor_right = 1.0
	var pill_side := SIDE if layout == Layout.BAR else SIDE + 14.0
	_pill.offset_left = pill_side
	_pill.offset_right = -pill_side
	_pill.offset_top = BAR_PILL_TOP if layout == Layout.BAR else ROUND_PILL_TOP
	_pill.offset_bottom = _pill.offset_top + BattlesPill.HEIGHT
	_bar = HomeBar.new()
	_bar.pressed.connect(_on_bar)
	add_child(_bar)
	_bar.anchor_right = 1.0
	_bar.offset_left = SIDE
	_bar.offset_right = -SIDE
	_bar.offset_top = BAR_TOP
	_bar.offset_bottom = BAR_TOP + HomeBar.HEIGHT
	set_daily_rank(_daily_rank)
	set_daily_info(null)


## BAR: a wide ink Play bar ("Play", the mode and its line), with a paper Mode
## button at its right end that opens the mode sheet.
func _build_bar() -> void:
	var holder := Control.new()
	holder.name = "PlayBar"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	holder.anchor_right = 1.0
	holder.offset_left = SIDE
	holder.offset_right = -SIDE
	holder.offset_top = PLAY_BAR_TOP
	holder.offset_bottom = PLAY_BAR_TOP + PLAY_BAR_H
	_play = _ink_button("Play")
	holder.add_child(_play)
	_play.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 26
	row.offset_right = -(MODE_BUTTON.x + 16)
	row.add_theme_constant_override("separation", UiTokens.SPACE_4)
	_play.add_child(row)
	var icon := TextureRect.new()
	icon.texture = PLAY_ICON
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(34, 34)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	_play_text = _on_ink_label(32, true)
	text.add_child(_play_text)
	_play_sub = _on_ink_label(UiTokens.FONT_SIZE_CAPTION, false)
	text.add_child(_play_sub)
	_mode_button = Button.new()
	_mode_button.name = "Mode"
	_mode_button.tooltip_text = "Choose a mode"
	_mode_button.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "focus"]:
		_mode_button.add_theme_stylebox_override(
			state, UiTheme.flat(UiTokens.PANEL, UiTokens.RADIUS_PILL, 0)
		)
	for state in ["pressed", "hover_pressed"]:
		_mode_button.add_theme_stylebox_override(
			state, UiTheme.flat(UiTokens.PANEL_RAISED, UiTokens.RADIUS_PILL, 0)
		)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 0)
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mode_button.add_child(stack)
	var word := UiKit.label("Mode", &"SmallNameLabel")
	word.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_CAPTION)
	stack.add_child(word)
	stack.add_child(_chevron_down(18.0))
	_mode_button.pressed.connect(open_modes)
	holder.add_child(_mode_button)
	_mode_button.anchor_left = 1.0
	_mode_button.anchor_right = 1.0
	_mode_button.anchor_top = 0.5
	_mode_button.anchor_bottom = 0.5
	_mode_button.offset_left = -MODE_BUTTON.x - 12
	_mode_button.offset_right = -12
	_mode_button.offset_top = -MODE_BUTTON.y / 2.0
	_mode_button.offset_bottom = MODE_BUTTON.y / 2.0


## ROUND: a big round ink Play in the middle of the room, and the mode on a
## paper chip under it that opens the mode sheet.
func _build_round() -> void:
	_play = UiKit.primary(PLAY_ICON, "Play")
	_play.name = "Play"
	_play.add_theme_font_size_override("font_size", 20)
	_play.add_theme_constant_override("icon_max_width", 40)
	var round_box := UiTheme.solid(UiTokens.PRIMARY, UiTokens.RADIUS_PILL, 0, 4)
	round_box.content_margin_top = 22
	round_box.content_margin_bottom = 18
	var round_down := round_box.duplicate() as StyleBoxFlat
	round_down.bg_color = UiTokens.INK_LINE.lightened(0.15)
	for state in ["normal", "hover", "focus", "disabled"]:
		_play.add_theme_stylebox_override(state, round_box)
	for state in ["pressed", "hover_pressed"]:
		_play.add_theme_stylebox_override(state, round_down)
	_play.pressed.connect(func() -> void: _start_mode(_mode))
	_play.custom_minimum_size = Vector2(ROUND_PLAY, ROUND_PLAY)
	add_child(_play)
	_play.anchor_left = 0.5
	_play.anchor_right = 0.5
	_play.offset_left = -ROUND_PLAY / 2.0
	_play.offset_right = ROUND_PLAY / 2.0
	_play.offset_top = ROUND_PLAY_TOP
	_play.offset_bottom = ROUND_PLAY_TOP + ROUND_PLAY
	_mode_button = Button.new()
	_mode_button.name = "Mode"
	_mode_button.tooltip_text = "Choose a mode"
	_mode_button.focus_mode = Control.FOCUS_NONE
	_mode_button.icon = CHEVRON_ICON
	_mode_button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mode_button.add_theme_constant_override("icon_max_width", 16)
	_mode_button.add_theme_constant_override("h_separation", UiTokens.SPACE_2)
	_mode_button.add_theme_font_override("font", GameFonts.ui(900))
	_mode_button.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_LABEL + 1)
	for state in [
		"font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"
	]:
		_mode_button.add_theme_color_override(state, UiTokens.ON_PANEL)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		_mode_button.add_theme_color_override(state, UiTokens.ON_PANEL)
	var chip := UiTheme.solid(UiTokens.PANEL)
	chip.content_margin_left = UiTokens.SPACE_4
	chip.content_margin_right = UiTokens.SPACE_3
	var chip_down := UiTheme.solid(UiTokens.PANEL_RAISED)
	chip_down.content_margin_left = chip.content_margin_left
	chip_down.content_margin_right = chip.content_margin_right
	for state in ["normal", "hover", "focus"]:
		_mode_button.add_theme_stylebox_override(state, chip)
	for state in ["pressed", "hover_pressed"]:
		_mode_button.add_theme_stylebox_override(state, chip_down)
	_mode_button.pressed.connect(open_modes)
	add_child(_mode_button)
	_mode_button.anchor_left = 0.5
	_mode_button.anchor_right = 0.5
	_mode_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_mode_button.offset_top = CHIP_TOP
	_mode_button.offset_bottom = CHIP_TOP + CHIP_H


## A chevron pointing down (the icon points right): "opens below".
func _chevron_down(side: float) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.custom_minimum_size = Vector2(side, side)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var icon := TextureRect.new()
	icon.texture = CHEVRON_ICON
	icon.modulate = UiTokens.ON_PANEL
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size = Vector2(side, side)
	icon.pivot_offset = Vector2(side, side) / 2.0
	icon.rotation_degrees = 90.0
	holder.add_child(icon)
	return holder


## The big ink Play with a paper ring: one tap plays the chosen mode.
func _ink_button(tip: String) -> Button:
	var b := Button.new()
	b.name = "Play"
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	var box := UiTheme.solid(UiTokens.PRIMARY, UiTokens.RADIUS_PILL, 0, 4)
	var down := UiTheme.solid(UiTokens.INK_LINE.lightened(0.15), UiTokens.RADIUS_PILL, 0, 4)
	for state in ["normal", "hover", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, box)
	for state in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(state, down)
	b.pressed.connect(func() -> void: _start_mode(_mode))
	return b


func _on_ink_label(size: int, display: bool) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", GameFonts.display() if display else GameFonts.ui(700))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override(
		"font_color", UiTokens.ON_PRIMARY if display else Color(UiTokens.PANEL, 0.86)
	)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l


func _process(_delta: float) -> void:
	if _seen_changes != GameModes.changes and _bar != null:
		set_daily_info(_daily_info)


func _on_bar(id: String) -> void:
	match id:
		"rooms":
			rooms_pressed.emit()
		"style":
			customize_pressed.emit()
		"rank":
			leaderboard_pressed.emit()
		"runs":
			runs_pressed.emit()


func _on_battles() -> void:
	AudioDirector.ui("tap")
	if GameModes.needs_update(GameModes.BATTLE):
		update_pressed.emit()
	else:
		battle_pressed.emit()


## "Best 87, #14 today"; just "Best 87" before today's first ranked run.
static func stats_text(best: int, rank: int) -> String:
	if rank > 0:
		return "Best %d, #%d today" % [best, rank]
	return "Best %d" % best


## The settings sheet over Home (the corner's Settings).
func open_settings() -> SettingsSheet:
	if _settings == null:
		_settings = SettingsSheet.new(_profile, _services)
		_settings.changed.connect(settings_changed.emit)
		_settings.practice_requested.connect(practice_requested.emit)
		_settings.seed_requested.connect(seed_requested.emit)
		_settings.closed.connect(func() -> void: _settings = null)
		add_child(_settings)
	return _settings


func settings() -> SettingsSheet:
	return _settings


## The corner's Settings button.
func settings_button() -> Button:
	return _settings_button


func wallet() -> Wallet:
	return _wallet


## The daily prize popup over Home (main claims when its button is pressed).
func show_prizes(prizes: Array) -> DailyPrizePopup:
	close_prizes()
	_prizes = DailyPrizePopup.new(prizes)
	_prizes.closed.connect(close_prizes)
	add_child(_prizes)
	return _prizes


func close_prizes() -> void:
	if _prizes != null:
		_prizes.queue_free()
		_prizes = null


func prize_popup() -> DailyPrizePopup:
	return _prizes


## Yesterday's Daily Run over Home (HomePopups shows it once after a reset).
func show_daily_result(past: DailyRunInfo.Yesterday) -> DailyResultPopup:
	close_daily_result()
	_daily_result = DailyResultPopup.new(past)
	_daily_result.closed.connect(close_daily_result)
	add_child(_daily_result)
	return _daily_result


func close_daily_result() -> void:
	if _daily_result != null:
		_daily_result.queue_free()
		_daily_result = null


func daily_result() -> DailyResultPopup:
	return _daily_result


## A line on the sky line: someone took the player's prize spot (SpotAlert).
func show_notice(text: String) -> void:
	if _notice == null:
		_notice = UiKit.label("", &"SmallNameLabel")
		_notice.name = "Notice"
		_notice.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_CAPTION + 1)
		var box := UiTheme.solid(UiTokens.PANEL)
		box.content_margin_left = UiTokens.SPACE_4
		box.content_margin_right = UiTokens.SPACE_4
		_notice.add_theme_stylebox_override("normal", box)
		_notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_notice.clip_text = true
		_notice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		add_child(_notice)
		_notice.anchor_left = 0.5
		_notice.anchor_right = 0.5
		_notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
		# BAR: above the bottom bar; ROUND: under the battles pill (the mode chip
		# sits above the bar there).
		var top := BAR_TOP - UiTokens.SPACE_3 - NOTICE_H
		if layout == Layout.ROUND:
			top = ROUND_PILL_TOP + BattlesPill.HEIGHT + UiTokens.SPACE_3
		_notice.offset_top = top
		_notice.offset_bottom = top + NOTICE_H
	_notice.text = text
	_notice.visible = not text.is_empty()
	# As wide as its text, up to the gutters (a longer line trims).
	var font := _notice.get_theme_font("font")
	var need := (
		font
		. get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, _notice.get_theme_font_size("font_size")
		)
		. x
	)
	_notice.custom_minimum_size.x = minf(
		need + UiTokens.SPACE_4 * 2 + 2, ScreenLayout.ROOM.x - SIDE * 2
	)
	_notice.offset_left = 0
	_notice.offset_right = 0


func notice_text() -> String:
	return _notice.text if _notice != null and _notice.visible else ""


## The wordmark, for tests.
func logo() -> Control:
	return _logo


## The big flyer, for tests.
func flyer() -> FlyerArt:
	return _flyer


## The big Play button: one tap plays the chosen mode.
func play_button() -> Button:
	return _play


## The Mode button (BAR) or the mode chip (ROUND): opens the mode sheet.
func mode_button() -> Button:
	return _mode_button


func battles_pill() -> BattlesPill:
	return _pill


## Today's Daily Run arrived (or null before it does, or offline).
func set_daily_info(info: DailyRunInfo) -> void:
	_daily_info = info
	_seen_changes = GameModes.changes
	_show_mode()


## The battles waiting for this player's turn (BattleFlow): the battles pill.
func set_battle_turns(n: int) -> void:
	_turns = n
	if _pill != null:
		_pill.set_turns(n)
	_show_mode()


## The mode sheet over Home (the Mode button or chip).
func open_modes() -> ModeSheet:
	if _sheet == null:
		var lines := {}
		var badges := {}
		for m in GameModes.all():
			lines[m.id] = _mode_line(m.id)
			badges[m.id] = GameModes.badge(m.id, _daily_info)
		if _turns > 0 and not GameModes.needs_update(GameModes.BATTLE):
			badges[GameModes.BATTLE] = str(_turns)
		_sheet = ModeSheet.new(_mode, lines, badges)
		_sheet.name = "ModeSheet"
		_sheet.picked.connect(choose_mode)
		_sheet.closed.connect(_close_modes)
		add_child(_sheet)
	return _sheet


func _close_modes() -> void:
	if _sheet != null:
		_sheet.queue_free()
		_sheet = null


## Chooses a mode (the sheet, a test): kept in the profile, Play follows it.
func choose_mode(id: String) -> void:
	var m := GameModes.find(id)
	if m.id == _mode:
		return
	_mode = m.id
	_profile.home_mode = _mode
	_show_mode()
	settings_changed.emit()


## One line about a mode now: Classic's best, the Daily Run's tries and clock,
## the battles waiting, Duel's rules, or Update to play.
func _mode_line(id: String) -> String:
	if GameModes.needs_update(id):
		return GameModes.UPDATE_LINE
	match id:
		GameModes.CLASSIC:
			return "Best %d" % _profile.best_score
		GameModes.BATTLE:
			if _turns > 0:
				return "%d your turn" % _turns
	return GameModes.rule_line(id, _daily_info)


## Play names the chosen mode: "Play" with "Classic · Best 87" (BAR), or
## "Play" over a "Classic · Best 87" chip (ROUND). An app too old for the mode
## says Update and opens the store.
func _show_mode() -> void:
	if _play == null:
		return
	var m := GameModes.find(_mode)
	var verb := GameModes.UPDATE if GameModes.needs_update(m.id) else "Play"
	var line := "%s · %s" % [m.tab_title, _mode_line(m.id)]
	if layout == Layout.BAR:
		_play_text.text = verb
		_play_sub.text = line
	else:
		_play.text = verb
		_mode_button.text = line
	_play.tooltip_text = "%s %s" % [verb, m.title]
	_play.disabled = not m.ready


## Today's rank arrived (or changed): a tag on Ranks.
func set_daily_rank(rank: int) -> void:
	_daily_rank = rank
	if _bar != null:
		_bar.set_tag("rank", "#%d" % rank if rank > 0 else "")


## Starts a mode: Classic plays a run, the Daily Run opens its screen.
func _start_mode(id: String) -> void:
	if GameModes.needs_update(id):
		update_pressed.emit()
		return
	match id:
		GameModes.CLASSIC:
			play_pressed.emit()
		GameModes.DAILY:
			daily_run_pressed.emit()
		GameModes.BATTLE:
			battle_pressed.emit()
		GameModes.DUEL:
			duel_pressed.emit()
		_:
			AudioDirector.ui("locked")
