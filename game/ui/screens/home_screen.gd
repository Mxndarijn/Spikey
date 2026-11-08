class_name HomeScreen
extends Control
## The main menu over the live room (Sticker Pop): the Leaderboard button
## (best score and today's rank in one sticker), the coins and a gear for the
## sound settings, the tilted
## wordmark ("Spikey"), the flyer
## bobbing in the room, one loadout card (flyer, world and trail; tap it to
## customize), then a big
## gold Play button between round white Rooms and Shop buttons.

signal play_pressed
## The Shop button: opens Customize too.
signal shop_pressed(tab: String)
## The loadout card: opens Customize.
signal customize_pressed
signal rooms_pressed
## The Best / Rank sticker: opens the leaderboards.
signal leaderboard_pressed
## A sound setting changed in the gear's popup (already in the profile):
## main saves it and applies it.
signal settings_changed

const PLAY_ICON := preload("res://assets/ui/icons/play.svg")
const SHOP_ICON := preload("res://assets/ui/icons/shop.svg")
const ROOMS_ICON := preload("res://assets/ui/icons/rooms.svg")
const SETTINGS_ICON := preload("res://assets/ui/icons/settings.svg")
## Rooms and Shop sit either side of Play as labelled round buttons.
const SIDE_BUTTON := 68.0
const PLAY_HEIGHT := 72.0
const PLAY_FONT := 30
## The wordmark: one word, ending above the flyer bobbing at the start height
## (tests/unit/test_screen_fit.gd).
const LOGO_SIZE := 72
const LOGO_TILT := -4.0
const CARD_TILT := -1.0

var _profile: Profile
var _loadout: LoadoutCard
var _logo: Tilt
var _rank: RankButton
var _daily_rank := 0
var _settings: SoundSettings


## daily_rank: the player's place on today's board, 0 for none yet.
func _init(profile: Profile, daily_rank: int = 0) -> void:
	_profile = profile
	_daily_rank = daily_rank
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", UiTokens.SPACE_4 + 4)
	margin.add_theme_constant_override("margin_right", UiTokens.SPACE_4 + 4)
	margin.add_theme_constant_override("margin_top", UiTokens.SPACE_6)
	margin.add_theme_constant_override("margin_bottom", UiTokens.SPACE_7 + 2)
	add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", UiTokens.SPACE_3)
	margin.add_child(col)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rank = RankButton.new(_profile.best_score, _daily_rank)
	_rank.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rank.pressed.connect(leaderboard_pressed.emit)
	top.add_child(_rank)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(fill)
	var coins := CoinPill.new()
	coins.set_amount(_profile.coins)
	coins.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Coins and the gear sit close together; the row has no other gaps (the
	# filler spaces it), so it fits 360 px next to the Leaderboard button.
	var corner := HBoxContainer.new()
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corner.add_theme_constant_override("separation", UiTokens.SPACE_1 + 2)
	corner.add_child(coins)
	var gear := Button.new()
	gear.theme_type_variation = &"RoundButton"
	gear.icon = SETTINGS_ICON
	gear.tooltip_text = "Sound settings"
	gear.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gear.custom_minimum_size = Vector2(UiTokens.SIZE_TAP_MIN, UiTokens.SIZE_TAP_MIN)
	gear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gear.focus_mode = Control.FOCUS_NONE
	gear.pressed.connect(open_settings)
	corner.add_child(gear)
	top.add_theme_constant_override("separation", 0)
	top.add_child(corner)
	col.add_child(top)

	_logo = Tilt.new(_wordmark(), LOGO_TILT)
	_logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_logo)

	# Room for the flyer, which bobs in the middle of the room behind the menu.
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)

	_loadout = LoadoutCard.new(_profile)
	_loadout.pressed.connect(customize_pressed.emit)
	var card := Tilt.new(_loadout, CARD_TILT)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(card)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, UiTokens.SPACE_3)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)

	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", 10)
	var rooms := _side_button(ROOMS_ICON, "Rooms")
	(rooms.get_child(0) as Button).pressed.connect(rooms_pressed.emit)
	bottom.add_child(rooms)
	var play := Button.new()
	play.theme_type_variation = &"ActionButton"
	play.text = "Play"
	play.icon = PLAY_ICON
	play.add_theme_font_size_override("font_size", PLAY_FONT)
	_big_drop(play, UiTokens.ACTION, UiTheme.BORDER_BOLD)
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	play.custom_minimum_size = Vector2(0, PLAY_HEIGHT)
	play.focus_mode = Control.FOCUS_NONE
	play.pressed.connect(play_pressed.emit)
	bottom.add_child(play)
	var shop := _side_button(SHOP_ICON, "Shop")
	(shop.get_child(0) as Button).pressed.connect(shop_pressed.emit.bind(Catalog.FLYER))
	bottom.add_child(shop)
	col.add_child(bottom)


## The gear: the sound settings popup over the home screen.
func open_settings() -> SoundSettings:
	if _settings == null:
		_settings = SoundSettings.new(_profile)
		_settings.changed.connect(settings_changed.emit)
		_settings.closed.connect(func() -> void: _settings = null)
		add_child(_settings)
	return _settings


func settings() -> SoundSettings:
	return _settings


## "Spikey" in white, outlined with an ink drop.
func _wordmark() -> Control:
	var l := Label.new()
	l.theme_type_variation = &"LogoLabel"
	l.add_theme_font_size_override("font_size", LOGO_SIZE)
	l.text = "Spikey"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A round white button with its name under it (Rooms, Shop).
func _side_button(icon: Texture2D, label: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	var b := Button.new()
	b.theme_type_variation = &"RoundButton"
	b.icon = icon
	b.tooltip_text = label
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("icon_max_width", 30)
	_big_drop(b, UiTokens.PANEL, UiTheme.BORDER)
	b.custom_minimum_size = Vector2(SIDE_BUTTON, SIDE_BUTTON)
	b.focus_mode = Control.FOCUS_NONE
	box.add_child(b)
	var l := Label.new()
	l.theme_type_variation = &"SkyCaption"
	l.text = label
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	return box


## Play and Shop drop 6px straight down, like the board's big buttons.
func _big_drop(b: Button, fill: Color, border: int) -> void:
	var box := UiTheme.sticker(fill, UiTokens.RADIUS_PILL, Vector2(0, 6), 8, border)
	b.add_theme_stylebox_override("normal", box)
	b.add_theme_stylebox_override("hover", box)
	b.add_theme_stylebox_override("pressed", box.pressed())
	b.add_theme_stylebox_override("hover_pressed", box.pressed())


## The wordmark (tilted), for tests.
func logo() -> Control:
	return _logo


## Today's rank arrived (or changed): shows it on the Leaderboard button.
func set_daily_rank(rank: int) -> void:
	_daily_rank = rank
	if _rank != null:
		_rank.set_rank(rank)


## The Leaderboard button (best score and today's rank), for tests.
func rank_button() -> RankButton:
	return _rank


## The loadout card (flyer, world and trail in use), for tests.
func loadout() -> LoadoutCard:
	return _loadout
