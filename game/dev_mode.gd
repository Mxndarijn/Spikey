class_name DevMode
extends RefCounted
## Developer mode: on when the game runs from the Godot editor (F5) or as a
## debug build, never in a release export. It opens every room for practice,
## seasonal ones too. Practice never changes the save, so this is safe.

## Tests set this to force developer mode on (1) or off (0); -1 = automatic.
static var override := -1


static func enabled() -> bool:
	if override >= 0:
		return override == 1
	return OS.has_feature("editor") or OS.is_debug_build()
