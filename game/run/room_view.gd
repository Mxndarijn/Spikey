class_name RoomView
extends Node2D
## Draws the room from the chosen world (ThemeDef) in the flat "Worlds v4"
## style: the sky and the world's layered landscape (game/run/scenes/), its
## falling leaves, snow, petals or embers below the score, the ghost score, and
## two-tone rounded spikes from sim state. Cosmetic only; hitboxes live in sim/.

const W := float(UiTokens.SIZE_VIEWPORT_W)
const H := float(UiTokens.SIZE_VIEWPORT_H)
const BAND := 8.0
## Phones taller or wider than 360 x 640 show space around the room
## (ScreenLayout). The ceiling, floor and walls carry on into it in the band
## colour, this far out (more than any phone needs).
const SURROUND := 2048.0
const SPIKE_DEPTH := float(UiTokens.SIZE_SPIKE_DEPTH)
const SPIKE_HALF := UiTokens.SIZE_SPIKE_BASE / 2.0
## Ceiling and floor: one unbroken row of 9 wide spikes. Band + depth reach the
## sim's kill lines (SimConfig.KILL_TOP = 34 px), so all of it looks deadly.
const EDGE_SPIKE_DEPTH := 26.0
const EDGE_SPIKE_HALF := 20.0
## The rounded tip: the sides end TIP_HALF px either side of the centre line,
## TIP_BACK px short of the tip, and curve round it.
const TIP_HALF := 3.0
const TIP_BACK := 2.0
## Color-blind spikes: ink body, a lighter ink half and a white edge.
const INK_SPIKE := UiTokens.INK_900
const INK_SPIKE_EDGE := Color(0.32, 0.29, 0.35, 1.0)
const INK_SPIKE_LINE := Color("#FFFFFF")
const INK_SPIKE_LINE_W := 2.0
## Wall spikes slide in over about 125 ms; the sky fades over 400 ms.
const SLIDE_SPEED := 8.0
const FADE_SPEED := 2.5
const FLASH_ALPHA := 0.35
## Exit portals: half-width (where the Calm/Wild tag goes), how far the centre
## sits from the wall (px), open time (s), tag coin size.
const EXIT_RX := 22.0
const EXIT_DEPTH := 6.0
const EXIT_FADE_TIME := 0.5
## The ghost of the next exit (shown one point early): fade-in time, how open
## and how faint it is, its slow pulse, and its dashed "not open yet" rim.
const GHOST_FADE_TIME := 0.3
const GHOST_OPEN := 0.8
const GHOST_ALPHA := 0.3
const GHOST_PULSE_ALPHA := 0.15
const GHOST_PULSE_TIME := 1.2
const GHOST_SPIN := 0.3
const GHOST_RIM_ALPHA := 0.85
const GHOST_RIM_W := 2.0
const GHOST_RIM_DASHES := 14
const EXIT_TAG_ICON := 16.0
const EXIT_TAG_DOT := 10.0
## How long the portal the bird came out of takes to close, seconds.
const ARRIVAL_CLOSE_TIME := 0.7
const COIN_ICON := preload("res://assets/ui/coin.svg")
## Midnight Cage tints the room night blue (WorldScenes.midnight_dim per world).
## Blink Walls: alpha of the outlines that show the next pattern.
const BLINK_OUTLINE_ALPHA := 0.6
## Falling things never enter the score area: they start below this line.
const MOTE_TOP := 196.0
## Falling things per world (design canvas "Worlds v4"): worlds not listed have
## a calm sky with none.
const MOTE_KIND := {
	"ice": "snow",
	"winterfest": "snow",
	"lava": "embers",
	"sugar": "sprinkles",
	"autumn": "leaves",
	"blossom": "petals",
	"deepsea": "bubbles",
	"aurora": "snow",
}
## Per world: how many, and the band they move in (top, bottom), px.
const MOTE_COUNT := {
	"ice": 12,
	"winterfest": 28,
	"lava": 14,
	"sugar": 16,
	"autumn": 12,
	"blossom": 12,
	"deepsea": 6,
	"aurora": 14,
}
const MOTE_BAND := {
	"ice": Vector2(200, 470),
	"winterfest": Vector2(196, 520),
	"lava": Vector2(200, 500),
	"sugar": Vector2(196, 450),
	"autumn": Vector2(196, 470),
	"blossom": Vector2(260, 520),
	"deepsea": Vector2(300, 540),
	"aurora": Vector2(330, 540),
}
## Per kind: drift speed in px/s (x, y) and sideways wobble in px.
const MOTE_MOTION := {
	"snow": [Vector2(-3, 18), 8.0],
	"embers": [Vector2(2, -40), 4.0],
	"sprinkles": [Vector2(3, 24), 3.0],
	"leaves": [Vector2(-10, 18), 14.0],
	"petals": [Vector2(8, 12), 12.0],
	"bubbles": [Vector2(0, -20), 5.0],
}
## Opacity of each kind (embers cycle through MOTE_ALPHAS).
const MOTE_ALPHA := {
	"snow": 1.0, "embers": 1.0, "sprinkles": 1.0, "leaves": 1.0, "petals": 0.9, "bubbles": 0.6
}
const MOTE_ALPHAS := [0.4, 0.55, 0.7, 0.9]
## Particles fade in and out over this many px at the ends of their band.
const MOTE_FADE := 24.0
## Snow: small flakes fall faster than big ones.
const SNOW_SIZES := [1.6, 2.2, 3.0]
const SNOW_SPEED := [1.25, 1.0, 0.7]
## Embers live this long (s) before they flicker out and start again.
const EMBER_LIFE := 1.6
const SPRINKLE_COLORS := [
	Color("#FF6FA8"), Color("#7FD3FF"), Color("#FFD23F"), Color("#7FE3B5"), Color("#B69CFF")
]
const LEAF_COLORS := [Color("#E2603A"), Color("#F2A23A"), Color("#C9452F")]


