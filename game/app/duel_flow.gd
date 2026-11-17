class_name DuelFlow
extends RefCounted
## Duel from the app's side (docs/DUEL_MODE.md, section 3): the Duel screen,
## the socket (DuelLink), and each round's run. A round runs through the same
## path as a Battle round (BattleFlow.Round: the server's seed, no revive), with
## a live rival: the rival's taps arrive as they are made and their bird flies
## a little behind yours (RivalGhost.live_on). This phone sends its own taps
## with the tick it reached every 6 ticks; the server judges the round.

## How often the ticks go out: every 6 ticks, 100 ms.
const SEND_EVERY := 6
const COPIED := "Copied. Send it to your friend."

var link: DuelLink
var _battle: BattleFlow
var _menus: MenuLayer
var _hud: Hud
var _profile: Profile
var _rival := {}
var _wins := [0, 0]
## The round in play: its number and the run's controller once it started.
var _round := 0
var _seed := 0
var _season := Seasons.NONE
var _playing: BattleFlow.Round
var _run: RunController
var _ghost: RivalGhost
var _sent_tick := 0
var _sent_taps := 0
var _down := false
var _countdown_until_ms := 0
var _round_over := false


func _init(
	p_link: DuelLink, battle: BattleFlow, menus: MenuLayer, hud: Hud, profile: Profile
) -> void:
	link = p_link
	_battle = battle
	_menus = menus
	_hud = hud
	_profile = profile
	link.received.connect(on_message)
	link.closed.connect(_on_closed)
	link.ticked.connect(_on_ticked)


## The Duel screen, opening the socket.
func open() -> DuelScreen:
	var screen := DuelScreen.new()
	screen.closed.connect(leave_screen)
	screen.find_pressed.connect(
		func() -> void:
			link.send({"t": "queue"})
			screen.show_finding()
	)
	screen.invite_pressed.connect(func() -> void: link.send({"t": "invite"}))
	screen.join_pressed.connect(func(code: String) -> void: link.send({"t": "join", "code": code}))
	screen.cancel_pressed.connect(
		func() -> void:
			link.send({"t": "cancel"})
			screen.show_start()
	)
	screen.battle_pressed.connect(
		func() -> void:
			link.send({"t": "cancel"})
			_battle.open()
	)
	screen.rematch_pressed.connect(
		func() -> void:
			link.send({"t": "rematch"})
			screen.set_line("Asked %s for a rematch." % _rival_name())
	)
	screen.copy_pressed.connect(
		func(text: String) -> void:
			DisplayServer.clipboard_set(text)
			_hud.show_toast(COPIED)
	)
	_menus.show_screen(screen)
	if GameModes.needs_update(GameModes.DUEL):
		screen.show_update()
		return screen
	link.open(_profile.leaderboard_name, _profile.equipped_id(ItemKind.FLYER))
	return screen


## Back from the Duel screen: out of the queue, and out of a match.
func leave_screen() -> void:
	link.send({"t": "cancel"})
	if _round > 0 and not _over():
		link.send({"t": "leave"})
	link.close()
	_battle.home()


func _over() -> bool:
	return _round == -1


func _rival_name() -> String:
	return str(_rival.get("name", "Your rival"))


func _screen() -> DuelScreen:
	return _menus.current() as DuelScreen


func _show_screen() -> DuelScreen:
	var s := _screen()
	if s == null:
		s = open()
	return s


