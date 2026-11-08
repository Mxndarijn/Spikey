class_name RoomView
extends Node2D
## Draws the room in the "Soft light" style from the chosen world (ThemeDef):
## the sky gradient with large blurred patches of its own sky stops, one glow
## bloom, a few drifting particles, the ghost score, and smooth spikes from sim
## state. Cosmetic only; hitboxes live in sim/.

const W := float(UiTokens.SIZE_VIEWPORT_W)
const H := float(UiTokens.SIZE_VIEWPORT_H)
const BAND := 8.0
const SPIKE_DEPTH := float(UiTokens.SIZE_SPIKE_DEPTH)
const SPIKE_HALF := UiTokens.SIZE_SPIKE_BASE / 2.0
## Ceiling and floor: one unbroken row of 9 wide spikes. Band + depth reach the
## sim's kill lines (SimConfig.KILL_TOP = 34 px), so all of it looks deadly.
const EDGE_SPIKE_DEPTH := 26.0
const EDGE_SPIKE_HALF := 20.0
const SPIKE_EDGE_ALPHA := 0.55
## Wall spikes slide in over about 125 ms; the sky fades over 400 ms.
const SLIDE_SPEED := 8.0
const FADE_SPEED := 2.5
const FLASH_ALPHA := 0.35
## Exit portals: half-width (where the Calm/Wild tag goes), how far the centre
## sits from the wall (px), open time (s), tag coin size.
const EXIT_RX := 22.0
const EXIT_DEPTH := 6.0
const EXIT_FADE_TIME := 0.5
const EXIT_TAG_ICON := 16.0
## How long the portal the bird came out of takes to close, seconds.
const ARRIVAL_CLOSE_TIME := 0.7
const COIN_ICON := preload("res://assets/ui/coin.svg")
## Midnight Cage dims the room with ink.
const MIDNIGHT_DIM := 0.35
## Blink Walls: alpha of the outlines that show the next pattern.
const BLINK_OUTLINE_ALPHA := 0.6
## Soft light patches: [center, radii, sky stop A, stop B, mix of B, alpha].
const PATCHES := [
	[Vector2(36, 0), Vector2(300, 270), 0, 0, 0.0, 1.0],
	[Vector2(360, 288), Vector2(200, 225), 0, 1, 0.5, 0.8],
	[Vector2(0, 640), Vector2(270, 264), 2, 2, 0.0, 1.0],
	[Vector2(360, 640), Vector2(225, 200), 1, 2, 0.6, 0.8],
]
const BLOOM_CENTER := Vector2(250, 190)
const BLOOM_RADIUS := 150.0
## Ambient particles: [x, y] seeds spread over the play area. Each world's kind
## decides the shape, size and motion (design boards "Ambient particles per
## world" and "Six new worlds"). They wrap around the play area, behind the spikes.
const MOTES := [
	[52.0, 220.0],
	[300.0, 330.0],
	[110.0, 380.0],
	[236.0, 470.0],
	[40.0, 520.0],
	[190.0, 140.0],
	[270.0, 90.0],
	[150.0, 560.0],
	[330.0, 200.0],
	[90.0, 300.0],
	[20.0, 110.0],
	[210.0, 260.0],
	[320.0, 430.0],
	[130.0, 470.0],
	[250.0, 580.0],
	[70.0, 70.0],
	[170.0, 330.0],
	[340.0, 540.0],
]
## Opacity of each particle, cycling like the boards (0.4 to 0.85).
const MOTE_ALPHAS := [0.4, 0.55, 0.7, 0.85]
const MOTE_KIND := {
	"sunset": "dust",
	"jungle": "pollen",
	"ice": "snow",
	"lava": "embers",
	"deepsea": "bubbles",
	"sugar": "sprinkles",
	"star": "stars",
	"autumn": "leaves",
	"desert": "sand",
	"blossom": "petals",
	"neon": "rain",
	"haunted": "fireflies",
	"winterfest": "snow",
}
## Per kind: drift speed in px/s (x, y) and sideways wobble in px.
const MOTE_MOTION := {
	"dust": [Vector2(6, -2), 4.0],
	"pollen": [Vector2(2, -12), 6.0],
	"snow": [Vector2(-3, 18), 8.0],
	"embers": [Vector2(2, -40), 4.0],
	"bubbles": [Vector2(0, -20), 5.0],
	"sprinkles": [Vector2(3, 24), 3.0],
	"stars": [Vector2.ZERO, 0.0],
	"leaves": [Vector2(-10, 18), 14.0],
	"sand": [Vector2(14, 1), 2.5],
	"petals": [Vector2(8, 12), 12.0],
	"rain": [Vector2(-55, 220), 0.0],
	"fireflies": [Vector2(3, -3), 12.0],
}
## Snow: small flakes fall faster than big ones.
const SNOW_SPEED := [1.25, 1.0, 0.7]
## Embers live this long (s) before they flicker out and start again.
const EMBER_LIFE := 1.6
const SPRINKLE_COLORS := [Color("#FFFFFF"), Color("#FF5FA2"), Color("#5CC8FF"), Color("#FFE45C")]
## Faint film grain over the sky (behind the spikes) so it reads as soft light,
## not a flat vector fill.
const GRAIN_ALPHA := 0.06
const GRAIN_TILE := 128

