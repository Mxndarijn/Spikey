class_name RunStore
extends RefCounted
## Keeps the player's RunHistory in its own file on the phone (next to the
## save, never sent anywhere). Every change is written at once, crash-safe
## (SafeFile). A few KB per run: seed and tap ticks, not video.

signal changed

const PATH := "user://runs.json"

var history := RunHistory.new()
var _path := PATH


func _init(path: String = PATH) -> void:
	_path = path
	var data: Variant = SafeFile.read_json(_path)
	if data is Dictionary:
		history = RunHistory.from_dict(data as Dictionary)


## A real run just ended: keep it as the newest.
func add(record: RunRecord) -> RunRecord:
	history.add(record)
	_write()
	return record


## Saves (on) or removes from Saved (off). False when nothing changed: no
## such run, or Saved is full.
func set_saved(id: int, on: bool) -> bool:
	var ok := history.save_run(id) if on else history.unsave_run(id)
	if ok:
		_write()
	return ok


func _write() -> void:
	SafeFile.write_json(_path, history.to_dict())
	changed.emit()
