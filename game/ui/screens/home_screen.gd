class_name HomeScreen
extends Control
## The main menu over the live room, calm and solid. Every element is a solid
## UI surface (UiTheme.solid: paper with an ink ring, ink with a paper ring), so
## it reads on every world's sky, light or night. From the top: Settings and
## the wallet in the corners, the "flapjaw" wordmark (ink in a paper halo), the
## flyer, then the one big Play for the chosen mode (Classic by default) with
## the Mode button at its end (a tap there opens ModeSheet), one small battles
## pill (your turns, See all) with the lost-spot news under it, and the bottom
## bar (Rooms, Style, Ranks, Runs). Best and today's rank are on Play's line.
## Play is a wide ink bar ("Play", the mode and one fact about it) with a paper
## Mode button at its right end (docs/ui-rework: the user's pick, option 1).

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

const PLAY_ICON := preload("res://assets/ui/icons/play.svg")
const SETTINGS_ICON := preload("res://assets/ui/icons/settings.svg")
const CHEVRON_ICON := preload("res://assets/ui/icons/chevron.svg")
## The wordmark: one word, wide Archivo 900, white in an ink halo.
const WORDMARK := "flapjaw"
const LOGO_TOP := 108.0
const LOGO_SIZE := 58
const LOGO_HALO := 10
const SIDE := float(UiTokens.SPACE_4)
## Home keeps this far off both spike rows (a game about spikes: controls
## close to them look cramped).
const SPIKE_GAP := 18.0
## The corners' top: SPIKE_GAP under the ceiling spike row.
const CORNER_TOP := float(SimConfig.KILL_TOP / SimConfig.SUB) + SPIKE_GAP
## The bottom bar, SPIKE_GAP above the floor spike row.
const BAR_TOP := float(SimConfig.KILL_BOTTOM / SimConfig.SUB) - SPIKE_GAP - HomeBar.HEIGHT
## The flyer, the Play bar, the battles pill.
const BAR_FLYER := Vector2(180, 246)
const PLAY_BAR_TOP := 306.0
const PLAY_BAR_H := 88.0
const MODE_BUTTON := Vector2(76, 64)
const BAR_PILL_TOP := PLAY_BAR_TOP + PLAY_BAR_H + UiTokens.SPACE_4
const FLYER_BODY := 43.0
## The lost-spot line: a small paper pill above the bottom bar.
const NOTICE_H := 32.0

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
## A night world (the room's text is white): Play turns paper with ink text, as
## ink would vanish on the dark sky.
var _night := false
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
	_settings_button.offset_top = CORNER_TOP
	_settings_button.offset_bottom = CORNER_TOP + UiKit.ICON_BUTTON
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
	_wallet.offset_top = CORNER_TOP + lift
	_wallet.offset_bottom = CORNER_TOP + lift + UiTokens.SIZE_TAP_MIN

	_logo = UiKit.label(WORDMARK, &"LogoLabel")
	_logo.name = "Logo"
	_logo.add_theme_font_size_override("font_size", LOGO_SIZE)
	# Ink letters in a paper halo: the ink carries it on light skies, the halo on
	# night ones.
	_logo.add_theme_color_override("font_color", UiTokens.INK_LINE)
	_logo.add_theme_color_override("font_outline_color", UiTokens.PANEL)
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
	_flyer.position = BAR_FLYER - Vector2(box.x / 2.0 + FLYER_BODY * 0.3, box.y / 2.0)
	_flyer.size = box
	add_child(_flyer)

	_night = get_theme_color("font_color", &"SkyLabel").get_luminance() > 0.5
	_build_bar()
	_pill = BattlesPill.new()
	_pill.pressed.connect(_on_battles)
	add_child(_pill)
	_pill.anchor_right = 1.0
	_pill.offset_left = SIDE
	_pill.offset_right = -SIDE
	_pill.offset_top = BAR_PILL_TOP
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
	icon.modulate = _play_ink()
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
	_play_sub = _on_ink_label(UiTokens.FONT_SIZE_LABEL, false)
	text.add_child(_play_sub)
	_mode_button = Button.new()
	_mode_button.name = "Mode"
	_mode_button.tooltip_text = "Choose a mode"
	_mode_button.focus_mode = Control.FOCUS_NONE
	# A quiet segment of the bar itself, a shade off Play's fill, so Play stays
	# the loudest thing; its name and chevron in Play's text colour.
	var seg := _play_fill().lightened(0.12) if not _night else UiTokens.PANEL_RAISED
	var seg_down := seg.lightened(0.1) if not _night else UiTokens.EDGE
	for state in ["normal", "hover", "focus"]:
		_mode_button.add_theme_stylebox_override(state, UiTheme.flat(seg, UiTokens.RADIUS_PILL, 0))
	for state in ["pressed", "hover_pressed"]:
		_mode_button.add_theme_stylebox_override(
			state, UiTheme.flat(seg_down, UiTokens.RADIUS_PILL, 0)
		)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 0)
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mode_button.add_child(stack)
	var word := UiKit.label("Mode", &"SmallNameLabel")
	word.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_CAPTION)
	word.add_theme_color_override("font_color", _play_ink())
	stack.add_child(word)
	stack.add_child(_chevron_down(18.0, _play_ink()))
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


