class_name CoinView
extends Node2D
## Draws the room's coin from sim state: pops in when it appears, bobs gently,
## and bursts into sparkles when collected. Looks only; the pickup itself is in
## sim/ (GameSim._check_coin).

const COIN_ICON := preload("res://assets/ui/coin.svg")
## Drawn a little larger than the 24px hitbox, like the spikes.
const DRAW_SIZE := 28.0
const BOB_PX := 3.0
const BOB_SPEED := 4.0
const POP_TIME := 0.2
const BURST_TIME := 0.35
const SPARKS := 8

var _run: RunController
var _time := 0.0
var _pop := 1.0
var _burst := 0.0
var _burst_at := Vector2.ZERO


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func bind(run: RunController) -> void:
	_run = run
	_pop = 1.0
	_burst = 0.0
	queue_redraw()


func on_spawned() -> void:
	_pop = 0.0


## Starts the sparkle burst where the coin was.
func on_collected(_total: int) -> void:
	_burst = 1.0
	var s := _run.sim.state
	_burst_at = Vector2(s.pickup_x, s.pickup_y) / float(SimConfig.SUB)


func _process(delta: float) -> void:
	if _run == null or _run.sim == null:
		return
	_time += delta
	_pop = minf(_pop + delta / POP_TIME, 1.0)
	_burst = maxf(_burst - delta / BURST_TIME, 0.0)
	queue_redraw()


func _coin_pos() -> Vector2:
	var s := _run.sim.state
	return Vector2(s.coin_x, s.coin_y) / float(SimConfig.SUB)


func _draw() -> void:
	if _run == null or _run.sim == null:
		return
	if _run.sim.state.coin_active:
		var p := _coin_pos() + Vector2(0, sin(_time * BOB_SPEED) * BOB_PX)
		var size := DRAW_SIZE * ease(_pop, -2.0)
		draw_texture_rect(
			COIN_ICON, Rect2(p - Vector2(size, size) / 2.0, Vector2(size, size)), false
		)
	if _burst > 0.0:
		var t := 1.0 - _burst
		var ring := Color(UiTokens.COIN, _burst * 0.8)
		draw_arc(_burst_at, 10.0 + t * 18.0, 0.0, TAU, 24, ring, 2.5, true)
		for i in SPARKS:
			var dir := Vector2.RIGHT.rotated(TAU * i / SPARKS)
			draw_circle(_burst_at + dir * (8.0 + t * 26.0), 2.5 * _burst, ring)