static var _soft: GradientTexture2D
static var _bloom: GradientTexture2D
static var _grain: NoiseTexture2D

## Off when the player turns on reduced flashing (accessibility).
var flash_enabled := true
## The big faint score behind the flyer: only while a run is being played,
## never behind menus or the game-over score.
var show_score := false:
	set(value):
		show_score = value
		queue_redraw()

## How portals look (Customize > Portals); main sets the equipped one.
var portal_style: PortalStyle = PortalStyle.cloud_hole()
var _run: RunController
var _theme: ThemeDef
## Per-slot slide-in progress (0..1) for each side wall.
var _left_reveal := PackedFloat32Array()
var _right_reveal := PackedFloat32Array()
var _sky: Array[Color] = []
var _prev_sky: Array[Color] = []
var _fade := 1.0
var _flash := 0.0
var _exit_fade := 0.0
## The portal the bird just came out of (opposite wall): 1 when it arrives,
## closing to 0 over ARRIVAL_CLOSE_TIME.
var _arrival := 0.0
var _arrival_side := 0
var _arrival_y := 0
var _arrival_kind := SimState.ExitKind.NORMAL
var _room_index := 0
var _time := 0.0


func _init() -> void:
	# The grain texture is tiled across the room.
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


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
	if _run == null or _run.sim == null:
		return
	var s := _run.sim.state
	var room := _run.sim.room
	_animate_wall(_left_reveal, _run.sim.wall_mask(0), delta)
	_animate_wall(_right_reveal, _run.sim.wall_mask(1), delta)
	_fade = minf(_fade + delta * FADE_SPEED, 1.0)
	_flash = maxf(_flash - delta * FADE_SPEED, 0.0)
	# Exits fade in over EXIT_FADE_TIME when they open.
	if s.exit_open:
		_exit_fade = minf(_exit_fade + delta / EXIT_FADE_TIME, 1.0)
	else:
		_exit_fade = 0.0
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


func _draw() -> void:
	if _theme == null:
		return
	var sky := _current_sky()
	var room := _run.sim.room if _run != null and _run.sim != null else null
	# Gravity Flip turns the sky upside down too, so players see it coming.
	if room != null and room.def.gravity_sign < 0:
		sky = [sky[2], sky[1], sky[0]]
	_draw_sky(sky)
	if room != null and room.def.skin == "midnight":
		draw_rect(Rect2(0, 0, W, H), Color(UiTokens.INK_900, MIDNIGHT_DIM))
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
		if _run.sim.state.exit_open:
			_draw_exits(inset)
	if _flash > 0.0:
		draw_rect(Rect2(0, 0, W, H), Color(_theme.world_accent, FLASH_ALPHA * _flash))


func _draw_sky(sky: Array[Color]) -> void:
	var half := H * 0.55
	draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W, half), Vector2(0, half)]),
		PackedColorArray([sky[0], sky[0], sky[1], sky[1]])
	)
	draw_polygon(
		PackedVector2Array([Vector2(0, half), Vector2(W, half), Vector2(W, H), Vector2(0, H)]),
		PackedColorArray([sky[1], sky[1], sky[2], sky[2]])
	)
	# Only the world's own sky stops (and mixes of them), so spikes keep their contrast.
	for p: Array in PATCHES:
		var c: Color = sky[p[2]].lerp(sky[p[3]], p[4])
		c.a = p[5]
		_draw_soft(soft_texture(), p[0], p[1], c)
	_draw_soft(bloom_texture(), BLOOM_CENTER, Vector2(BLOOM_RADIUS, BLOOM_RADIUS), _theme.glow)
	draw_texture_rect(grain_texture(), Rect2(0, 0, W, H), true, Color(1, 1, 1, GRAIN_ALPHA))
	_draw_motes()


