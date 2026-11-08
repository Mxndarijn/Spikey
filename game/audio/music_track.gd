class_name MusicTrack
extends Resource
## A background music track: four stems of the same length (pad, bass, drums,
## lead) that play in sync. The game, not the player, turns stems on as a run
## builds (see AudioDirector). Players pick a track in Customize > Music.
## Cosmetic only. See docs/AUDIO.md.
##
## Adding a track: one entry in all() (stems in assets/audio/music/<id>/
## named <id>_<stem>.ogg, imported with loop on), its line in the catalog and
## a price in the shop.

## Special picks (not tracks): the track that fits the equipped world, or a
## random owned track each run.
const MATCH_WORLD := "match_world"
const SHUFFLE := "shuffle"
const DEFAULT_ID := "candy_hop"
## Stem order inside AudioStreamSynchronized.
const STEMS: Array[String] = ["pad", "bass", "drums", "lead"]
const PAD := 0
const BASS := 1
const DRUMS := 2
const LEAD := 3
const DIR := "res://assets/audio/music"

## Stable id, kept in saves: never rename a shipped one.
@export var id := DEFAULT_ID
@export var display_name := "Candy Hop"
## One line for the shop popup.
@export var blurb := ""
@export var bpm := 120
## World ids this track is the "Match my world" pick for.
@export var worlds: PackedStringArray = []


static func _make(
	p_id: String, p_name: String, p_bpm: int, p_worlds: PackedStringArray, p_blurb: String
) -> MusicTrack:
	var t := MusicTrack.new()
	t.id = p_id
	t.display_name = p_name
	t.bpm = p_bpm
	t.worlds = p_worlds
	t.blurb = p_blurb
	return t


static func all() -> Array[MusicTrack]:
	return [
		_make("candy_hop", "Candy Hop", 120, ["sugar", "blossom", "sunset"], "Bright and bouncy."),
		_make(
			"bubble_drift", "Bubble Drift", 92, ["deepsea", "ice", "winterfest"], "Calm and floaty."
		),
		_make(
			"jungle_bounce",
			"Jungle Bounce",
			104,
			["jungle", "autumn", "desert"],
			"Playful, with a swing."
		),
		_make("lava_rush", "Lava Rush", 140, ["lava", "haunted"], "Fast and tense."),
		_make("star_arcade", "Star Arcade", 128, ["star", "neon"], "Retro arcade beeps."),
	]


static func find(track_id: String) -> MusicTrack:
	for t in all():
		if t.id == track_id:
			return t
	return null


## The track for "Match my world"; the default when no track lists the world.
static func for_world(world_id: String) -> MusicTrack:
	for t in all():
		if world_id in t.worlds:
			return t
	return find(DEFAULT_ID)


func stem_path(stem: int) -> String:
	return "%s/%s/%s_%s.ogg" % [DIR, id, id, STEMS[stem]]


## The four stems in sync, ready to play. Each stem starts at full volume.
func build_stream() -> AudioStreamSynchronized:
	var s := AudioStreamSynchronized.new()
	s.stream_count = STEMS.size()
	for i in STEMS.size():
		var stem := load(stem_path(i)) as AudioStream
		if stem is AudioStreamOggVorbis:
			(stem as AudioStreamOggVorbis).loop = true
		s.set_sync_stream(i, stem)
		s.set_sync_stream_volume(i, 0.0)
	return s
