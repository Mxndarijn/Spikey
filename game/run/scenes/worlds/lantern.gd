extends RefCounted
## Lantern Night (seasonal, February): a festival evening. A string of paper
## lanterns under the ceiling, sky lanterns drifting up both sides, a full
## moon, a pagoda on the far hill, a red bridge, bamboo and a lantern post.

const STRING := Color("#1B0C26")
const PAPER_RED := Color("#F2453D")
const PAPER_ORANGE := Color("#FF9A5C")
const PAPER_RIB := Color(0, 0, 0, 0.16)
const BRASS := Color("#FFC93C")
const SKY_LANTERN := Color("#FF8A4A")
const SKY_LANTERN_GLOW := Color("#FFC27A")
const SKY_LANTERN_FLAME := Color("#FFF0C2")
const PAGODA := Color("#2A1238")
const PAGODA_ROOF := Color("#A63A52")
const PAGODA_WINDOW := Color("#FFB86B")
const TREE := Color("#2A1238")
const BRIDGE := Color("#C4473A")
const BAMBOO := Color("#2F6B4F")
const BAMBOO_DARK := Color("#27593F")
const BAMBOO_JOINT := Color("#1D4A38")


static func paint(pen: ScenePen, t: ThemeDef) -> void:
	var far := SceneGround.new(506, 16, 0.9, 2.2, t.hill_far, 0)
	var mid := SceneGround.new(556, 11, 1.3, 0.6, t.hill_mid, 1)
	var near := SceneGround.new(602, 6, 1.2, 3.4, t.hill_near, 2)
	SceneProps.night_stars(pen, 23, 34, 300, Vector3(286, 236, 52))
	SceneProps.sun(pen, 286, 236, 28, t)
	# The string of lanterns sags between the two top corners.
	var from := Vector2(30, 44)
	var sag := Vector2(180, 86)
	var to := Vector2(330, 44)
	pen.stroke(ScenePath.at(from.x, from.y).q(sag.x, sag.y, to.x, to.y).done(), STRING, 1.6)
	var along := [0.1, 0.26, 0.42, 0.58, 0.74, 0.9]
	for i in along.size():
		var k: float = along[i]
		var at := from.lerp(sag, k).lerp(sag.lerp(to, k), k)
		_paper_lantern(pen, at.x, at.y + 1, 0.62, PAPER_ORANGE if i % 2 == 1 else PAPER_RED)
	# Sky lanterns: (x, y, size), all clear of the wall spikes.
	for d: Vector3 in [
		Vector3(58, 306, 1),
		Vector3(88, 392, 0.7),
		Vector3(44, 440, 0.55),
		Vector3(312, 338, 0.8),
		Vector3(284, 430, 0.6),
		Vector3(320, 286, 0.5),
		Vector3(248, 470, 0.5),
		Vector3(124, 462, 0.45),
		Vector3(196, 444, 0.4),
	]:
		_sky_lantern(pen, d.x, d.y, d.z)
	far.paint(pen)
	_pagoda(pen, 112, far.y(112) + 3, 1.1)
	for x: float in [40.0, 60.0, 170.0, 300.0, 322.0]:
		SceneProps.p_round(pen, x, far.y(x) + 2, far.scale(), TREE)
	mid.paint(pen)
	_bridge(pen, mid, 198, 276)
	for x: float in [150.0, 310.0]:
		SceneProps.p_pine(pen, x, mid.y(x) + 2, mid.scale(), t.prop)
	near.paint(pen)
	_bamboo(pen, 42, near.y(42) + 2, 150, BAMBOO)
	_bamboo(pen, 56, near.y(56) + 2, 104, BAMBOO_DARK)
	_bamboo(pen, 320, near.y(320) + 2, 128, BAMBOO)
	# A lantern on a post.
	var post := near.y(118)
	pen.line(118, post + 2, 118, post - 26, STRING, 2.4)
	_paper_lantern(pen, 118, post - 24, 0.8, PAPER_RED)


