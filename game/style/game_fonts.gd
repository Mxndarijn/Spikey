class_name GameFonts
extends RefCounted
## The design kit's fonts: Baloo 2 (display: scores, numbers, titles, at 800)
## and Nunito (UI, 600 to 800). Both are variable fonts in assets/fonts/ under
## the SIL Open Font License (license files next to them). If a file is missing,
## the closest installed system font is used, so the game always has text.

const DISPLAY_FILE := "res://assets/fonts/Baloo2-Variable.ttf"
const UI_FILE := "res://assets/fonts/Nunito-Variable.ttf"
const DISPLAY_WEIGHT := 800
const DISPLAY_FALLBACK: Array[String] = ["Baloo 2", "Arial Rounded MT Bold", "Segoe UI Black"]
const UI_FALLBACK: Array[String] = ["Nunito", "Segoe UI", "Roboto", "Helvetica Neue"]

static var _display: Font
static var _ui := {}


## Drops the cached fonts (on exit, so Godot can free them).
static func release() -> void:
	_display = null
	_ui.clear()


static func display() -> Font:
	if _display == null:
		_display = _load(DISPLAY_FILE, DISPLAY_FALLBACK, DISPLAY_WEIGHT)
	return _display


## UI font at a weight from the kit (600, 700 or 800).
static func ui(weight: int = 700) -> Font:
	if not _ui.has(weight):
		_ui[weight] = _load(UI_FILE, UI_FALLBACK, weight)
	return _ui[weight]


static func _load(path: String, fallback: Array[String], weight: int) -> Font:
	if not ResourceLoader.exists(path):
		var f := SystemFont.new()
		f.font_names = PackedStringArray(fallback)
		f.font_weight = weight
		return f
	var v := FontVariation.new()
	v.base_font = load(path)
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	v.variation_opentype = {wght: weight}
	return v