## The world's ambient particles (shape and motion from MOTE_KIND).
func _draw_motes() -> void:
	var kind := mote_kind(_theme.id)
	var motion: Array = MOTE_MOTION[kind]
	var vel: Vector2 = motion[0]
	var wobble: float = motion[1]
	var top := BAND + EDGE_SPIKE_DEPTH
	var span := H - 2.0 * top
	for i in MOTES.size():
		var m: Array = MOTES[i]
		var size := i % 3
		var speed: float = SNOW_SPEED[size] if kind == "snow" else 0.85 + 0.1 * size
		var phase := _time * 0.8 + i * 1.7
		var x := fposmod(m[0] + vel.x * speed * _time + sin(phase) * wobble, W)
		var y := fposmod(m[1] - top + vel.y * speed * _time, span) + top
		# 0 at the floor, 1 at the ceiling (bubbles grow as they rise).
		var height := 1.0 - (y - top) / span
		_draw_mote(kind, Vector2(x, y), size, MOTE_ALPHAS[i % MOTE_ALPHAS.size()], phase, i, height)


## One particle. `size` is 0, 1 or 2 (small to big), `height` 0..1 up the room.
func _draw_mote(
	kind: String, pos: Vector2, size: int, alpha: float, phase: float, i: int, height: float
) -> void:
	var col := Color(_theme.particle, alpha)
	match kind:
		"dust":
			# A 4 px mote in a soft glow.
			_draw_soft(soft_texture(), pos, Vector2(7, 7), Color(_theme.particle, alpha * 0.45))
			draw_circle(pos, 2.0, col)
		"pollen":
			# A 6 px grain with a 2 px pale ring.
			draw_circle(pos, 5.0, Color(_theme.particle, alpha * 0.35))
			draw_circle(pos, 3.0, col)
		"snow":
			# 3, 5 or 7 px flakes. A faint rim in the deepest sky stop keeps
			# white flakes visible on near-white skies.
			var r := 1.5 + size
			draw_circle(pos, r + 0.75, Color(_theme.sky_bottom, alpha * 0.25))
			draw_circle(pos, r, col)
		"embers":
			# 3 x 7 px sparks in an orange glow; they rise and flicker out.
			var life := fposmod(_time / EMBER_LIFE + i * 0.618, 1.0)
			var flicker := 0.75 + 0.25 * sin(phase * 9.0)
			var a := alpha * flicker * smoothstep(0.0, 0.12, life) * (1.0 - life)
			_draw_soft(soft_texture(), pos, Vector2(9, 9), Color(_theme.world_accent, 0.55 * a))
			var dir := Vector2.UP.rotated(deg_to_rad(float((i * 53) % 30 - 15)))
			_draw_capsule(pos, dir, 2.0, 1.5, Color(_theme.particle, a))
		"bubbles":
			# 6, 9 or 12 px rings that grow a little as they rise.
			var r := (3.0 + 1.5 * size) * (1.0 + 0.25 * height)
			draw_circle(pos, r, Color(_theme.particle, alpha * 0.12))
			draw_arc(pos, r, 0, TAU, 20, col, 1.5, true)
		"sprinkles":
			# 9 x 3 px candy sprinkles in four colours, tumbling.
			var dir := Vector2.from_angle(phase * 1.5 + i)
			var c: Color = SPRINKLE_COLORS[i % SPRINKLE_COLORS.size()]
			_draw_capsule(pos, dir, 3.0, 1.5, Color(c, alpha))
		"stars":
			# Stay put; each one flares up in turn.
			var tw := pow(maxf(sin(_time * 1.1 + i * 2.4), 0.0), 4.0)
			var r := 3.5 + 0.5 * size
			_draw_sparkle(pos, r * (1.0 + 0.4 * tw), Color(col, alpha * (0.45 + 0.55 * tw)))
		"leaves":
			# 12 x 7 px leaves, pointed at both ends, turning as they fall.
			var flip := maxf(absf(cos(phase * 0.9)), 0.3)
			draw_set_transform(pos, phase * 0.7 + i, Vector2(1.0, flip))
			draw_colored_polygon(_leaf_points(6.0, 3.5), col)
			draw_set_transform(Vector2.ZERO)
		"petals":
			# 9 x 6 px petals that flutter as they float past.
			var flip := maxf(absf(cos(phase * 1.1)), 0.3)
			draw_set_transform(pos, phase * 0.6 + i, Vector2(1.0, 0.67 * flip))
			draw_circle(Vector2.ZERO, 4.5, col)
			draw_set_transform(Vector2.ZERO)
		"rain":
			# 2 x 16 px streaks along the fall direction.
			var dir: Vector2 = (MOTE_MOTION["rain"][0] as Vector2).normalized()
			draw_line(pos - dir * 8.0, pos + dir * 8.0, col, 2.0, true)
		"fireflies":
			# 5 px lights in a wide glow, blinking on and off one by one.
			var blink := clampf(sin(phase * 1.3) * 1.5, 0.0, 1.0)
			_draw_soft(soft_texture(), pos, Vector2(12, 12), Color(col, 0.45 * alpha * blink))
			draw_circle(pos, 2.5, Color(_theme.particle, blink))
		"sand":
			draw_circle(pos, 1.5, col)


