class_name GameFonts
extends RefCounted
## The design kit's one font: Archivo, a variable font with a weight axis
## (wght 100 to 900) and a width axis (wdth 62 to 125), in assets/fonts/ under
## the SIL Open Font License (Archivo-OFL.txt next to it).
## display(): weight 900 at width 125, for the wordmark, titles and scores.
## ui(weight): normal width, for everything else (600 to 900).
## If the file is missing, the closest installed system font is used, so the
## game always has text.

const FILE := "res://assets/fonts/Archivo-Variable.ttf"
const LICENSE := "res://assets/fonts/Archivo-OFL.txt"
const FAMILY := "Archivo"
const DISPLAY_WEIGHT := 900
const DISPLAY_WIDTH := 125
const UI_WIDTH := 100
const FALLBACK: Array[String] = ["Archivo", "Segoe UI", "Roboto", "Helvetica Neue", "Arial"]

## "weight:width" -> Font
static var _cache := {}


## Drops the cached fonts (on exit, so Godot can free them).
static func release() -> void:
	_cache.clear()


static func display() -> Font:
	return wide(DISPLAY_WEIGHT, DISPLAY_WIDTH)


## UI font at a weight from the kit (600, 700, 800 or 900).
static func ui(weight: int = 700) -> Font:
	return wide(weight, UI_WIDTH)


## Archivo at any weight and width (the canvas uses 112 for button labels).
static func wide(weight: int, width: int) -> Font:
	var key := "%d:%d" % [weight, width]
	if not _cache.has(key):
		_cache[key] = _load(weight, width)
	return _cache[key]


static func _load(weight: int, width: int) -> Font:
	if not ResourceLoader.exists(FILE):
		var f := SystemFont.new()
		f.font_names = PackedStringArray(FALLBACK)
		f.font_weight = weight
		f.font_stretch = width
		return f
	var v := FontVariation.new()
	v.base_font = load(FILE)
	var ts := TextServerManager.get_primary_interface()
	v.variation_opentype = {ts.name_to_tag("wght"): weight, ts.name_to_tag("wdth"): width}
	return v