## The sky and the world's scene, drawn behind the room's own drawing and only
## redrawn when the world or the sky changes.
class Backdrop:
	extends Node2D
	var view: RoomView

	func _draw() -> void:
		view.paint_backdrop(self)


## Off when the player turns on reduced flashing (accessibility).
var flash_enabled := true
## The big faint score behind the flyer: only while a run is being played,
## never behind menus or the game-over score.
var show_score := false:
	set(value):
		show_score = value
		queue_redraw()
## Color-blind spikes (Settings): ceiling, floor and wall spikes in ink with a
## white edge instead of the world's spike colour.
var color_blind_spikes := false:
	set(value):
		color_blind_spikes = value
		queue_redraw()

## How portals look (Customize > Portals); main sets the equipped one.
var portal_style: PortalStyle = PortalStyle.match_world()
var _run: RunController
var _theme: ThemeDef
var _backdrop: Backdrop
## The sky the backdrop was last drawn with.
var _drawn_sky: Array[Color] = []
## Per-slot slide-in progress (0..1) for each side wall.
var _left_reveal := PackedFloat32Array()
var _right_reveal := PackedFloat32Array()
var _sky: Array[Color] = []
var _prev_sky: Array[Color] = []
var _fade := 1.0
var _flash := 0.0
var _exit_fade := 0.0
## The ghost: fades in while previewed, out while the real exit opens.
var _ghost_fade := 0.0
## The portal the bird just came out of (opposite wall): 1 when it arrives,
## closing to 0 over ARRIVAL_CLOSE_TIME.
var _arrival := 0.0
var _arrival_side := 0
var _arrival_y := 0
var _arrival_kind := SimState.ExitKind.NORMAL
var _room_index := 0
var _time := 0.0


func _init() -> void:
	_backdrop = Backdrop.new()
	_backdrop.view = self
	_backdrop.show_behind_parent = true
	add_child(_backdrop)


func bind(run: RunController, theme: ThemeDef) -> void:
	_run = run
	_left_reveal.resize(SimConfig.SLOT_COUNT)
	_right_reveal.resize(SimConfig.SLOT_COUNT)
	_left_reveal.fill(0.0)
	_right_reveal.fill(0.0)
	_room_index = 0
	set_theme(theme)


## Switches world instantly (theme picker); keeps the current room's palette slot.
func set_theme(theme: ThemeDef) -> void:
	_theme = theme
	_sky = theme.sky_for_room(_room_index)
	_prev_sky = _sky
	_fade = 1.0
	_flash = 0.0
	_drawn_sky = []
	_backdrop.queue_redraw()
	queue_redraw()


