class_name HomeScreen
extends Control
## The main menu over the live room, with no boxes: the coin balance top
## right, the "flapjaw" wordmark, "Best 87, #14 today" under it, the flyer in
## use bobbing big in the middle of the room with its puff trail, and the
## cradle dock at the bottom: Rooms, Style | Play | #rank, Settings.
## Shop sits top left, opposite the wallet. Above the dock, the Your runs card
## shows the last run ("Last: 17 in Sunset, just now"); it opens Your runs,
## and its replay button watches that run. Settings opens the settings sheet.

signal play_pressed
## Opens one kind's list in Customize directly (nothing on Home emits it now;
## main still listens, for shortcuts to a kind).
signal shop_pressed(tab: String)
## Style (the dock): opens Customize on "Your look".
signal customize_pressed
signal rooms_pressed
## The wallet (gold and diamonds, top right) and the Shop pill: open the Shop.
signal store_pressed
## The Your runs card.
signal runs_pressed
## The card's replay button: watch the last run.
signal watch_last_pressed(record: RunRecord)
## The #rank item: opens the leaderboards.
signal leaderboard_pressed
## A setting changed in the settings sheet (already in the profile): main
## saves it and applies it.
signal settings_changed
## The debug page's room picker: practise `id` with `variant`.
signal practice_requested(id: String, variant: String)
## The debug page's seed picker: play seed `seed_value` as practice.
signal seed_requested(seed_value: int)

const PLAY_ICON := preload("res://assets/ui/icons/play.svg")
const STYLE_ICON := preload("res://assets/ui/icons/customize.svg")
const ROOMS_ICON := preload("res://assets/ui/icons/rooms.svg")
const SETTINGS_ICON := preload("res://assets/ui/icons/settings.svg")
const TROPHY_ICON := preload("res://assets/ui/icons/trophy.svg")
const SHOP_ICON := preload("res://assets/ui/icons/shop.svg")
const HISTORY_ICON := preload("res://assets/ui/icons/history.svg")
const REPLAY_ICON := preload("res://assets/ui/icons/replay.svg")
## The wordmark: one word, wide Archivo 900, ending well above the flyer.
const WORDMARK := "flapjaw"
const LOGO_TOP := 118.0
## 64px keeps "flapjaw" (7 wide letters) inside 24px side margins.
const LOGO_SIZE := 64
const STATS_TOP := 236.0
## The lost-spot line, between the stats and the flyer.
const NOTICE_TOP := 262.0
const NOTICE_WIDTH := 300.0
## The flyer's centre and body size on Home (bigger than in a run).
const FLYER_CENTER := Vector2(196, 346)
const FLYER_BODY := 52.0
## The Your runs card, between the flyer and the dock.
const RUNS_CARD := Rect2(36, 394, 288, 60)
const RUNS_REPLAY := 48.0
const NO_RUNS := "Your last 100 runs show up here"

var _profile: Profile
var _services: AppServices
var _logo: Label
var _stats: Label
var _flyer: FlyerArt
var _dock: Dock
var _daily_rank := 0
var _settings: SettingsSheet
var _wallet: Wallet
var _prizes: DailyPrizePopup
var _notice: Label
var _last_run: RunRecord
var _shop: Button
var _runs_card: Button
var _runs_line: Label
var _replay: Button


