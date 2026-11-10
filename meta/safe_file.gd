class_name SafeFile
extends RefCounted
## JSON files that survive a crash or a full disk mid-save: a write goes to
## `<path>.tmp` first and replaces the file only once it is complete, and the
## file it replaces stays as `<path>.bak`. Reading falls back to the backup
## when the file is missing or broken.

const TMP := ".tmp"
const BAK := ".bak"
## A broken file is moved aside under this suffix (never overwritten), so a
## player's progress can still be recovered by hand.
const BROKEN := ".broken"


## Writes `data` as JSON. Returns false (and leaves the old file alone) when
## the new one could not be written in full.
static func write_json(path: String, data: Variant) -> bool:
	var text := JSON.stringify(data, "  ")
	var tmp := path + TMP
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	# Read it back: a short write (full disk) must not replace a good file.
	if FileAccess.get_file_as_string(tmp) != text:
		DirAccess.remove_absolute(tmp)
		return false
	if FileAccess.file_exists(path) and _parse(path) != null:
		DirAccess.copy_absolute(path, path + BAK)
	return DirAccess.rename_absolute(tmp, path) == OK


## The parsed file, else its backup; null when neither exists or parses. A
## file that exists but doesn't parse is moved aside to `<path>.broken`.
static func read_json(path: String) -> Variant:
	if FileAccess.file_exists(path):
		var data: Variant = _parse(path)
		if data != null:
			return data
		DirAccess.rename_absolute(path, path + BROKEN)
	if FileAccess.file_exists(path + BAK):
		return _parse(path + BAK)
	return null


## True when there is something to load (the file or its backup).
static func exists(path: String) -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + BAK)


## Removes the file and everything this class keeps next to it.
static func remove(path: String) -> void:
	for p in [path, path + TMP, path + BAK, path + BROKEN]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


static func _parse(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data
