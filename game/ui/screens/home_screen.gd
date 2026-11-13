class_name HomeScreen
extends Control
## The main menu over the live room, with no boxes, in three places (button
## system A3): the corners (Settings top left, where other screens have their
## way back, since Home has none; the wallet top right), the sky line (the
## "flapjaw" wordmark, "Best 87, #14 today", and the slot Daily Run's pill
## will use), and the cradle dock at the bottom: Rooms, Style | Play | Ranks,
## Runs. The flyer in use bobs big in the middle of the room with its puff trail.

signal play_pressed
## Opens one kind's list in Customize directly (nothing on Home emits it now;
## main still listens, for shortcuts to a kind).
signal shop_pressed(tab: String)
## Style (the dock): opens Customize on "Your look".
signal customize_pressed
signal rooms_pressed
## The wallet (gold and diamonds, top right): opens the Wallet (the Shop).
signal store_pressed
## Runs (the dock): opens Your runs.
signal runs_pressed
## Ranks (the dock): opens the leaderboards.
signal leaderboard_pressed
## A setting changed in the settings sheet (already in the profile): main
## saves it and applies it.
signal settings_changed
## The debug page's room picker: practise `id` with `variant`.
signal practice_requested(id: String, variant: String)
## The debug page's seed picker: play seed `seed_value` in `season` as practice.
signal seed_requested(seed_value: int, season: int)

const PLAY_ICON := preload("res://assets/ui/icons/play.svg")
const STYLE_ICON := preload("res://assets/ui/icons/customize.svg")
const ROOMS_ICON := preload("res://assets/ui/icons/rooms.svg")
const SETTINGS_ICON := preload("res://assets/ui/icons/settings.svg")
const TROPHY_ICON := preload("res://assets/ui/icons/trophy.svg")
const HISTORY_ICON := preload("res://assets/ui/icons/history.svg")
## The wordmark: one word, wide Archivo 900, ending well above the flyer.
const WORDMARK := "flapjaw"
const LOGO_TOP := 110.0
## 64px keeps "flapjaw" (7 wide letters) inside 24px side margins.
const LOGO_SIZE := 64
const STATS_TOP := 196.0
## The sky line under the stats: Daily Run's pill goes here (not built yet);
## until then the lost-spot line uses it.
const SKY_LINE_TOP := 232.0
const NOTICE_TOP := SKY_LINE_TOP
const NOTICE_WIDTH := 300.0
## The flyer's centre and body size on Home (bigger than in a run).
const FLYER_CENTER := Vector2(196, 346)
const FLYER_BODY := 52.0

var _profile: Profile
var _services: AppServices
var _logo: Label
var _stats: Label
var _flyer: FlyerArt
var _dock: Dock
var _daily_rank := 0
var _settings: SettingsSheet
var _settings_button: Button
var _wallet: Wallet
var _prizes: DailyPrizePopup
var _notice: Label


## daily_rank: the player's place on today's board, 0 for none yet.
func _init(profile: Profile, services: AppServices, daily_rank: int = 0) -> void:
	_profile = profile
	_services = services
	_daily_rank = daily_rank
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	# Settings in the corner slot: Home has no way back, so its corner holds it.
	# A cog on a paper disc, the same paper as the wallet's pill opposite it,
	# so Home's corner never reads as another screen's back arrow.
	_settings_button = UiKit.disc_button(
		SETTINGS_ICON, "Settings", UiKit.Disc.PAPER, UiKit.ICON_BUTTON
	)
	_settings_button.name = "Settings"
	_settings_button.pressed.connect(open_settings)
	UiKit.place_corner(self, _settings_button)
	# Gold and diamonds on a paper pill, top right, level with the corner; they
	# open the Wallet (the Shop).
	_wallet = Wallet.new()
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
				{"id": "rank", "icon": TROPHY_ICON, "text": "Ranks", "tip": "Leaderboards"},
				{"id": "runs", "icon": HISTORY_ICON, "text": "Runs", "tip": "Your runs"},
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
		"runs":
			runs_pressed.emit()


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


## A line on the sky line: someone took the player's prize spot (SpotAlert).
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


func stats_line() -> String:
	return _stats.text


## Today's rank arrived (or changed): shows it under the wordmark.
func set_daily_rank(rank: int) -> void:
	_daily_rank = rank
	if _stats != null:
		_stats.text = stats_text(_profile.best_score, rank)