## A round paper lantern hanging from (x, y): brass caps, two ribs, a tassel.
static func _paper_lantern(pen: ScenePen, x: float, y: float, s: float, col: Color) -> void:
	pen.push(ScenePen.place(x, y, 0.0, s, s))
	pen.rect(-3, -2, 6, 3, BRASS)
	pen.ellipse(Vector2(0, 9), 9, 8.5, col)
	pen.stroke(ScenePath.at(-4, 1.5).q(-7, 9, -4, 16.5).done(), PAPER_RIB, 1.4, false)
	pen.stroke(ScenePath.at(4, 1.5).q(7, 9, 4, 16.5).done(), PAPER_RIB, 1.4, false)
	pen.rect(-3, 17, 6, 2.6, BRASS)
	pen.line(0, 19.6, 0, 25, BRASS, 1.6)
	pen.pop()


## A sky lantern centred on (x, y): a paper bag, lit from below.
static func _sky_lantern(pen: ScenePen, x: float, y: float, s: float) -> void:
	pen.push(ScenePen.place(x, y, 0.0, s, s))
	pen.fill(ScenePath.at(-7, -10).q(0, -13, 7, -10).l(9, 8).l(-9, 8).done(), SKY_LANTERN)
	pen.fill(
		PackedVector2Array([Vector2(-8.2, 1), Vector2(8.2, 1), Vector2(9, 8), Vector2(-9, 8)]),
		SKY_LANTERN_GLOW
	)
	pen.rect(-2, 3, 4, 4, SKY_LANTERN_FLAME, 2)
	pen.pop()


## A three-storey pagoda with upturned roofs, lit windows and a spire.
static func _pagoda(pen: ScenePen, x: float, b: float, s: float) -> void:
	pen.push(ScenePen.place(x, b, 0.0, s, s))
	var y := 0.0
	# Storeys from the ground up: (half width, height).
	var storeys := [Vector2(15, 15), Vector2(11.5, 13), Vector2(8.5, 12)]
	for k in storeys.size():
		var w: float = storeys[k].x
		var h: float = storeys[k].y
		pen.rect(-w, y - h, w * 2, h + 1, PAGODA)
		pen.rect(-2.2, y - h + 4, 4.4, 8.0 if k == 0 else 5.0, PAGODA_WINDOW, 1.2)
		if k == 0:
			pen.rect(-10, y - h + 5, 3.4, 4.6, PAGODA_WINDOW, 1)
			pen.rect(6.6, y - h + 5, 3.4, 4.6, PAGODA_WINDOW, 1)
		y -= h
		var roof := ScenePath.at(-w - 9, y + 1.5).q(-w - 3, y, -w + 1, y - 6).h(w - 1)
		pen.fill(roof.q(w + 3, y, w + 9, y + 1.5).done(), PAGODA_ROOF)
		y -= 6
	pen.line(0, y, 0, y - 12, PAGODA_ROOF, 2)
	pen.circle(Vector2(0, y - 6), 2, BRASS)
	pen.pop()


## An arched bridge over the ground from x0 to x1, with a handrail on posts.
static func _bridge(pen: ScenePen, g: SceneGround, x0: float, x1: float) -> void:
	var a := Vector2(x0, g.y(x0) + 2)
	var b := Vector2(x1, g.y(x1) + 2)
	var top := Vector2((x0 + x1) / 2.0, minf(a.y, b.y) - 26)
	var up := Vector2(0, -10)
	pen.stroke(ScenePath.at(a.x, a.y).q(top.x, top.y, b.x, b.y).done(), BRIDGE, 6)
	var rail := ScenePath.at(a.x, a.y - 10).q(top.x, top.y - 10, b.x, b.y - 10)
	pen.stroke(rail.done(), BRIDGE, 2.4)
	for k: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var p := a.lerp(top, k).lerp(top.lerp(b, k), k)
		pen.line(p.x, p.y, p.x + up.x, p.y + up.y - 2, BRIDGE, 2.6)


## A bamboo stalk `length` tall with joints and three leaves.
static func _bamboo(pen: ScenePen, x: float, b: float, length: float, col: Color) -> void:
	pen.line(x, b, x, b - length, col, 4.5)
	var y := b - 22
	while y > b - length:
		pen.stroke(PackedVector2Array([Vector2(x - 3, y), Vector2(x + 3, y)]), BAMBOO_JOINT, 1.6)
		y -= 24
	# Leaves: (how far up, which side).
	for d: Vector2 in [Vector2(0.55, 1), Vector2(0.75, -1), Vector2(0.95, 1)]:
		pen.ellipse(Vector2(x + d.y * 9, b - length * d.x - 3), 9, 2.8, col, d.y * -24)