func on_room_changed(room_index: int) -> void:
	if _run != null and _run.sim != null and room_index > 0:
		var s := _run.sim.state
		# It flies away from the wall it came out of.
		_arrival_side = 0 if s.vx > 0 else 1
		_arrival_y = s.y
		_arrival_kind = s.route if s.score % SimConfig.FORK_EVERY == 0 else SimState.ExitKind.NORMAL
		_arrival = 1.0
	_prev_sky = _current_sky()
	_room_index = room_index
	_sky = _theme.sky_for_room(room_index)
	_fade = 0.0
	if flash_enabled:
		_flash = 1.0


func _process(delta: float) -> void:
	_time += delta
	if _theme != null and _shown_sky() != _drawn_sky:
		_backdrop.queue_redraw()
	if _run == null or _run.sim == null:
		queue_redraw()
		return
	var s := _run.sim.state
	_animate_wall(_left_reveal, _run.sim.wall_mask(0), delta)
	_animate_wall(_right_reveal, _run.sim.wall_mask(1), delta)
	_fade = minf(_fade + delta * FADE_SPEED, 1.0)
	_flash = maxf(_flash - delta * FADE_SPEED, 0.0)
	# Exits fade in over EXIT_FADE_TIME when they open.
	if s.exit_open:
		_exit_fade = minf(_exit_fade + delta / EXIT_FADE_TIME, 1.0)
	else:
		_exit_fade = 0.0
	if s.exit_preview:
		_ghost_fade = minf(_ghost_fade + delta / GHOST_FADE_TIME, 1.0)
	elif s.exit_open:
		_ghost_fade = maxf(_ghost_fade - delta / EXIT_FADE_TIME, 0.0)
	else:
		_ghost_fade = 0.0
	_arrival = maxf(_arrival - delta / ARRIVAL_CLOSE_TIME, 0.0)
	queue_redraw()


func _animate_wall(reveal: PackedFloat32Array, mask: int, delta: float) -> void:
	for slot in SimConfig.SLOT_COUNT:
		var target := 1.0 if RoomRules.has_slot(mask, slot) else 0.0
		reveal[slot] = move_toward(reveal[slot], target, delta * SLIDE_SPEED)


func _current_sky() -> Array[Color]:
	if _fade >= 1.0:
		return _sky
	var out: Array[Color] = []
	for i in 3:
		out.append(_prev_sky[i].lerp(_sky[i], _fade))
	return out


## The sky as shown: Gravity Flip turns it upside down, so players see it coming.
func _shown_sky() -> Array[Color]:
	var sky := _current_sky()
	var room := _run.sim.room if _run != null and _run.sim != null else null
	if room != null and room.def.skin == "midnight":
		# Midnight Cage: the sky darkens more than the scene.
		var night := WorldScenes.midnight_dim(_theme).y
		var dark: Array[Color] = []
		for c in sky:
			dark.append(c.lerp(WorldScenes.MIDNIGHT_TINT, night))
		sky = dark
	if room != null and room.def.gravity_sign < 0:
		var flipped: Array[Color] = [sky[2], sky[1], sky[0]]
		return flipped
	return sky


## The Backdrop's drawing: sky stops of the room, then the world's scene.
func paint_backdrop(canvas: CanvasItem) -> void:
	if _theme == null:
		return
	_drawn_sky = _shown_sky()
	var pen := ScenePen.new(canvas)
	pen.sky = _drawn_sky
	pen.sky_split = _theme.sky_split
	WorldScenes.paint(pen, _theme)


func _draw() -> void:
	if _theme == null:
		return
	var room := _run.sim.room if _run != null and _run.sim != null else null
	_draw_motes()
	if room != null and room.def.skin == "midnight":
		var dim := WorldScenes.midnight_dim(_theme).x
		draw_rect(Rect2(0, 0, W, H), Color(WorldScenes.MIDNIGHT_TINT, dim))
	_draw_score()
	_draw_edges()
	if room != null:
		var inset := room.inset() / float(SimConfig.SUB)
		_draw_side_spikes(_left_reveal, 0, inset, 1.0)
		_draw_side_spikes(_right_reveal, 1, W - inset, -1.0)
		if room.def.wall_mode == RoomDef.WallMode.BLINK:
			_draw_blink_preview(room, inset)
		if _arrival > 0.0:
			var wall_x := inset if _arrival_side == 0 else W - inset
			var into := 1.0 if _arrival_side == 0 else -1.0
			_draw_exit(wall_x, into, _arrival_y, _arrival_kind, _arrival_curve(), false)
		if _ghost_fade > 0.0 and (_run.sim.state.exit_preview or _run.sim.state.exit_open):
			_draw_ghosts(inset)
		if _run.sim.state.exit_open:
			_draw_exits(inset)
	if _flash > 0.0:
		draw_rect(Rect2(0, 0, W, H), Color(_theme.world_accent, FLASH_ALPHA * _flash))