## A chevron pointing down (the icon points right): "opens below".
func _chevron_down(side: float, color: Color = UiTokens.ON_PANEL) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.custom_minimum_size = Vector2(side, side)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var icon := TextureRect.new()
	icon.texture = CHEVRON_ICON
	icon.modulate = color
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size = Vector2(side, side)
	icon.pivot_offset = Vector2(side, side) / 2.0
	icon.rotation_degrees = 90.0
	holder.add_child(icon)
	return holder


## The big Play: ink with a paper ring (paper with an ink ring on night
## worlds). One tap plays the chosen mode.
func _ink_button(tip: String) -> Button:
	var b := Button.new()
	b.name = "Play"
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	var box := UiTheme.solid(_play_fill(), UiTokens.RADIUS_PILL, 0, 4)
	var down_fill := _play_fill().lightened(0.15) if not _night else UiTokens.PANEL_RAISED
	var down := UiTheme.solid(down_fill, UiTokens.RADIUS_PILL, 0, 4)
	for state in ["normal", "hover", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, box)
	for state in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(state, down)
	b.pressed.connect(func() -> void: _start_mode(_mode))
	return b


func _play_fill() -> Color:
	return UiTokens.PANEL if _night else UiTokens.PRIMARY


## Play's text and icon colour.
func _play_ink() -> Color:
	return UiTokens.ON_PANEL if _night else UiTokens.ON_PRIMARY


func _on_ink_label(size: int, display: bool) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", GameFonts.display() if display else GameFonts.ui(700))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", _play_ink())
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
		# Under the battles pill and as wide: the news belongs to it.
		_notice.anchor_left = 0.0
		_notice.anchor_right = 1.0
		_notice.offset_left = SIDE
		_notice.offset_right = -SIDE
		var top := BAR_PILL_TOP + BattlesPill.HEIGHT + UiTokens.SPACE_2
		_notice.offset_top = top
		_notice.offset_bottom = top + NOTICE_H
	_notice.text = text
	_notice.visible = not text.is_empty()


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
			# Only UPDATE: a count would repeat the line beside it.
			if GameModes.needs_update(m.id):
				badges[m.id] = GameModes.UPDATE.to_upper()
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
			if _daily_rank > 0:
				return "Best %d · #%d today" % [_profile.best_score, _daily_rank]
			return "Best %d" % _profile.best_score
		GameModes.BATTLE:
			if _turns > 0:
				return BattlesPill.turns_text(_turns)
	return GameModes.rule_line(id, _daily_info)


## The one fact under Play (the mode sheet has the full line): Classic's best,
## the Daily Run's tries, the battles waiting, Duel's kind.
func _short_line(id: String) -> String:
	if GameModes.needs_update(id):
		return "Update to play"
	match id:
		GameModes.CLASSIC:
			return "Best %d" % _profile.best_score
		GameModes.DAILY:
			if _daily_info != null and _daily_info.is_online():
				var left := _daily_info.tries_left()
				return (
					"%d %s left" % [left, "try" if left == 1 else "tries"]
					if left > 0
					else "Done today"
				)
			return "One map a day"
		GameModes.BATTLE:
			return "%d waiting" % _turns if _turns > 0 else "First to 6"
	return "Live 1v1"


## Play names the chosen mode: "Play" with "Classic · Best 87" under it. An
## app too old for the mode says Update and opens the store.
func _show_mode() -> void:
	if _play == null:
		return
	var m := GameModes.find(_mode)
	var verb := GameModes.UPDATE if GameModes.needs_update(m.id) else "Play"
	var line := "%s · %s" % [m.tab_title, _short_line(m.id)]
	_play_text.text = verb
	_play_sub.text = line
	_play.tooltip_text = "%s %s" % [verb, m.title]
	_play.disabled = not m.ready


## Today's rank arrived (or changed): a tag on Ranks.
func set_daily_rank(rank: int) -> void:
	_daily_rank = rank
	_show_mode()


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
