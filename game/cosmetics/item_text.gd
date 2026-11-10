class_name ItemText
extends RefCounted
## The words about an item in Customize: the one-line detail in its popup and
## the short badge ("Premium", "Fits Jungle Canopy", "Matches Sunset Glow").


## What the item is, with the promise that it changes nothing in a run.
static func detail(kind: String, id: String) -> String:
	match kind:
		ItemKind.FLYER:
			var f := Catalog.flyer(id)
			if f == null:
				return ""
			return f.blurb + " Looks only, same hitbox."
		ItemKind.WORLD:
			return "A world to play in. Looks only: every world plays the same."
		ItemKind.TRAIL:
			var t := Catalog.trail(id)
			if t != null and t.use_world_color:
				return "Takes the color of the world you play in."
			return "A trail behind your flyer."
		ItemKind.PORTAL:
			var p := Catalog.portal(id)
			var blurb := p.blurb + " " if p != null and not p.blurb.is_empty() else ""
			return blurb + "Looks only: every exit is the same size."
		ItemKind.MUSIC:
			match id:
				MusicTrack.MATCH_WORLD:
					return "Plays the track that fits the world you pick."
				MusicTrack.SHUFFLE:
					return "Plays a random track you own, a new one each run."
			var t := Catalog.track(id)
			if t == null:
				return ""
			return "%s. Music only: every run plays the same." % ItemCard.track_line(id, null)
		ItemKind.CRASH:
			var c := Catalog.crash(id)
			var line := c.blurb + " " if c != null and not c.blurb.is_empty() else ""
			return line + "Looks only: it plays after the run has ended."
		ItemKind.PLATE:
			var plate := Catalog.plate(id)
			var line := plate.blurb + " " if plate != null and not plate.blurb.is_empty() else ""
			return line + "Shows behind your row on the leaderboards."
	return ""


## A short extra line: "Premium" or "Seasonal: October" for worlds, the worlds
## a flyer fits for flyers, the worlds a track matches for music. Empty when
## there is nothing.
static func badge(kind: String, id: String) -> String:
	match kind:
		ItemKind.WORLD:
			var w := Catalog.world(id)
			if w == null:
				return ""
			if not w.season.is_empty():
				return "Seasonal: %s" % w.season
			return "Premium" if w.premium else ""
		ItemKind.FLYER:
			var f := Catalog.flyer(id)
			if f == null or f.fits_worlds.is_empty():
				return ""
			return "Fits " + " and ".join(_world_names(f.fits_worlds))
		ItemKind.MUSIC:
			var t := Catalog.track(id)
			if t == null or t.worlds.is_empty():
				return ""
			var names := _world_names(t.worlds)
			var last: String = names[names.size() - 1]
			names.resize(names.size() - 1)
			if names.is_empty():
				return "Matches " + last
			return "Matches %s and %s" % [", ".join(names), last]
	return ""


static func _world_names(ids: PackedStringArray) -> Array[String]:
	var out: Array[String] = []
	for wid in ids:
		out.append(Catalog.display_name(ItemKind.WORLD, wid))
	return out