## daily_rank: the player's place on today's board, 0 for none yet.
## last_run: the newest of the player's runs (RunHistory.last()), or null.
func _init(
	profile: Profile, services: AppServices, daily_rank: int = 0, last_run: RunRecord = null
) -> void:
	_profile = profile
	_services = services
	_daily_rank = daily_rank
	_last_run = last_run
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	# Gold and diamonds, top right; tapping them opens the Shop.
	_wallet = Wallet.new()
	_wallet.show_balance(_profile)
	_wallet.name = "Coins"
	_wallet.pressed.connect(store_pressed.emit)
	add_child(_wallet)
	_wallet.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	_wallet.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_wallet.offset_left -= 20
	_wallet.offset_right -= 20
	var lift := (UiTokens.SIZE_TAP_MIN - CoinPill.ICON_SIZE) / 2.0
	_wallet.offset_top = 50 - lift
	_wallet.offset_bottom = 50 + CoinPill.ICON_SIZE + lift

	_add_shop(lift)

	_logo = _row_label(WORDMARK, &"LogoLabel", LOGO_TOP)
	_logo.add_theme_font_size_override("font_size", LOGO_SIZE)
	_stats = _row_label(stats_text(_profile.best_score, _daily_rank), &"SkyCaption", STATS_TOP)

	var character := Catalog.flyer(_profile.equipped_id(ItemKind.FLYER))
	if character == null:
		character = Catalog.flyers()[0]
	_flyer = FlyerArt.new(character.idle, FLYER_BODY)
	_flyer.name = "Flyer"
	var box := _flyer.custom_minimum_size
	_flyer.position = FLYER_CENTER - Vector2(box.x / 2.0 + FLYER_BODY * 0.3, box.y / 2.0)
	_flyer.size = box
	add_child(_flyer)

	_dock = (
		Dock
		. new(
			[
				{"id": "rooms", "icon": ROOMS_ICON, "text": "Rooms"},
				{"id": "style", "icon": STYLE_ICON, "text": "Style"},
			],
			[
				{"id": "rank", "icon": TROPHY_ICON, "text": rank_text(), "tip": "Leaderboards"},
				{"id": "settings", "icon": SETTINGS_ICON, "text": "Settings"},
			],
			{"id": "play", "icon": PLAY_ICON, "text": "Play"}
		)
	)
	_dock.pressed.connect(_on_dock)
	add_child(_dock)
	_add_runs_card()


## Shop, top left: a paper pill level with the wallet.
func _add_shop(lift: float) -> void:
	_shop = Button.new()
	_shop.name = "Shop"
	_shop.icon = SHOP_ICON
	_shop.text = "Shop"
	_shop.focus_mode = Control.FOCUS_NONE
	_shop.add_theme_constant_override("icon_max_width", 22)
	var pill := UiTheme.flat(UiTokens.PANEL, UiTokens.RADIUS_PILL, 0)
	pill.content_margin_left = 12
	pill.content_margin_right = 16
	var down := pill.duplicate() as StyleBoxFlat
	down.bg_color = UiTokens.PANEL_RAISED
	for state in ["normal", "hover"]:
		_shop.add_theme_stylebox_override(state, pill)
	for state in ["pressed", "hover_pressed"]:
		_shop.add_theme_stylebox_override(state, down)
	_shop.custom_minimum_size = Vector2(0, UiTokens.SIZE_TAP_MIN)
	_shop.position = Vector2(16, 50 - lift)
	_shop.pressed.connect(store_pressed.emit)
	add_child(_shop)


## The Your runs card: the history icon, "Your runs" and the last run, and a
## replay button for that run (none before the first run, or for a run from
## an older version, which can't be watched).
func _add_runs_card() -> void:
	_runs_card = Button.new()
	_runs_card.name = "RunsCard"
	_runs_card.focus_mode = Control.FOCUS_NONE
	_runs_card.tooltip_text = "Your runs"
	var card := UiTheme.flat(UiTokens.PANEL, UiTokens.RADIUS_M, 0)
	var down := card.duplicate() as StyleBoxFlat
	down.bg_color = UiTokens.PANEL_RAISED
	for state in ["normal", "hover"]:
		_runs_card.add_theme_stylebox_override(state, card)
	for state in ["pressed", "hover_pressed"]:
		_runs_card.add_theme_stylebox_override(state, down)
	_runs_card.position = RUNS_CARD.position
	_runs_card.size = RUNS_CARD.size
	_runs_card.custom_minimum_size = RUNS_CARD.size
	_runs_card.pressed.connect(runs_pressed.emit)
	add_child(_runs_card)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_right = -6
	row.add_theme_constant_override("separation", 10)
	_runs_card.add_child(row)
	var icon := TextureRect.new()
	icon.texture = HISTORY_ICON
	icon.modulate = UiTokens.ON_PANEL
	icon.custom_minimum_size = Vector2(UiTokens.SIZE_ICON_M, UiTokens.SIZE_ICON_M)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	var title := UiKit.label("Your runs", &"SmallNameLabel", false)
	title.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_BUTTON)
	col.add_child(title)
	_runs_line = UiKit.label(runs_line_text(_last_run), &"MutedLabel", false)
	_runs_line.add_theme_font_size_override("font_size", UiTokens.FONT_SIZE_CAPTION)
	_runs_line.clip_text = true
	_runs_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(_runs_line)
	row.add_child(col)
	_replay = UiKit.icon_button(REPLAY_ICON, "Watch your last run again", &"InkButton", RUNS_REPLAY)
	_replay.name = "WatchLast"
	_replay.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var disc := UiTheme.flat(UiTokens.PANEL_RAISED, UiTokens.RADIUS_PILL, 0)
	var disc_down := UiTheme.flat(UiTokens.EDGE, UiTokens.RADIUS_PILL, 0)
	for state in ["normal", "hover"]:
		_replay.add_theme_stylebox_override(state, disc)
	for state in ["pressed", "hover_pressed"]:
		_replay.add_theme_stylebox_override(state, disc_down)
	_replay.visible = _last_run != null and _last_run.watchable()
	_replay.pressed.connect(func() -> void: watch_last_pressed.emit(_last_run))
	row.add_child(_replay)


