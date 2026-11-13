class_name DailyPrizePopup
extends Control
## "You finished #2": the diamonds a player won, shown on Home on the next
## start: a daily top-10 finish, a best-score milestone or a 7-day streak
## (WalletService kinds). A flat paper card over the dimmed room with the
## headline (the place, "Best 50" or "7 days"), what it is, the diamonds won
## and one Claim button; the close button in the card's top right keeps the
## prizes for the next start. Under Claim the text button "Ways to earn
## diamonds" opens the Wallet's Earn free tab (the prizes stay unclaimed). With
## several unclaimed prizes it shows the latest daily place (else the latest
## bonus) and claims them all at once.

signal claim_pressed
signal closed
## "Ways to earn diamonds".
signal earn_pressed

const DIAMOND_ICON := preload("res://assets/ui/diamond.svg")
const SIDE := 28
## BigPanel's inner padding on each side (UiTheme).
const CARD_PAD := 20
const HEADLINE_SIZE := 64
const HEADLINE_MIN := 32
## Room for the headline on the narrowest (360 wide) screen.
const HEADLINE_W := UiTokens.SIZE_VIEWPORT_W - 2 * (SIDE + CARD_PAD)
const MONTHS: Array[String] = [
	"January",
	"February",
	"March",
	"April",
	"May",
	"June",
	"July",
	"August",
	"September",
	"October",
	"November",
	"December",
]
const FAILED := "Couldn't claim right now. Try again later."
const EARN_LINK := "Ways to earn diamonds"

var _prizes: Array = []
var _claim := Button.new()
var _note := Label.new()
var _rank := Label.new()
var _line := Label.new()
var _earn := Button.new()


## prizes: WalletService.synced's list, oldest first. Must not be empty.
func _init(prizes: Array) -> void:
	_prizes = prizes
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var scrim := ColorRect.new()
	scrim.color = UiTokens.SCRIM
	ScrimBleed.attach(scrim)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", SIDE)
	margin.add_theme_constant_override("margin_right", SIDE)
	add_child(margin)
	var card := PanelContainer.new()
	card.theme_type_variation = &"BigPanel"
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	margin.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTokens.SPACE_3)
	card.add_child(col)

	var day := UiKit.label(day_line(latest()), &"MutedLabel", false)
	col.add_child(UiKit.card_head(day, closed.emit))
	_rank.theme_type_variation = &"NameLabel"
	_rank.text = headline(latest())
	_rank.add_theme_font_size_override("font_size", headline_size(_rank.text))
	_rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Never let the headline widen the card past the screen edge.
	_rank.clip_text = true
	col.add_child(_rank)
	_line.theme_type_variation = &"InkLabel"
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.custom_minimum_size = Vector2(200, 0)
	_line.text = summary()
	col.add_child(_line)

	_claim.theme_type_variation = &"ActionButton"
	_claim.icon = DIAMOND_ICON
	_claim.add_theme_constant_override("icon_max_width", 22)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		_claim.add_theme_color_override(state, Color.WHITE)
	_claim.text = "Claim %d" % total()
	_claim.tooltip_text = "Claim %s" % diamonds_text(total())
	_claim.custom_minimum_size = Vector2(0, UiTokens.SIZE_BUTTON_H)
	_claim.focus_mode = Control.FOCUS_NONE
	UiKit.center_icon_group(_claim)
	_claim.pressed.connect(_on_claim)
	col.add_child(_claim)
	_note.theme_type_variation = &"MutedLabel"
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(200, 0)
	# Only a failed claim says something here.
	_note.visible = false
	col.add_child(_note)
	# The card's one text button: it opens the Wallet's Earn free tab.
	_earn.theme_type_variation = &"InkButton"
	_earn.text = EARN_LINK
	_earn.custom_minimum_size = Vector2(0, UiTokens.SIZE_TAP_MIN)
	_earn.focus_mode = Control.FOCUS_NONE
	_earn.pressed.connect(earn_pressed.emit)
	col.add_child(_earn)


## The prize in the headline: the most recent daily one, else the last bonus.
func latest() -> Dictionary:
	var pick := {}
	for p: Dictionary in _prizes:
		if pick.is_empty() or is_daily(p) or not is_daily(pick):
			pick = p
	return pick


## Prizes from before the bonuses carry no kind: they are daily ones.
static func is_daily(prize: Dictionary) -> bool:
	return str(prize.get("kind", WalletService.DAILY)) == WalletService.DAILY


## "#2" for a daily place, "Best 50" for a milestone, "7 days" for a streak.
static func headline(prize: Dictionary) -> String:
	match str(prize.get("kind", WalletService.DAILY)):
		WalletService.MILESTONE:
			return "Best %s" % str(prize.get("ref", ""))
		WalletService.STREAK:
			return "7 days"
	return "#%d" % int(prize.get("rank", 0))


## The largest font size (64 down to 32) at which `text` fits the card:
## "#2" stays big, "Best 50" and "Best 1000" shrink to fit.
static func headline_size(text: String) -> int:
	return UiKit.fit_font_size(text, GameFonts.display(), HEADLINE_SIZE, HEADLINE_W, HEADLINE_MIN)


## All diamonds waiting to be claimed.
func total() -> int:
	var sum := 0
	for p: Dictionary in _prizes:
		sum += int(p.get("diamonds", 0))
	return sum


## "You won 2 diamonds."; with more waiting, "You won 5 diamonds over 3 days."
## (all daily) or "You won 5 diamonds from 3 prizes." (mixed).
func summary() -> String:
	if _prizes.size() <= 1:
		return "You won %s." % diamonds_text(total())
	for p: Dictionary in _prizes:
		if not is_daily(p):
			return "You won %s from %d prizes." % [diamonds_text(total()), _prizes.size()]
	return "You won %s over %d days." % [diamonds_text(total()), _prizes.size()]


static func diamonds_text(count: int) -> String:
	return "1 diamond" if count == 1 else "%d diamonds" % count


## "Daily board, 9 November" from a daily prize's "2026-11-09" day; what a
## bonus is for otherwise.
static func day_line(prize: Dictionary) -> String:
	match str(prize.get("kind", WalletService.DAILY)):
		WalletService.MILESTONE:
			return "New best score"
		WalletService.STREAK:
			return "Played 7 days in a row"
	var parts := str(prize.get("day", "")).split("-")
	if parts.size() != 3 or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return "Daily board"
	var month := int(parts[1])
	if month < 1 or month > 12:
		return "Daily board"
	return "Daily board, %d %s" % [int(parts[2]), MONTHS[month - 1]]


func _on_claim() -> void:
	_claim.disabled = true
	claim_pressed.emit()


## The claim did not go through: say so and let the player try again.
func show_failed() -> void:
	_claim.disabled = false
	_note.text = FAILED
	_note.visible = true
	_note.add_theme_color_override("font_color", UiTokens.DANGER)


func rank_text() -> String:
	return _rank.text


func claim_text() -> String:
	return _claim.text


func note_text() -> String:
	return _note.text if _note.visible else ""


func earn_button() -> Button:
	return _earn


func is_claiming() -> bool:
	return _claim.disabled