## A rounded stick: `half_len` px from centre to each end along `dir`, `r` px thick.
## One polygon, so see-through particles have no darker overlaps.
func _draw_capsule(c: Vector2, dir: Vector2, half_len: float, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var base := dir.angle()
	for j in 5:
		pts.append(c + dir * half_len + Vector2.from_angle(base - PI / 2.0 + PI * j / 4.0) * r)
	for j in 5:
		pts.append(c - dir * half_len + Vector2.from_angle(base + PI / 2.0 + PI * j / 4.0) * r)
	draw_colored_polygon(pts, col)


## A leaf outline, pointed at both ends.
static func _leaf_points(half_len: float, half_w: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for j in 6:
		var t := j / 6.0
		pts.append(Vector2(lerpf(-half_len, half_len, t), -sin(PI * t) * half_w))
	for j in 6:
		var t := j / 6.0
		pts.append(Vector2(lerpf(half_len, -half_len, t), sin(PI * t) * half_w))
	return pts


func _draw_sparkle(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 8:
		var reach := r if k % 2 == 0 else r * 0.3
		pts.append(c + Vector2.from_angle(PI / 4.0 * k - PI / 2.0) * reach)
	draw_colored_polygon(pts, col)


## The particle kind for a world id ("dust" for worlds without one).
static func mote_kind(world_id: String) -> String:
	return MOTE_KIND.get(world_id, "dust")


func _draw_soft(tex: Texture2D, center: Vector2, radii: Vector2, color: Color) -> void:
	draw_texture_rect(tex, Rect2(center - radii, radii * 2.0), false, color)


## White in the middle, fading smoothly to clear at the edge; tinted per patch.
static func soft_texture() -> GradientTexture2D:
	if _soft == null:
		_soft = _radial(
			PackedFloat32Array([0.0, 0.45, 1.0]),
			PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
		)
	return _soft


## The glow bloom: glow-inner at the centre, glow-outer at the edge of its
## core, then nothing.
static func bloom_texture() -> GradientTexture2D:
	if _bloom == null:
		_bloom = _radial(
			PackedFloat32Array([0.0, 0.3, 1.0]),
			PackedColorArray(
				[
					Color(1, 1, 1, UiTokens.OPACITY_GLOW_INNER),
					Color(1, 1, 1, UiTokens.OPACITY_GLOW_OUTER),
					Color(1, 1, 1, 0),
				]
			)
		)
	return _bloom


## Seamless value noise, tiled over the room at GRAIN_ALPHA.
static func grain_texture() -> NoiseTexture2D:
	if _grain == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_VALUE
		noise.frequency = 0.9
		noise.seed = 7
		_grain = NoiseTexture2D.new()
		_grain.noise = noise
		_grain.width = GRAIN_TILE
		_grain.height = GRAIN_TILE
		_grain.seamless = true
		_grain.generate_mipmaps = false
	return _grain


static func _radial(offsets: PackedFloat32Array, colors: PackedColorArray) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = colors
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t


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
	draw_rect(Rect2(0, 0, W, BAND), _theme.spike)
	draw_rect(Rect2(0, H - BAND, W, BAND), _theme.spike)
	var count := int(W / (EDGE_SPIKE_HALF * 2.0))
	var step := W / count
	for i in count:
		var cx := step * (i + 0.5)
		_draw_spike(Vector2(cx, BAND), Vector2(0, 1), EDGE_SPIKE_HALF, EDGE_SPIKE_DEPTH)
		_draw_spike(Vector2(cx, H - BAND), Vector2(0, -1), EDGE_SPIKE_HALF, EDGE_SPIKE_DEPTH)


func _draw_side_spikes(reveal: PackedFloat32Array, side: int, wall_x: float, dir: float) -> void:
	var room := _run.sim.room
	if room.inset() > 0:
		# Squeeze Box: the wall itself moves in; draw it as a band.
		var band_x := 0.0 if side == 0 else wall_x
		draw_rect(Rect2(band_x, 0, wall_x if side == 0 else W - wall_x, H), _theme.spike)
	for slot in SimConfig.SLOT_COUNT:
		var t := reveal[slot]
		if t <= 0.0:
			continue
		var cy := SimConfig.slot_center_y(slot) / float(SimConfig.SUB)
		# Tide spikes slide in and out: the drawn depth follows the sim's.
		var out := float(room.slot_depth(side, slot)) / SimConfig.SPIKE_DEPTH
		var depth := SPIKE_DEPTH * ease(t, 0.5) * out
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


## Fork exits: a white sticker tag (ink outline, hard drop) on the room side.
func _draw_exit_tag(center: Vector2, into: float, kind: int) -> void:
	var wild := kind == SimState.ExitKind.WILD
	var text := "Wild +%d" % SimConfig.WILD_COINS if wild else "Calm"
	var font := GameFonts.ui(900)
	var size := UiTokens.FONT_SIZE_LABEL
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var w := text_w + 20.0 + (EXIT_TAG_ICON + 4.0 if wild else 0.0)
	var h := 28.0
	var x := center.x + into * (EXIT_RX + 10.0) - (w if into < 0.0 else 0.0)
	var rect := Rect2(x, center.y - h / 2.0, w, h)
	var tag := StyleBoxFlat.new()
	tag.bg_color = UiTokens.PANEL
	tag.set_corner_radius_all(int(h / 2.0))
	tag.set_border_width_all(3)
	tag.border_color = UiTokens.INK_LINE
	tag.shadow_color = UiTokens.INK_LINE
	tag.shadow_offset = Vector2(0, 3)
	tag.anti_aliasing = true
	tag.draw(get_canvas_item(), rect)
	var tx := rect.position.x + 10.0
	if wild:
		var icon := Rect2(tx, center.y - EXIT_TAG_ICON / 2.0, EXIT_TAG_ICON, EXIT_TAG_ICON)
		draw_texture_rect(COIN_ICON, icon, false)
		tx += EXIT_TAG_ICON + 4.0
	draw_string(
		font,
		Vector2(tx, center.y + size * 0.36),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		size,
		UiTokens.ON_PANEL
	)


## Blink Walls: the pattern coming next shows as outlines.
func _draw_blink_preview(room: RoomRuntime, inset: float) -> void:
	var s := _run.sim.state
	var second := room.blink_showing_second()
	var next_left := s.left_spikes if second else room.blink_left
	var next_right := s.right_spikes if second else room.blink_right
	var outline := Color(_theme.spike, BLINK_OUTLINE_ALPHA)
	for side in 2:
		var mask := next_left if side == 0 else next_right
		var wall_x := inset if side == 0 else W - inset
		var dir := 1.0 if side == 0 else -1.0
		for slot in SimConfig.SLOT_COUNT:
			if not RoomRules.has_slot(mask, slot):
				continue
			var cy := SimConfig.slot_center_y(slot) / float(SimConfig.SUB)
			var pts := PackedVector2Array(
				[
					Vector2(wall_x, cy - SPIKE_HALF),
					Vector2(wall_x + dir * SPIKE_DEPTH, cy),
					Vector2(wall_x, cy + SPIKE_HALF),
				]
			)
			draw_polyline(pts, outline, 2.0, true)


## Smooth spike: a triangle with a rounded tip in the world's spike color,
## with one half lit in spike-edge.
func _draw_spike(base: Vector2, dir: Vector2, half: float, depth: float) -> void:
	var side := Vector2(-dir.y, dir.x)
	var a := base + side * half
	var b := base - side * half
	var tip := base + dir * depth
	var tip_r := 3.0
	var tip_c := tip - dir * tip_r * 1.6
	var arc := PackedVector2Array()
	for i in 7:
		var ang := lerpf(-PI * 0.38, PI * 0.38, i / 6.0)
		arc.append(tip_c + dir.rotated(ang) * tip_r)
	# Walk the tip arc from the a-side to the b-side so the outline never crosses itself.
	if arc[0].distance_squared_to(a) > arc[arc.size() - 1].distance_squared_to(a):
		arc.reverse()
	var pts := PackedVector2Array([a])
	pts.append_array(arc)
	pts.append(b)
	draw_colored_polygon(pts, _theme.spike)
	var lit := PackedVector2Array([base, tip_c + dir * tip_r, b])
	draw_colored_polygon(lit, Color(_theme.spike_edge, SPIKE_EDGE_ALPHA))
	# Filled polygons have hard, stair-stepped edges (no 2D MSAA in the
	# Compatibility renderer); an anti-aliased outline smooths them.
	var outline := pts.duplicate()
	outline.append(a)
	draw_polyline(outline, _theme.spike, 1.0, true)


## Drops the cached textures (on exit, so Godot can free them).
static func release() -> void:
	_soft = null
	_bloom = null
	_grain = null
