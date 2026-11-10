class_name MusicPreview
extends RefCounted
## Previewing tracks in Customize: plays one, and puts the track from before
## back when the preview stops. Without an AudioDirector (tests) only the
## state changes.

## The music id playing ("" for none).
var playing := ""

var _audio: AudioDirector
var _resting: MusicTrack


func _init(audio: AudioDirector) -> void:
	_audio = audio


## Plays `id` (Match my world plays the track for `world_id`), or stops it
## when it is already playing.
func toggle(id: String, world_id: String) -> void:
	if playing == id:
		stop()
		return
	var t := track_for(id, world_id)
	if t == null:
		return
	var director := _director()
	if playing.is_empty():
		_resting = director.track if director != null else null
	playing = id
	if director != null:
		director.play_track(t)


## Stops a preview and plays the track from before it again.
func stop() -> void:
	if playing.is_empty():
		return
	playing = ""
	var director := _director()
	if director != null and _resting != null:
		director.play_track(_resting)
	_resting = null


## A new pick was put to use: main plays it, so nothing to go back to.
func hand_over() -> void:
	playing = ""
	_resting = null


## The track a music card previews: itself, or the world's for Match my world.
static func track_for(id: String, world_id: String) -> MusicTrack:
	if id == MusicTrack.MATCH_WORLD:
		return MusicTrack.for_world(world_id)
	return Catalog.track(id)


## The live AudioDirector, or null (tests, or one already freed).
func _director() -> AudioDirector:
	if not is_instance_valid(_audio) or not _audio.is_inside_tree():
		return null
	return _audio
