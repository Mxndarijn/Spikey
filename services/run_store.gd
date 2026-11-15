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


## Your runs become these (oldest first): the runs of a player who just moved
## to this phone.
func replace(records: Array[RunRecord]) -> void:
	history = RunHistory.new()
	for r in records:
		history.add(r)
	_write()


## Forgets every run (the player moved to another phone).
func clear() -> void:
	history = RunHistory.new()
	_write()


func _write() -> void:
	SafeFile.write_json(_path, history.to_dict())
	changed.emit()
