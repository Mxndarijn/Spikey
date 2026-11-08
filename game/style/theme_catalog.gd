class_name ThemeCatalog
extends RefCounted
## All worlds the player can pick, loaded from data/themes/.

const DIR := "res://data/themes"
const DEFAULT_ID := "sunset"

static var _themes: Array[ThemeDef] = []


static func release() -> void:
	_themes.clear()


static func all() -> Array[ThemeDef]:
	if _themes.is_empty():
		_load()
	return _themes


static func find(id: String) -> ThemeDef:
	for t in all():
		if t.id == id:
			return t
	return null


static func default_theme() -> ThemeDef:
	var t := find(DEFAULT_ID)
	return t if t != null else all()[0]


## The next world in picker order, wrapping around.
static func next(current: ThemeDef) -> ThemeDef:
	var list := all()
	var i := list.find(current)
	return list[(i + 1) % list.size()]


static func _load() -> void:
	for file in DirAccess.get_files_at(DIR):
		# Exported builds list "x.tres.remap" instead of "x.tres".
		var file_name := file.trim_suffix(".remap")
		if not file_name.ends_with(".tres"):
			continue
		var t := load(DIR.path_join(file_name)) as ThemeDef
		if t != null:
			_themes.append(t)
	_themes.sort_custom(func(a: ThemeDef, b: ThemeDef) -> bool: return a.order < b.order)
