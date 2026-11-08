class_name Catalog
extends RefCounted
## Everything the player can pick or buy, by kind. Read-only content:
## the Profile records what the player owns and uses.

const FLYER := "flyer"
const WORLD := "world"
const TRAIL := "trail"
const PORTAL := "portal"
const MUSIC := "music"
const KINDS: Array[String] = [FLYER, WORLD, TRAIL, PORTAL, MUSIC]
## Music picks that are not tracks: always owned, free, listed first.
const MUSIC_PICKS: Array[String] = [MusicTrack.MATCH_WORLD, MusicTrack.SHUFFLE]
const MUSIC_PICK_NAMES := {
	MusicTrack.MATCH_WORLD: "Match my world", MusicTrack.SHUFFLE: "Shuffle owned"
}
const FLYER_DIR := "res://data/flyers"

static var _flyers: Array[CharacterDef] = []
static var _trails: Array[TrailStyle] = []
static var _portals: Array[PortalStyle] = []
static var _tracks: Array[MusicTrack] = []


static func release() -> void:
	_flyers.clear()
	_trails.clear()
	_portals.clear()
	_tracks.clear()
	ThemeCatalog.release()


static func flyers() -> Array[CharacterDef]:
	if _flyers.is_empty():
		for res in load_dir(FLYER_DIR):
			if res is CharacterDef:
				_flyers.append(res)
		_flyers.sort_custom(
			func(a: CharacterDef, b: CharacterDef) -> bool: return a.order < b.order
		)
	return _flyers


static func worlds() -> Array[ThemeDef]:
	return ThemeCatalog.all()


static func trails() -> Array[TrailStyle]:
	if _trails.is_empty():
		_trails = [
			TrailStyle.world_ribbon(),
			TrailStyle.spark_dots(),
			TrailStyle.bubble_stream(),
			TrailStyle.rainbow_ribbon(),
			TrailStyle.leaf_swirl(),
			TrailStyle.pixel_trail(),
			TrailStyle.confetti(),
			TrailStyle.comet_tail(),
			TrailStyle.star_dust(),
			TrailStyle.music_notes(),
		]
	return _trails


## Exit portal looks, in display order. A new style is one line here (see
## PortalStyle).
static func portals() -> Array[PortalStyle]:
	if _portals.is_empty():
		_portals = [
			PortalStyle.cloud_hole(),
			PortalStyle.ink_splat(),
			PortalStyle.feather_ring(),
			PortalStyle.breakout_crack(),
			PortalStyle.ripple_mirror(),
		]
	return _portals


## Music tracks, in display order (MusicTrack.all()).
static func tracks() -> Array[MusicTrack]:
	if _tracks.is_empty():
		_tracks = MusicTrack.all()
	return _tracks


## Ids of every item of a kind, in display order.
static func ids(kind: String) -> Array[String]:
	var out: Array[String] = []
	match kind:
		FLYER:
			for f in flyers():
				out.append(f.id)
		WORLD:
			for w in worlds():
				out.append(w.id)
		TRAIL:
			for t in trails():
				out.append(t.id)
		PORTAL:
			for p in portals():
				out.append(p.id)
		MUSIC:
			out.append_array(MUSIC_PICKS)
			for t in tracks():
				out.append(t.id)
	return out


static func flyer(id: String) -> CharacterDef:
	for f in flyers():
		if f.id == id:
			return f
	return null


static func world(id: String) -> ThemeDef:
	return ThemeCatalog.find(id)


static func trail(id: String) -> TrailStyle:
	for t in trails():
		if t.id == id:
			return t
	return null


static func portal(id: String) -> PortalStyle:
	for p in portals():
		if p.id == id:
			return p
	return null


## A music track; null for the picks (Match my world, Shuffle owned).
static func track(id: String) -> MusicTrack:
	for t in tracks():
		if t.id == id:
			return t
	return null


static func display_name(kind: String, id: String) -> String:
	match kind:
		FLYER:
			var f := flyer(id)
			return f.display_name if f != null else id
		WORLD:
			var w := world(id)
			return w.display_name if w != null else id
		TRAIL:
			var t := trail(id)
			return t.display_name if t != null else id
		PORTAL:
			var p := portal(id)
			return p.display_name if p != null else id
		MUSIC:
			if MUSIC_PICK_NAMES.has(id):
				return MUSIC_PICK_NAMES[id]
			var m := track(id)
			return m.display_name if m != null else id
	return id


## Loads every .tres in a folder (handles exported ".remap" names).
static func load_dir(dir: String) -> Array[Resource]:
	var out: Array[Resource] = []
	for file in DirAccess.get_files_at(dir):
		var file_name := file.trim_suffix(".remap")
		if file_name.ends_with(".tres"):
			var res := load(dir.path_join(file_name))
			if res != null:
				out.append(res)
	return out
