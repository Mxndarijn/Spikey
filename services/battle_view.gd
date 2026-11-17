class_name BattleView
extends RefCounted
## One battle as the server shows it to this player (battle_get, battle_list:
## backend/migrations/0110_battles.sql, spikey_battle_view). Anything missing
## or of the wrong type reads as empty.

const WAITING := "waiting"
const OPEN := "open"
const FINISHED := "finished"
const CLOSED := "closed"

var id := 0
var status := ""
var first_to := MatchRules.FIRST_TO
var random := false
## This player started the battle (opens the odd rounds).
var starter := false
var wins_me := 0
var wins_them := 0
## "me", "them" or "" (nobody's: waiting for an opponent, or over).
var turn := ""
var rival_name := ""
var rival_flyer := ""
var rival_bot := false
var last_move_s := 0
var ended_by := ""
## "me", "them", "draw" or "" (not over).
var winner := ""
var can_close := false
var can_nudge := false
## [{number, blind, mine_first, my_score, their_score, winner}], oldest first.
var rounds: Array[Dictionary] = []
## The round this player plays next (0: none) and how: "open" or "answer".
var play_round := 0
var play_role := ""
var play_blind := false
## The rival's checked run of the round to answer ({} for none: blind, or not
## checked yet): score, coins, taps, seed, season, loadout.
var rival: Dictionary = {}
var rival_pending := false
## An invite battle's code (only in battle_create's answer).
var code := ""
## battle_start_run said the run started before was lost, or the round was dealt again.
var lost := false
var redealt := false


static func parse(data: Variant) -> BattleView:
	var v := BattleView.new()
	if not data is Dictionary:
		return v
	var d := data as Dictionary
	v.id = int(d.get("battle", 0))
	v.status = str(d.get("status", ""))
	v.first_to = int(d.get("first_to", MatchRules.FIRST_TO))
	v.random = bool(d.get("random", false))
	v.starter = bool(d.get("starter", false))
	v.wins_me = int(d.get("wins_me", 0))
	v.wins_them = int(d.get("wins_them", 0))
	v.turn = _text(d.get("turn"))
	var opp: Variant = d.get("opponent")
	if opp is Dictionary:
		v.rival_name = _text((opp as Dictionary).get("name"))
		v.rival_flyer = _text((opp as Dictionary).get("flyer"))
		v.rival_bot = bool((opp as Dictionary).get("bot", false))
	v.last_move_s = int(d.get("last_move_s", 0))
	v.ended_by = _text(d.get("ended_by"))
	v.winner = _text(d.get("winner"))
	v.can_close = bool(d.get("can_close", false))
	v.can_nudge = bool(d.get("can_nudge", false))
	var list: Variant = d.get("rounds", [])
	if list is Array:
		for r: Variant in list:
			if r is Dictionary:
				v.rounds.append(r as Dictionary)
	var play: Variant = d.get("play")
	if play is Dictionary:
		var p := play as Dictionary
		v.play_round = int(p.get("round", 0))
		v.play_role = _text(p.get("role"))
		v.play_blind = bool(p.get("blind", false))
		v.rival_pending = bool(p.get("rival_pending", false))
		if p.get("rival") is Dictionary:
			v.rival = p.get("rival") as Dictionary
	v.code = _text(d.get("code"))
	v.lost = bool(d.get("lost", false))
	v.redealt = bool(d.get("redealt", false))
	return v


static func _text(value: Variant) -> String:
	return value as String if value is String else ""


func is_over() -> bool:
	return status == FINISHED or status == CLOSED


func my_turn() -> bool:
	return turn == "me" and play_round > 0


## The rival as shown: their name, or "Waiting for a rival" before anyone joined.
func rival_label() -> String:
	return rival_name if not rival_name.is_empty() else "Waiting for a rival"


## The rival's score in the round to answer, -1 when it isn't shown.
func rival_score() -> int:
	return int(rival.get("score", -1)) if not rival.is_empty() else -1


## One line for the battle list: what happens next.
func status_line() -> String:
	if status == CLOSED:
		return "Closed, no result"
	if status == FINISHED:
		return _result_line()
	if status == WAITING:
		return "Waiting for a rival"
	if my_turn():
		return _turn_line()
	return "Waiting for %s · %s" % [rival_label(), MatchRules.since_text(last_move_s)]


func _result_line() -> String:
	var how := " (resigned)" if ended_by == "resigned" else ""
	if winner == "me":
		return "You won %d-%d%s" % [wins_me, wins_them, how]
	if winner == "them":
		return "%s won %d-%d%s" % [rival_label(), wins_them, wins_me, how]
	return "Draw %d-%d" % [wins_me, wins_them]


func _turn_line() -> String:
	if play_role == "answer" and rival_score() >= 0:
		return "Round %d · %s scored %d" % [play_round, rival_name, rival_score()]
	if play_role == "answer" and play_blind:
		return "Round %d · %s has played" % [play_round, rival_name]
	return "Round %d · you go first" % play_round
