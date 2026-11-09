class_name HomeScreen
extends Control
## The main menu over the live room, with no boxes: the coin balance top
## right, the "flapjaw" wordmark, "Best 87, #14 today" under it, the flyer in
## use bobbing big in the middle of the room with its puff trail, and the
## cradle dock at the bottom: Rooms, Style | Play | #rank, Settings.
## Settings opens the settings sheet over Home.

signal play_pressed
## Opens one kind's list in Customize directly (nothing on Home emits it now;
## main still listens, for shortcuts to a kind).
signal shop_pressed(tab: String)
## Style (the dock): opens Customize on "Your look".
signal customize_pressed
signal rooms_pressed
## The #rank item: opens the leaderboards.
signal leaderboard_pressed
## A setting changed in the settings sheet (already in the profile): main
## saves it and applies it.
signal settings_changed

const PLAY_ICON := preload("res://assets/ui/icons/play.svg")
const STYLE_ICON := preload("res://assets/ui/icons/customize.svg")
const ROOMS_ICON := preload("res://assets/ui/icons/rooms.svg")
const SETTINGS_ICON := preload("res://assets/ui/icons/settings.svg")
const TROPHY_ICON := preload("res://assets/ui/icons/trophy.svg")
## The wordmark: one word, wide Archivo 900, ending well above the flyer.
const WORDMARK := "flapjaw"
const LOGO_TOP := 118.0
## 64px keeps "flapjaw" (7 wide letters) inside 24px side margins.
const LOGO_SIZE := 64
const STATS_TOP := 236.0
## The flyer's centre and body size on Home (bigger than in a run).
const FLYER_CENTER := Vector2(196, 346)
const FLYER_BODY := 52.0

var _profile: Profile
var _logo: Label
var _stats: Label
var _flyer: FlyerArt
var _dock: Dock
var _daily_rank := 0
var _settings: SettingsSheet


## daily_rank: the player's place on today's board, 0 for none yet.
func _init(profile: Profile, daily_rank: int = 0) -> void:
	_profile = profile
	_daily_rank = daily_rank
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	var coins := CoinPill.new()
	coins.set_amount(_profile.coins)
	coins.name = "Coins"
	add_child(coins)
	coins.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	coins.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	coins.offset_left -= 20
	coins.offset_right -= 20
	coins.offset_top = 50
	coins.offset_bottom = 50 + CoinPill.ICON_SIZE

	_logo = _row_label(WORDMARK, &"LogoLabel", LOGO_TOP)
	_logo.add_theme_font_size_override("font_size", LOGO_SIZE)
	_stats = _row_label(stats_text(_profile.best_score, _daily_rank), &"SkyCaption", STATS_TOP)

	var character := Catalog.flyer(_profile.equipped_id(Catalog.FLYER))
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
		_settings = SettingsSheet.new(_profile)
		_settings.changed.connect(settings_changed.emit)
		_settings.closed.connect(func() -> void: _settings = null)
		add_child(_settings)
	return _settings


func settings() -> SettingsSheet:
	return _settings


## The wordmark, for tests.
func logo() -> Control:
	return _logo


## The big flyer, for tests.
func flyer() -> FlyerArt:
	return _flyer


func dock() -> Dock:
	return _dock


func stats_line() -> String:
	return _stats.text


## Today's rank arrived (or changed): shows it under the wordmark and in the dock.
func set_daily_rank(rank: int) -> void:
	_daily_rank = rank
	if _stats != null:
		_stats.text = stats_text(_profile.best_score, rank)
	if _dock != null:
		_dock.set_text("rank", rank_text())
