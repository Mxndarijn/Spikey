class_name GameModes
extends RefCounted
## The game modes Home offers (docs/DUEL_MODE.md, "The mode picker"): one entry
## per mode, drawn as a tab in Home's mode tabs (ModeTabs). A new mode is one
## entry here plus its own flow; a mode that is not built yet shows as "Soon"
## and can't be played.

const CLASSIC := "classic"
const DAILY := "daily"
const BATTLE := "battle"
const DUEL := "duel"
## Shown on a mode that isn't built yet.
const SOON := "Soon"
## Battle and Duel run only on the newest gameplay version (the server's).
const UPDATE := "Update"
const UPDATE_LINE := "Update to play"
## The modes that need this phone on the server's gameplay version.
const LATEST_ONLY: Array[String] = [BATTLE, DUEL]
## Battle is paused (the user, 2026-11-17): hidden everywhere in the app (its
## Home tab, the Battles screens, battle pushes and links, the Wins boards'
## Battle tab, the Duel's "a Battle instead", its permission prompt). Its code
## and the server's tables stay; tests that need it turn battle_enabled on.
const BATTLE_ENABLED := false


## One mode: what its tab shows.
class Mode:
	extends RefCounted
	var id: String
	var title: String
	## Its name on the tab (short: four tabs share the bar).
	var tab_title: String
	## Its rules in one line, under the tabs while it is chosen.
	var rule: String
	var icon: Texture2D
	## The dock's main action while this mode is chosen.
	var play_label: String
	## False: shown as "Soon", its Play does nothing.
	var ready: bool

	func _init(
		p_id: String,
		p_title: String,
		p_tab: String,
		p_rule: String,
		p_icon: Texture2D,
		p_play: String,
		p_ready: bool
	) -> void:
		id = p_id
		title = p_title
		tab_title = p_tab
		rule = p_rule
		icon = p_icon
		play_label = p_play
		ready = p_ready


static var _all: Array[Mode] = []
## BATTLE_ENABLED, switchable for tests (tests/run_tests.gd resets it per test).
static var battle_enabled := BATTLE_ENABLED
## The server's gameplay version (0: not known yet), from its ping.
static var server_version := 0
## Counts changes of server_version, so Home redraws its tabs once.
static var changes := 0


## Every mode in tab order (Battle only while enabled); Classic is first and
## the default.
static func all() -> Array[Mode]:
	var out: Array[Mode] = []
	for m in _every():
		if m.id != BATTLE or battle_enabled:
			out.append(m)
	return out


static func _every() -> Array[Mode]:
	if _all.is_empty():
		_all = [
			Mode.new(
				CLASSIC,
				"Classic",
				"Classic",
				"Endless. One life.",
				preload("res://assets/ui/icons/play.svg"),
				"Play",
				true
			),
			Mode.new(
				DAILY,
				"Daily Run",
				"Daily",
				"One map a day · %d tries" % DailyRunRules.TRIES_PER_DAY,
				preload("res://assets/ui/icons/calendar.svg"),
				"Daily",
				true
			),
			Mode.new(
				BATTLE,
				"Battle",
				"Battle",
				"Take turns on one map · First to 6",
				preload("res://assets/ui/icons/battle.svg"),
				"Battles",
				true
			),
			Mode.new(
				DUEL,
				"Duel",
				"Duel",
				"Live 1v1 · Best of 3",
				preload("res://assets/ui/icons/crown.svg"),
				"Duel",
				true
			),
		]
	return _all


static func ids() -> Array[String]:
	var out: Array[String] = []
	for m in all():
		out.append(m.id)
	return out


## The server said its gameplay version (or that this phone is too old).
static func set_server_version(v: int) -> void:
	if v != server_version:
		server_version = v
		changes += 1


## This mode needs a newer app: Battle and Duel on an older gameplay version
## than the server's. Classic and the Daily Run go on working.
static func needs_update(id: String) -> bool:
	return id in LATEST_ONLY and server_version > SimConfig.GAMEPLAY_VERSION


## The dock's main action for this mode now.
static func play_label(id: String) -> String:
	return UPDATE if needs_update(id) else find(id).play_label


## The mode with this id, or Classic for an unknown one (an old save).
static func find(id: String) -> Mode:
	for m in all():
		if m.id == id:
			return m
	return all()[0]


## The line under the tabs. The Daily Run's shows today's tries and
## the time to the next map once they are known.
static func rule_line(id: String, daily: DailyRunInfo = null) -> String:
	if needs_update(id):
		return UPDATE_LINE
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


## The small badge on the tab's corner: "Soon" for a mode not built yet, the
## tries left for the Daily Run, else "".
static func badge(id: String, daily: DailyRunInfo = null) -> String:
	var m := find(id)
	if not m.ready:
		return SOON
	if needs_update(id):
		return UPDATE.to_upper()
	if id == DAILY and daily != null and daily.is_online() and daily.tries_left() > 0:
		return str(daily.tries_left())
	return ""
