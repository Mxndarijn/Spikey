class_name GameOverStage
extends Node
## Game over empties the room so its text never sits on a hazard: the hazards,
## coins, trail, crash effect, Midnight Cage's dark and the room's own drawing
## (cage spikes, exits, motes) fade out over FADE_TIME, while the world's sky,
## landscape and frame stay (RoomView's backdrop). The flyer floats off the
## wall to the middle, big and dazed (BirdView.showcase); on a new best it bobs.
## Cosmetic only: it changes how views draw, never sim state. A new run
## (reset) brings everything back.

const FADE_TIME := 0.3
const FLY_TIME := 0.45
## Where the flyer settles, logical px: in the gap between Best and the stats
## on the Game over screen (GameOverScreen.FLYER_Y).
const SPOT := Vector2(UiTokens.SIZE_VIEWPORT_W / 2.0, GameOverScreen.FLYER_Y)

var _room: RoomView
var _bird: BirdView
var _faded: Array[CanvasItem] = []
var _tween: Tween
var _empty := false


## `faded`: the views that fade out whole (hazards, coins, trail, crash, night).
func setup(room: RoomView, bird: BirdView, faded: Array[CanvasItem]) -> void:
	_room = room
	_bird = bird
	_faded = faded


## Empties the room and shows the flyer. `still`: reduced motion, no fades.
func show_empty(new_best: bool, still: bool) -> void:
	_kill_tween()
	_empty = true
	_bird.showcase(SPOT, not new_best, still, 0.0 if still else FLY_TIME)
	if still:
		_set_alpha(0.0)
		return
	_tween = create_tween().set_parallel()
	_tween.tween_property(_room, "self_modulate:a", 0.0, FADE_TIME)
	for item in _faded:
		_tween.tween_property(item, "modulate:a", 0.0, FADE_TIME)


## Back to the full room at once (a new run starts).
func reset() -> void:
	_kill_tween()
	_empty = false
	_set_alpha(1.0)


func is_empty() -> bool:
	return _empty


func _set_alpha(a: float) -> void:
	_room.self_modulate.a = a
	for item in _faded:
		item.modulate.a = a


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