## Every message from the server.
func on_message(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"invite":
			var s := _screen()
			if s != null:
				s.show_invite(str(msg.get("code", "")))
		"matched":
			_rival = msg.get("rival", {}) if msg.get("rival") is Dictionary else {}
			_wins = [0, 0]
		"countdown":
			_on_countdown(msg)
		"resume":
			_on_countdown(msg, true)
		"rival":
			if _ghost != null:
				_ghost.feed(int(msg.get("tick", 0)), msg.get("taps", []) as Array)
		"rival_down":
			if _ghost != null:
				_ghost.set_down(int(msg.get("score", 0)))
			_hud.show_toast("%s is down at %d" % [_rival_name(), int(msg.get("score", 0))])
		"round_over":
			_on_round_over(msg)
		"match_over":
			_on_match_over(msg)
		"rival_gone":
			_hud.show_toast("%s lost the connection" % _rival_name())
		"rival_back":
			_hud.show_toast("%s is back" % _rival_name())
		"rematch_asked":
			var s := _screen()
			if s != null:
				s.set_line("%s wants a rematch. Tap Rematch to play." % _rival_name())
		"error":
			if str(msg.get("message", "")) == "update_required":
				GameModes.set_server_version(SimConfig.GAMEPLAY_VERSION + 1)
				var s := _screen()
				if s != null:
					s.show_update()
				return
			_hud.show_toast(str(msg.get("message", "")).capitalize())


func _wins_of(msg: Dictionary) -> void:
	var w: Variant = msg.get("wins")
	if w is Array and (w as Array).size() == 2:
		_wins = [int(w[0]), int(w[1])]


## A round's countdown: the seed arrives; the run starts when it ends.
func _on_countdown(msg: Dictionary, resumed: bool = false) -> void:
	_wins_of(msg)
	_round = int(msg.get("round", 1))
	_seed = int(msg.get("seed", 0))
	_season = int(msg.get("season", Seasons.NONE))
	_round_over = false
	var left_ms := int(msg.get("start_in_ms", 0)) if not resumed else -int(msg.get("elapsed_ms", 0))
	if resumed:
		# Back after a lost connection: the server goes on from its own copy.
		_hud.show_toast("Back in round %d" % _round)
		return
	_countdown_until_ms = Time.get_ticks_msec() + left_ms
	var s := _show_screen()
	s.show_countdown(_round, _rival_name(), _wins[0], _wins[1], ceili(left_ms / 1000.0))
	_count_down(left_ms)


func _count_down(left_ms: int) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var at := _round
	var left := left_ms
	while left > 0:
		var step := mini(left, 1000)
		await tree.create_timer(step / 1000.0).timeout
		if not _battle.alive():
			return
		left -= step
		if _round != at:
			return
		var s := _screen()
		if s != null and left > 0:
			s.show_countdown(_round, _rival_name(), _wins[0], _wins[1], ceili(left / 1000.0))
	start_round_run()


## The countdown ended: the round's run starts, the rival's bird with it.
func start_round_run() -> void:
	var character := Catalog.flyer(str(_rival.get("flyer", "")))
	if character == null:
		character = Catalog.flyers()[0]
	_ghost = RivalGhost.live_on(_seed, _season, character, _rival_name())
	_playing = BattleFlow.Round.new()
	_playing.seed_value = _seed
	_playing.season = _season
	_playing.number = _round
	_playing.ghost = _ghost
	_playing.finish = _on_run_finished
	_sent_tick = 0
	_sent_taps = 0
	_down = false
	_battle.start_external(_playing)
	_run = _battle.run_in_play()


func _on_ticked() -> void:
	if _playing == null or _run == null or _run.sim == null or _down:
		return
	var tick := _run.sim.state.tick
	if tick - _sent_tick < SEND_EVERY and not _run.sim.is_over():
		return
	_send_ticks(tick)


func _send_ticks(tick: int) -> void:
	var taps := _run.replay().taps
	var fresh: Array[int] = []
	for i in range(_sent_taps, taps.size()):
		fresh.append(taps[i])
	_sent_taps = taps.size()
	_sent_tick = tick
	link.send({"t": "ticks", "tick": tick, "taps": fresh})


## Your bird is down: the last ticks go out, and the rival may still fly.
func _on_run_finished(replay: Replay) -> void:
	if _run != null and _run.sim != null:
		_send_ticks(_run.sim.state.tick)
	_down = true
	if not _round_over:
		var tree := Engine.get_main_loop() as SceneTree
		await tree.create_timer(1.0).timeout
		if not _battle.alive():
			return
		if not _round_over and _down:
			_show_screen().show_waiting(replay.score, _rival_name())


func _on_round_over(msg: Dictionary) -> void:
	_round_over = true
	_wins_of(msg)
	var winner := str(msg.get("winner", ""))
	var text := "Round %d is a draw" % int(msg.get("round", 0))
	if winner == "me":
		text = "You win round %d" % int(msg.get("round", 0))
	elif winner == "them":
		text = "%s wins round %d" % [_rival_name(), int(msg.get("round", 0))]
	if _down or _playing == null:
		_end_run()
		_show_screen().show_between(
			text, int(msg.get("my_score", 0)), int(msg.get("their_score", 0)), _rival_name()
		)
	else:
		# Still flying: the round is decided; fly on until the next one starts.
		_hud.show_toast(text + ". Keep flying!")


func _on_match_over(msg: Dictionary) -> void:
	_wins_of(msg)
	_end_run()
	_round = -1
	_show_screen().show_result(
		str(msg.get("winner", "")),
		_wins[0],
		_wins[1],
		_rival_name(),
		str(msg.get("ended_by", "")) == "left"
	)


func _end_run() -> void:
	_playing = null
	_ghost = null
	_battle.end_external()


func _on_closed(why: String) -> void:
	var s := _screen()
	if (
		s != null
		and s.state in [DuelScreen.State.START, DuelScreen.State.FINDING, DuelScreen.State.INVITE]
	):
		s.set_line(why)
	elif _playing != null:
		_hud.show_toast(why)


func ghost() -> RivalGhost:
	return _ghost


func playing() -> BattleFlow.Round:
	return _playing


func wins() -> Array:
	return _wins