## The particle kind for a world id ("" for worlds with none).
static func mote_kind(world_id: String) -> String:
	return MOTE_KIND.get(world_id, "")


## The world's falling things (shape and motion from MOTE_KIND), in their band
## below the score, wrapping round and fading at the band's ends.
func _draw_motes() -> void:
	var kind := mote_kind(_theme.id)
	if kind.is_empty():
		return
	var pen := ScenePen.new(self)
	var motion: Array = MOTE_MOTION[kind]
	var vel: Vector2 = motion[0]
	var wobble: float = motion[1]
	var band: Vector2 = MOTE_BAND.get(_theme.id, Vector2(MOTE_TOP, H * 0.75))
	var top := maxf(band.x, MOTE_TOP)
	var span := band.y - top
	for i in int(MOTE_COUNT.get(_theme.id, 12)):
		var size := i % 3
		var speed: float = SNOW_SPEED[size] if kind == "snow" else 0.85 + 0.1 * size
		var phase := _time * 0.8 + i * 1.7
		var x := fposmod(37.0 + i * 83.7 + vel.x * speed * _time + sin(phase) * wobble, W)
		var y := fposmod(fposmod(0.13 + i * 0.618034, 1.0) * span + vel.y * speed * _time, span)
		var edge := minf(y, span - y)
		var alpha: float = MOTE_ALPHA[kind] * clampf(edge / MOTE_FADE, 0.0, 1.0)
		if alpha <= 0.0:
			continue
		# 0 at the bottom of the band, 1 at the top (bubbles grow as they rise).
		var height := 1.0 - y / span
		_draw_mote(pen, kind, Vector2(x, top + y), size, alpha, phase, i, height)


## One flat particle. `size` is 0, 1 or 2 (small to big), `height` 0..1 up the band.
func _draw_mote(
	pen: ScenePen,
	kind: String,
	pos: Vector2,
	size: int,
	alpha: float,
	phase: float,
	i: int,
	height: float
) -> void:
	var col := Color(_theme.particle, alpha)
	match kind:
		"snow":
			pen.circle(pos, SNOW_SIZES[size], col)
		"embers":
			# 4 px diamonds that rise and flicker out.
			var life := fposmod(_time / EMBER_LIFE + i * 0.618, 1.0)
			var flicker := 0.75 + 0.25 * sin(phase * 9.0)
			var a: float = (
				MOTE_ALPHAS[i % MOTE_ALPHAS.size()]
				* alpha
				* flicker
				* smoothstep(0.0, 0.12, life)
				* (1.0 - life)
			)
			pen.push(ScenePen.place(pos.x, pos.y, 45.0))
			pen.rect(-2, -2, 4, 4, Color(_theme.particle, a), 1)
			pen.pop()
		"sprinkles":
			# 9 x 3.5 px candy sprinkles in five colours, tumbling.
			var c: Color = SPRINKLE_COLORS[i % SPRINKLE_COLORS.size()]
			pen.push(ScenePen.place(pos.x, pos.y, rad_to_deg(phase * 1.5) + i * 40.0))
			pen.rect(-4.5, -1.75, 9, 3.5, Color(c, alpha), 1.75)
			pen.pop()
		"leaves":
			# 12 x 8 px leaves, pointed at both ends, turning as they fall.
			var flip := maxf(absf(cos(phase * 0.9)), 0.3)
			var c: Color = LEAF_COLORS[i % LEAF_COLORS.size()]
			pen.push(ScenePen.place(pos.x, pos.y, rad_to_deg(phase * 0.7) + i * 57.0, 1.0, flip))
			pen.fill(ScenePath.at(-6, 0).q(0, -8, 6, 0).q(0, 8, -6, 0).done(), Color(c, alpha))
			pen.pop()
		"petals":
			# 10 x 6 px petals that flutter as they float past.
			var flip := maxf(absf(cos(phase * 1.1)), 0.3)
			pen.ellipse(pos, 5.0, 3.0 * flip, col, rad_to_deg(phase * 0.6) + i * 57.0)
		"bubbles":
			# Rings that grow a little as they rise.
			var r := (3.5 + 1.0 * size) * (1.0 + 0.25 * height)
			pen.ring(pos, r, col, 2.0)


