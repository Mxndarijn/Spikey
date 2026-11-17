class_name GameModes
extends RefCounted
## The game modes Home offers (docs/DUEL_MODE.md, "The mode picker"): one entry
## per mode, drawn as a card in Home's mode carousel and as a tile in the All
## modes sheet. A new mode is one entry here plus its own flow; a mode that is
## not built yet shows as "Soon" and can't be played.

const CLASSIC := "classic"
const DAILY := "daily"
const BATTLE := "battle"
const DUEL := "duel"
## Shown on a mode that isn't built yet.
const SOON := "Soon"


## One mode: what its card and tile show.
class Mode:
	extends RefCounted
	var id: String
	var title: String
	## Its rules in one line, for the card and the tile.
	var rule: String
	var icon: Texture2D
	## The dock's main action while this mode is chosen.
	var play_label: String
	## False: shown as "Soon", its Play does nothing.
	var ready: bool

	func _init(
		p_id: String,
		p_title: String,
		p_rule: String,
		p_icon: Texture2D,
		p_play: String,
		p_ready: bool
	) -> void:
		id = p_id
		title = p_title
		rule = p_rule
		icon = p_icon
		play_label = p_play
		ready = p_ready


static var _all: Array[Mode] = []


## Every mode in carousel order; Classic is first and the default.
static func all() -> Array[Mode]:
	if _all.is_empty():
		_all = [
			Mode.new(
				CLASSIC,
				"Classic",
				"Endless. One life.",
				preload("res://assets/ui/icons/play.svg"),
				"Play",
				true
			),
			Mode.new(
				DAILY,
				"Daily Run",
				"One map a day · %d tries" % DailyRunRules.TRIES_PER_DAY,
				preload("res://assets/ui/icons/calendar.svg"),
				"Daily",
				true
			),
			Mode.new(
				BATTLE,
				"Battle",
				"Take turns on one map · first to 6",
				preload("res://assets/ui/icons/trophy.svg"),
				SOON,
				false
			),
			Mode.new(
				DUEL,
				"Duel",
				"Live 1v1 · best of 3",
				preload("res://assets/ui/icons/crown.svg"),
				SOON,
				false
			),
		]
	return _all


static func ids() -> Array[String]:
	var out: Array[String] = []
	for m in all():
		out.append(m.id)
	return out


## The mode with this id, or Classic for an unknown one (an old save).
static func find(id: String) -> Mode:
	for m in all():
		if m.id == id:
			return m
	return all()[0]


## The card's line under the name. The Daily Run's shows today's tries and
## the time to the next map once they are known.
static func rule_line(id: String, daily: DailyRunInfo = null) -> String:
	if id == DAILY and daily != null and daily.is_online():
		return daily_line(daily)
	return find(id).rule


## "2 tries left · 4h 12m", "#12 · 4h 12m" or "Done · 4h 12m".
static func daily_line(info: DailyRunInfo) -> String:
	var parts: Array[String] = []
	if info.tries_left() > 0:
		parts.append(DailyRunRules.tries_text(info.tries_used, info.tries_max))
	elif info.rank > 0:
		parts.append("#%d" % info.rank)
	else:
		parts.append("Done")
	if info.resets_in_s >= 0:
		parts.append(LeaderboardScreen.duration(info.resets_in_s))
	return " · ".join(parts)


## The small badge on the card's corner: "Soon" for a mode not built yet, the
## tries left for the Daily Run, else "".
static func badge(id: String, daily: DailyRunInfo = null) -> String:
	var m := find(id)
	if not m.ready:
		return SOON
	if id == DAILY and daily != null and daily.is_online() and daily.tries_left() > 0:
		return str(daily.tries_left())
	return ""