## "Last: 17 in Sunset, just now", or a line on what the card is before the
## first run.
static func runs_line_text(r: RunRecord, now: int = -1) -> String:
	if r == null:
		return NO_RUNS
	var at := now if now >= 0 else int(Time.get_unix_time_from_system())
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var when := RunRow.when_text(r.played_at, at, bias)
	if when.length() > 0 and when[0] != when[0].to_lower():
		when = when[0].to_lower() + when.substr(1)
	if when.begins_with("today, "):
		when = "today at " + when.substr(7)
	return "Last: %d in %s, %s" % [r.score(), RunRow.world_name(r.world), when]


func _row_label(text: String, variation: StringName, top: float) -> Label:
	var l := UiKit.label(text, variation)
	add_child(l)
	l.anchor_right = 1.0
	l.offset_top = top
	l.offset_bottom = top + l.get_combined_minimum_size().y
	return l


func _on_dock(id: String) -> void:
	match id:
		"play":
			play_pressed.emit()
		"rooms":
			rooms_pressed.emit()
		"style":
			customize_pressed.emit()
		"rank":
			leaderboard_pressed.emit()
		"settings":
			open_settings()


## "Best 87, #14 today"; just "Best 87" before today's first ranked run.
static func stats_text(best: int, rank: int) -> String:
	if rank > 0:
		return "Best %d, #%d today" % [best, rank]
	return "Best %d" % best


## The dock's leaderboard item: today's rank, or "Ranks" without one.
func rank_text() -> String:
	return "#%d" % _daily_rank if _daily_rank > 0 else "Ranks"


## The settings sheet over Home (the dock's Settings).
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


## A line under the stats: someone took the player's prize spot (SpotAlert).
func show_notice(text: String) -> void:
	if _notice == null:
		_notice = UiKit.wrapped("", &"SkyCaption", NOTICE_WIDTH)
		_notice.add_theme_font_size_override("font_size", 13)
		add_child(_notice)
		_notice.anchor_right = 1.0
		_notice.offset_left = (ScreenLayout.ROOM.x - NOTICE_WIDTH) / 2.0
		_notice.offset_right = -_notice.offset_left
		_notice.offset_top = NOTICE_TOP
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


func dock() -> Dock:
	return _dock


func shop_button() -> Button:
	return _shop


func runs_card() -> Button:
	return _runs_card


func runs_line() -> String:
	return _runs_line.text


func replay_button() -> Button:
	return _replay


func stats_line() -> String:
	return _stats.text


## Today's rank arrived (or changed): shows it under the wordmark and in the dock.
func set_daily_rank(rank: int) -> void:
	_daily_rank = rank
	if _stats != null:
		_stats.text = stats_text(_profile.best_score, rank)
	if _dock != null:
		_dock.set_text("rank", rank_text())