## The score to show: the run's score, or in practice the points scored since
## the practice started (it starts at the room's from_score).
static func practice_points(sim: GameSim) -> int:
	if sim.is_practice():
		return sim.state.score - RoomCatalog.all()[sim.practice_room].from_score
	return sim.state.score


func _draw_score() -> void:
	if not show_score:
		return
	var score := 0 if _run == null or _run.sim == null else practice_points(_run.sim)
	draw_string(
		GameFonts.display(),
		Vector2(0, 380),
		str(score),
		HORIZONTAL_ALIGNMENT_CENTER,
		W,
		UiTokens.FONT_SIZE_SCORE_GHOST,
		UiTokens.SCORE_GHOST
	)


func _draw_edges() -> void:
	var body := INK_SPIKE if color_blind_spikes else _theme.spike
	for r in surround_rects():
		draw_rect(r, body)
	draw_rect(Rect2(0, 0, W, BAND), body)
	draw_rect(Rect2(0, H - BAND, W, BAND), body)
	var count := int(W / (EDGE_SPIKE_HALF * 2.0))
	var step := W / count
	for i in count:
		var cx := step * (i + 0.5)
		_draw_spike(Vector2(cx, BAND), Vector2(0, 1), EDGE_SPIKE_HALF, EDGE_SPIKE_DEPTH)
		_draw_spike(Vector2(cx, H - BAND), Vector2(0, -1), EDGE_SPIKE_HALF, EDGE_SPIKE_DEPTH)


## The band colour around the room: above, below, left and right of it.
static func surround_rects() -> Array[Rect2]:
	var s := SURROUND
	var out: Array[Rect2] = [
		Rect2(-s, -s, W + s * 2.0, s),
		Rect2(-s, H, W + s * 2.0, s),
		Rect2(-s, 0, s, H),
		Rect2(W, 0, s, H),
	]
	return out


func _draw_side_spikes(reveal: PackedFloat32Array, side: int, wall_x: float, dir: float) -> void:
	var room := _run.sim.room
	if room.inset() > 0:
		# Squeeze Box: the wall itself moves in; draw it as a band.
		var band_x := 0.0 if side == 0 else wall_x
		var band := INK_SPIKE if color_blind_spikes else _theme.spike
		draw_rect(Rect2(band_x, 0, wall_x if side == 0 else W - wall_x, H), band)
	for slot in SimConfig.SLOT_COUNT:
		var t := reveal[slot]
		if t <= 0.0:
			continue
		var cy := SimConfig.slot_center_y(slot) / float(SimConfig.SUB)
		# Tide spikes slide in and out: the drawn depth follows the sim's. Up to
		# normal size the spike slides out of the wall; past it, it grows longer.
		var out := float(room.slot_depth(side, slot)) / SimConfig.SPIKE_DEPTH
		var depth := SPIKE_DEPTH * ease(t, 0.5) * out
		if depth > SPIKE_DEPTH:
			_draw_spike(Vector2(wall_x, cy), Vector2(dir, 0), SPIKE_HALF, depth)
		else:
			var base_x := wall_x - dir * (SPIKE_DEPTH - depth)
			_draw_spike(Vector2(base_x, cy), Vector2(dir, 0), SPIKE_HALF, SPIKE_DEPTH)


## The open exit(s). Safe, so never in the spike colour: the style's colour
## (by default the world's accent) for a normal exit, mint for Calm and gold
## for Wild (each fork exit also carries a sticker label, not colour alone).
func _draw_exits(inset: float) -> void:
	var s := _run.sim.state
	var wall_x := inset if s.exit_side == 0 else W - inset
	var into := 1.0 if s.exit_side == 0 else -1.0
	var open := _exit_open_curve()
	_draw_exit(wall_x, into, s.exit_a_y, s.exit_a_kind, open, true)
	if s.exit_b_kind != SimState.ExitKind.NORMAL:
		_draw_exit(wall_x, into, s.exit_b_y, s.exit_b_kind, open, true)


