class_name RunLook
extends RefCounted
## How the live room looks: the flyer, world, trail, crash effect, portal and
## music in use. Normally the player's own (from the save); during a replay
## the recorded player's, borrowed until the replay ends. Looks only: nothing
## here touches the run.

var theme: ThemeDef
var character: CharacterDef
var trail_style: TrailStyle
var crash_style: CrashStyle
## On while a replay's look replaces the player's.
var borrowed := false

var _profile: Profile
var _room: RoomView
var _hazards: HazardLayer
var _trail: TrailView
var _bird: BirdView
var _crash: CrashView
var _menus: MenuLayer
var _hud: Hud
var _audio: AudioDirector


func _init(
	profile: Profile,
	room: RoomView,
	hazards: HazardLayer,
	trail: TrailView,
	bird: BirdView,
	crash: CrashView,
	menus: MenuLayer,
	hud: Hud,
	audio: AudioDirector
) -> void:
	_profile = profile
	_room = room
	_hazards = hazards
	_trail = trail
	_bird = bird
	_crash = crash
	_menus = menus
	_hud = hud
	_audio = audio


## The player's own flyer, world, trail, crash effect, portal and music, with
## safe defaults for ids we don't know.
func use_equipped() -> void:
	borrowed = false
	character = Catalog.flyer(_profile.equipped_id(ItemKind.FLYER))
	if character == null:
		character = Catalog.flyers()[0]
	trail_style = Catalog.trail(_profile.equipped_id(ItemKind.TRAIL))
	if trail_style == null:
		trail_style = TrailStyle.world_ribbon()
	crash_style = CrashStyle.equipped(_profile)
	var world := Catalog.world(_profile.equipped_id(ItemKind.WORLD))
	set_world(world if world != null else ThemeCatalog.default_theme())
	_bird.set_character(character)
	_room.portal_style = PortalStyle.equipped(_profile)
	choose_music()


## A recorded player's look (a replay's loadout), for this replay only:
## nothing is saved or equipped. Ids we don't know keep the player's own.
func borrow(look: Dictionary) -> void:
	borrowed = true
	var flyer := Catalog.flyer(str(look.get(ItemKind.FLYER, "")))
	if flyer != null:
		character = flyer
	var trail := Catalog.trail(str(look.get(ItemKind.TRAIL, "")))
	if trail != null:
		trail_style = trail
	var crash := Catalog.crash(str(look.get(ItemKind.CRASH, "")))
	if crash != null:
		crash_style = crash
	var world := Catalog.world(str(look.get(ItemKind.WORLD, "")))
	if world != null:
		set_world(world)
	_bird.set_character(character)
	var portal := Catalog.portal(str(look.get(ItemKind.PORTAL, "")))
	_room.portal_style = portal if portal != null else PortalStyle.equipped(_profile)
	var music := str(look.get(ItemKind.MUSIC, ""))
	if Catalog.track(music) == null and not music in Catalog.MUSIC_PICKS:
		music = ""
	choose_music(music)


## The world the room, its hazards, the trail and the text on the room use.
func set_world(t: ThemeDef) -> void:
	theme = t
	# Night rooms get white text on the room; cards stay ink.
	var text := UiTheme.room_theme(t)
	_menus.set_room_theme(text)
	_room.set_theme(t)
	_hazards.set_theme(t)
	_trail.set_style(trail_style, t)
	_hud.set_room_theme(text)


## Shows world `id` in the room behind a Customize list without saving it;
## the world in use comes back with show_own_world().
func preview_world(id: String) -> void:
	var t := Catalog.world(id)
	if t != null:
		_room.set_theme(t)
		_hazards.set_theme(t)


func show_own_world() -> void:
	_room.set_theme(theme)
	_hazards.set_theme(theme)


## The live flyer, its trail and crash; screens that draw the flyer big
## themselves hide them.
func show_flyer(value: bool) -> void:
	_bird.visible = value
	_trail.visible = value
	_crash.visible = value


## Music: `pick` (a track id, Match my world or Shuffle owned), else the
## player's own pick. Shuffle draws from the player's own tracks.
func choose_music(pick: String = "") -> void:
	if pick.is_empty():
		pick = _profile.equipped_id(ItemKind.MUSIC)
	if pick.is_empty():
		pick = MusicTrack.MATCH_WORLD
	var owned := PackedStringArray(_profile.owned.get(ItemKind.MUSIC, []))
	_audio.choose_track(pick, theme.id, owned)


## The crash effect in use, where the flyer is drawn; its pieces fly away from
## the wall the flyer was heading for. The run is already over.
func play_crash(sim: GameSim) -> void:
	if crash_style == null or sim == null:
		return
	var away := -1.0 if sim.state.vx > 0 else 1.0
	var palette := PackedColorArray()
	if crash_style.piece == CrashStyle.SHARD and character != null:
		palette = CrashPainter.flyer_palette(character.idle)
	_crash.play(crash_style, _bird.position, away, palette)
	if crash_style.hides_flyer:
		_bird.fade_out()
