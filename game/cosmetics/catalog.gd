class_name Catalog
extends RefCounted
## Everything the player can pick or buy, by kind (ItemKind): what each id
## looks like. Read-only content: the Profile records what the player owns
## and uses, Shop what it costs.
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
static var _crashes: Array[CrashStyle] = []
static var _plates: Array[PlateStyle] = []


## Swaps equipped looks that no longer exist (a portal style, crash effect or
## name plate that was retired) for the default of their kind, so a save from
## an older build always shows something. Returns true if it changed any.
static func repair(profile: Profile) -> bool:
	var changed := false
	var lookups := {
		ItemKind.PORTAL: portal,
		ItemKind.CRASH: crash,
		ItemKind.PLATE: plate,
	}
	for kind: String in lookups:
		var find: Callable = lookups[kind]
		if find.call(profile.equipped_id(kind)) == null:
			profile.equipped[kind] = ItemKind.DEFAULTS[kind]
			changed = true
	return changed


static func release() -> void:
	_flyers.clear()
	_trails.clear()
	_portals.clear()
	_tracks.clear()
	_crashes.clear()
	_plates.clear()
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
		_trails.append_array(TrailStyle.flap_trails())
	return _trails


## Exit portal looks, in display order, Match my world first. A new style is
## one line in PortalStyle.STYLES.
static func portals() -> Array[PortalStyle]:
	if _portals.is_empty():
		_portals = PortalStyle.all()
	return _portals


## Music tracks, in display order (MusicTrack.all()).
static func tracks() -> Array[MusicTrack]:
	if _tracks.is_empty():
		_tracks = MusicTrack.all()
	return _tracks


## Crash effects, in display order, the free default first. A new style is one
## row in CrashStyle.STYLES.
static func crashes() -> Array[CrashStyle]:
	if _crashes.is_empty():
		_crashes = CrashStyle.all()
	return _crashes


## Name plates, in display order, Paper first. A new plate is one row in
## PlateStyle.STYLES.
static func plates() -> Array[PlateStyle]:
	if _plates.is_empty():
		_plates = PlateStyle.all()
	return _plates


## Ids of every item of a kind, in display order.
static func ids(kind: String) -> Array[String]:
	var out: Array[String] = []
	match kind:
		ItemKind.FLYER:
			for f in flyers():
				out.append(f.id)
		ItemKind.WORLD:
			for w in worlds():
				out.append(w.id)
		ItemKind.TRAIL:
			for t in trails():
				out.append(t.id)
		ItemKind.PORTAL:
			for p in portals():
				out.append(p.id)
		ItemKind.MUSIC:
			out.append_array(MUSIC_PICKS)
			for t in tracks():
				out.append(t.id)
		ItemKind.CRASH:
			for c in crashes():
				out.append(c.id)
		ItemKind.PLATE:
			for p in plates():
				out.append(p.id)
	return out


static func flyer(id: String) -> CharacterDef:
	for f in flyers():
		if f.id == id:
			return f
	return null


## The flyer's idle picture, or null for an id we don't know.
static func flyer_art(id: String) -> Texture2D:
	var f := flyer(id)
	return f.idle if f != null else null


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


static func crash(id: String) -> CrashStyle:
	for c in crashes():
		if c.id == id:
			return c
	return null


static func plate(id: String) -> PlateStyle:
	for p in plates():
		if p.id == id:
			return p
	return null


static func display_name(kind: String, id: String) -> String:
	match kind:
		ItemKind.CRASH:
			var c := crash(id)
			return c.display_name if c != null else id
		ItemKind.PLATE:
			var pl := plate(id)
			return pl.display_name if pl != null else id
		ItemKind.FLYER:
			var f := flyer(id)
			return f.display_name if f != null else id
		ItemKind.WORLD:
			var w := world(id)
			return w.display_name if w != null else id
		ItemKind.TRAIL:
			var t := trail(id)
			return t.display_name if t != null else id
		ItemKind.PORTAL:
			var p := portal(id)
			return p.display_name if p != null else id
		ItemKind.MUSIC:
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