## The next exit(s), one point early: faint, slowly pulsing, with a dashed
## rim, on the wall and at the height(s) they will open at. They fade out
## while the real exit grows in their place.
func _draw_ghosts(inset: float) -> void:
	var s := _run.sim.state
	var wall_x := inset if s.exit_side == 0 else W - inset
	var into := 1.0 if s.exit_side == 0 else -1.0
	_draw_ghost(wall_x, into, s.exit_a_y, s.exit_a_kind)
	if s.exit_b_kind != SimState.ExitKind.NORMAL:
		_draw_ghost(wall_x, into, s.exit_b_y, s.exit_b_kind)


func _draw_ghost(wall_x: float, into: float, y_sub: int, kind: int) -> void:
	var center := Vector2(wall_x + into * EXIT_DEPTH, y_sub / float(SimConfig.SUB))
	var half := SimConfig.EXIT_HALF / float(SimConfig.SUB)
	var side := 0 if into > 0.0 else 1
	var pulse := 0.5 + 0.5 * sin(_time * TAU / GHOST_PULSE_TIME)
	var alpha := _ghost_fade * (GHOST_ALPHA + GHOST_PULSE_ALPHA * pulse)
	var override := _exit_override(kind)
	portal_style.draw_portal(
		self, center, half, side, GHOST_OPEN, _time * GHOST_SPIN, _theme, override, alpha
	)
	var k := half / PortalPainter.REF_HALF
	var shift := (PortalPainter.DISC_DEPTH - PortalPainter.EXIT_CENTER_DEPTH) * k
	var disc := center + Vector2(into * shift, 0.0)
	var rim: Color = override if override.a > 0.0 else _theme.world_accent
	rim.a = _ghost_fade * GHOST_RIM_ALPHA
	var radius := Vector2(16.0 * k, half * 0.95)
	var steps := GHOST_RIM_DASHES * 2
	for i in range(0, steps, 2):
		var a0 := TAU * i / steps
		var a1 := TAU * (i + 1) / steps
		draw_line(
			disc + Vector2(cos(a0), sin(a0)) * radius,
			disc + Vector2(cos(a1), sin(a1)) * radius,
			rim,
			GHOST_RIM_W,
			true
		)
	if kind != SimState.ExitKind.NORMAL:
		_draw_exit_tag(center, into, kind, _ghost_fade * GHOST_RIM_ALPHA)


## One portal in the player's equipped style (Customize > Portals).
## `into` points from the wall into the room (+1 on the left wall). `open`
## scales it (0 = shut); `tagged` adds the Calm/Wild sticker.
func _draw_exit(
	wall_x: float, into: float, y_sub: int, kind: int, open: float, tagged: bool
) -> void:
	if open <= 0.0:
		return
	var center := Vector2(wall_x + into * EXIT_DEPTH, y_sub / float(SimConfig.SUB))
	var half := SimConfig.EXIT_HALF / float(SimConfig.SUB)
	var side := 0 if into > 0.0 else 1
	portal_style.draw_portal(self, center, half, side, open, _time, _theme, _exit_override(kind))
	if tagged and kind != SimState.ExitKind.NORMAL:
		_draw_exit_tag(center, into, kind)


## The rift opens from a thin slit with a little overshoot.
func _exit_open_curve() -> float:
	var t := _exit_fade
	if t >= 1.0:
		return 1.0
	return clampf(1.0 - pow(1.0 - t, 3.0) + sin(t * PI) * 0.12, 0.0, 1.12)


## The arrival portal stays open a moment, then snaps shut.
func _arrival_curve() -> float:
	var hold := 0.45
	if _arrival >= hold:
		return 1.0
	return ease(_arrival / hold, 0.4)


## Calm and Wild exits keep their own colour in every style; a normal exit
## uses the style's (clear = the style decides).
func _exit_override(kind: int) -> Color:
	match kind:
		SimState.ExitKind.CALM:
			return UiTokens.SUCCESS
		SimState.ExitKind.WILD:
			return UiTokens.ACTION
	return Color(0, 0, 0, 0)


## Fork exits: a flat cream pill on the room side (no outline, no drop): a
## mint dot and "Calm", or the coin and "Wild +3".
func _draw_exit_tag(center: Vector2, into: float, kind: int, alpha: float = 1.0) -> void:
	var tint := Color(1, 1, 1, alpha)
	var wild := kind == SimState.ExitKind.WILD
	var text := "Wild +%d" % SimConfig.WILD_COINS if wild else "Calm"
	var font := GameFonts.ui(900)
	var size := UiTokens.FONT_SIZE_LABEL
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var mark := EXIT_TAG_ICON if wild else EXIT_TAG_DOT
	var w := text_w + 20.0 + mark + 4.0
	var h := 28.0
	var x := center.x + into * (EXIT_RX + 10.0) - (w if into < 0.0 else 0.0)
	var rect := Rect2(x, center.y - h / 2.0, w, h)
	UiTheme.flat(UiTokens.PANEL * tint, UiTokens.RADIUS_PILL, 0).draw(get_canvas_item(), rect)
	var tx := rect.position.x + 10.0
	if wild:
		var icon := Rect2(tx, center.y - EXIT_TAG_ICON / 2.0, EXIT_TAG_ICON, EXIT_TAG_ICON)
		draw_texture_rect(COIN_ICON, icon, false, tint)
	else:
		draw_circle(
			Vector2(tx + EXIT_TAG_DOT / 2.0, center.y), EXIT_TAG_DOT / 2.0, UiTokens.SUCCESS * tint
		)
	tx += mark + 4.0
	draw_string(
		font,
		Vector2(tx, center.y + size * 0.36),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		size,
		UiTokens.ON_PANEL * tint
	)


## Blink Walls: the pattern coming next shows as outlines.
func _draw_blink_preview(room: RoomRuntime, inset: float) -> void:
	var s := _run.sim.state
	var second := room.blink_showing_second()
	var next_left := s.left_spikes if second else room.blink_left
	var next_right := s.right_spikes if second else room.blink_right
	var outline := Color(INK_SPIKE if color_blind_spikes else _theme.spike, BLINK_OUTLINE_ALPHA)
	for side in 2:
		var mask := next_left if side == 0 else next_right
		var wall_x := inset if side == 0 else W - inset
		var dir := 1.0 if side == 0 else -1.0
		for slot in SimConfig.SLOT_COUNT:
			if not RoomRules.has_slot(mask, slot):
				continue
			var cy := SimConfig.slot_center_y(slot) / float(SimConfig.SUB)
			var pts := spike_points(Vector2(wall_x, cy), Vector2(dir, 0), SPIKE_HALF, SPIKE_DEPTH)
			draw_polyline(pts, outline, 2.0, true)


## A rounded spike's outline from one base corner round the tip to the other:
## `base` is the middle of its base, `dir` points to the tip, `depth` px away.
static func spike_points(
	base: Vector2, dir: Vector2, half: float, depth: float
) -> PackedVector2Array:
	var side := Vector2(-dir.y, dir.x)
	var p := ScenePath.at(base.x + side.x * half, base.y + side.y * half)
	var near := base + dir * (depth - TIP_BACK)
	var a := near + side * TIP_HALF
	var b := near - side * TIP_HALF
	var ctrl := base + dir * (depth + TIP_BACK)
	p.l(a.x, a.y).q(ctrl.x, ctrl.y, b.x, b.y)
	p.l(base.x - side.x * half, base.y - side.y * half)
	return p.done()


## The lit half of a rounded spike (the half toward the top-left light), from
## the base corner to the tip and back down the middle.
static func spike_lit_points(
	base: Vector2, dir: Vector2, half: float, depth: float
) -> PackedVector2Array:
	var side := Vector2(-dir.y, dir.x)
	if side.x + side.y > 0.0:
		side = -side
	var near := base + dir * (depth - TIP_BACK) + side * TIP_HALF
	var ctrl := base + dir * (depth + TIP_BACK)
	var tip := base + dir * depth
	var p := ScenePath.at(base.x + side.x * half, base.y + side.y * half).l(near.x, near.y)
	p.q(ctrl.x, ctrl.y, tip.x, tip.y).l(base.x, base.y)
	return p.done()


## A two-tone rounded spike (design canvas "Worlds v4"): the world's spike
## colour with its lit half in spike-edge; color-blind spikes are ink with a
## white edge.
func _draw_spike(base: Vector2, dir: Vector2, half: float, depth: float) -> void:
	var pen := ScenePen.new(self)
	var pts := spike_points(base, dir, half, depth)
	pen.fill(pts, INK_SPIKE if color_blind_spikes else _theme.spike)
	pen.fill(
		spike_lit_points(base, dir, half, depth),
		INK_SPIKE_EDGE if color_blind_spikes else _theme.spike_edge
	)
	if color_blind_spikes:
		pen.stroke(pts, INK_SPIKE_LINE, INK_SPIKE_LINE_W)


## Nothing is cached any more; kept so main can call it on exit.
static func release() -> void:
	pass
