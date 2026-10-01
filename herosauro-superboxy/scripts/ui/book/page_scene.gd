class_name PageScene
extends Control
## A picture-book illustration drawn in code, for every page whose painted art
## is not in the repository yet (the owner's book pages live in Drive).
##
## It has to look intentional rather than like a placeholder, so each chapter
## gets its own place, drawn the way a picture book would simplify it:
##   adamastor  Porto by day: the Douro, the D. Luís bridge's arch, Ribeira
##              houses climbing the bank, a granite quay in front
##   dragao     the Estádio do Dragão at night: moon, stars, floodlights
##              pouring light onto a striped pitch
##   pandas     an old Porto street at sunset: tall narrow houses, azulejos,
##              balconies; tired and cracked before, lit up and magical after
## plus the story's props for the page (cups, goblins, the dragon, pandas,
## suitcases, the van, splashes, fire, sparkles).
##
## Everything is drawn in a fixed 1600x900 design space; the owner of this
## node scales it to cover its rect. The ground line every character stands on
## is GROUND_Y. Randomness is seeded per page (ARCHITECTURE.md rule 4).

const DESIGN := Vector2(1600.0, 900.0)
const GROUND_Y := 620.0
const INK := Color(0.10, 0.07, 0.10, 0.92)
const LINE := 5.0

var chapter_id: String = "adamastor"
## "intro" or "outro": the pandas street is shabby before and magical after.
var part: String = "intro"
## Prop ids for this page; see _draw_prop().
var props: Array = []
var seed_value: int = 1
## False for an overlay that only draws props in front of the characters.
var backdrop := true

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = DESIGN
	custom_minimum_size = DESIGN


func configure(chapter: String, which_part: String, page_props: Array, page_seed: int) -> void:
	chapter_id = chapter
	part = which_part
	props = page_props
	seed_value = page_seed
	queue_redraw()


## Scale and offset that make DESIGN cover `rect_size`, cropping the long axis.
static func cover_transform(rect_size: Vector2) -> Array:
	var k := maxf(rect_size.x / DESIGN.x, rect_size.y / DESIGN.y)
	var off := (rect_size - DESIGN * k) * 0.5
	return [k, off]


func _draw() -> void:
	_rng.seed = 0x5EED0000 + seed_value
	if not backdrop:
		for p in props:
			_draw_prop(str(p))
		return
	match chapter_id:
		"dragao":
			_draw_stadium()
		"pandas":
			_draw_street()
		_:
			_draw_douro()
	for p in props:
		_draw_prop(str(p))


# --- Shared helpers ------------------------------------------------------------

func _vgrad(top: float, bottom: float, c0: Color, c1: Color, x0: float = 0.0,
		x1: float = DESIGN.x) -> void:
	draw_polygon(PackedVector2Array([Vector2(x0, top), Vector2(x1, top),
		Vector2(x1, bottom), Vector2(x0, bottom)]),
		PackedColorArray([c0, c0, c1, c1]))


func _poly(pts: PackedVector2Array, fill: Color, outline: float = LINE) -> void:
	draw_colored_polygon(pts, fill)
	if outline > 0.0:
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, INK, outline, true)


func _ellipse_pts(c: Vector2, rx: float, ry: float, n: int = 32, a0: float = 0.0,
		a1: float = TAU) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _ellipse(c: Vector2, rx: float, ry: float, fill: Color, outline: float = LINE) -> void:
	var pts := _ellipse_pts(c, rx, ry, 36)
	pts.remove_at(pts.size() - 1)
	_poly(pts, fill, outline)


func _disc(c: Vector2, r: float, fill: Color, outline: float = LINE) -> void:
	if outline > 0.0:
		draw_circle(c, r + outline * 0.5, INK)
	draw_circle(c, r - (outline * 0.5 if outline > 0.0 else 0.0), fill)


func _rrect(x: float, y: float, w: float, h: float, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var cs := [Vector2(x + w - r, y + r), Vector2(x + w - r, y + h - r),
		Vector2(x + r, y + h - r), Vector2(x + r, y + r)]
	for i in 4:
		var a0 := -PI * 0.5 + i * PI * 0.5
		for k in 6:
			var a := a0 + k * (PI * 0.5) / 5.0
			pts.append(cs[i] + Vector2(cos(a), sin(a)) * r)
	return pts


func _cloud(c: Vector2, k: float, tint: Color = Color.WHITE) -> void:
	var puffs := [[-70, 10, 46], [-20, -18, 60], [40, -6, 52], [90, 14, 38], [10, 22, 50]]
	for p in puffs:
		draw_circle(c + Vector2(p[0], p[1] + 8) * k, (p[2] + 4) * k, Color(0.55, 0.65, 0.85, 0.35))
	for p in puffs:
		draw_circle(c + Vector2(p[0], p[1]) * k, p[2] * k, tint)


func _sparkle(c: Vector2, r: float, col: Color = Color("fff3a8")) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := -PI * 0.5 + i * PI / 4.0
		var rr := r if i % 2 == 0 else r * 0.28
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	_poly(pts, col, 3.0)


## A row of cobbles: the ground every Porto scene stands on.
func _cobbles(top: float, base: Color) -> void:
	_vgrad(top, DESIGN.y, base.lightened(0.08), base.darkened(0.25))
	draw_line(Vector2(0, top), Vector2(DESIGN.x, top), INK, LINE, true)
	var row := 0
	var y := top + 18.0
	while y < DESIGN.y + 30.0:
		var h := 14.0 + (y - top) * 0.07
		var w := 34.0 + (y - top) * 0.16
		var x := -w * 0.5 if row % 2 == 0 else 0.0
		while x < DESIGN.x + w:
			var shade := base.lerp(base.darkened(0.3), _rng.randf() * 0.5)
			var pts := _ellipse_pts(Vector2(x + w * 0.5, y), w * 0.44, h * 0.42, 12)
			draw_colored_polygon(pts, shade)
			draw_polyline(pts, Color(0, 0, 0, 0.18), 2.0, true)
			x += w
		y += h * 1.05
		row += 1


# --- Chapter 1: the Douro by day ----------------------------------------------------

func _draw_douro() -> void:
	_vgrad(0, 520, Color("3a86d8"), Color("bfe6ff"))
	# Sun with soft rings.
	for i in 4:
		draw_circle(Vector2(1360, 150), 150.0 - i * 28.0, Color(1.0, 0.95, 0.6, 0.10 + i * 0.05))
	_disc(Vector2(1360, 150), 62, Color("ffe066"), 0.0)
	_cloud(Vector2(260, 150), 1.1)
	_cloud(Vector2(820, 95), 0.8)
	_cloud(Vector2(1100, 250), 0.7)

	# The banks: Gaia on the left, Ribeira on the right, houses climbing both.
	_bank(true)
	_bank(false)
	# River.
	_vgrad(500, GROUND_Y, Color("2a8fb5"), Color("1d6a8c"))
	for i in 22:
		var x := _rng.randf_range(0, DESIGN.x)
		var y := _rng.randf_range(515, GROUND_Y - 12)
		draw_arc(Vector2(x, y), _rng.randf_range(14, 30), PI * 1.15, PI * 1.85, 8,
			Color(1, 1, 1, 0.55), 3.0, true)
	_bridge()
	# Rabelo boat.
	if not props.has("splash"):
		_rabelo(Vector2(1220, 575))
	# The granite quay the heroes stand on.
	_cobbles(GROUND_Y, Color("b9b2a6"))


func _bank(left: bool) -> void:
	var base := Color("6aa86b") if left else Color("7fae6a")
	var pts := PackedVector2Array()
	if left:
		pts = PackedVector2Array([Vector2(0, 250), Vector2(220, 300), Vector2(430, 420),
			Vector2(520, 510), Vector2(0, 510)])
	else:
		pts = PackedVector2Array([Vector2(1600, 210), Vector2(1380, 260), Vector2(1180, 380),
			Vector2(1080, 510), Vector2(1600, 510)])
	_poly(pts, base, 0.0)
	var colours := [Color("f4c95d"), Color("f28b82"), Color("ffffff"), Color("8ec5ff"),
		Color("ffb26b"), Color("e8e0cf")]
	var xs := range(0, 470, 52) if left else range(1130, 1600, 52)
	for x0 in xs:
		var x := float(x0)
		# Height of the bank at this x, so houses sit on the slope.
		var t := (x / 470.0) if left else ((1600.0 - x) / 470.0)
		var top := lerpf(270.0, 470.0, t) + _rng.randf_range(-12, 12)
		var h := _rng.randf_range(70, 110)
		var w := _rng.randf_range(40, 54)
		var c: Color = colours[_rng.randi_range(0, colours.size() - 1)]
		_poly(PackedVector2Array([Vector2(x, top), Vector2(x + w, top), Vector2(x + w, top + h),
			Vector2(x, top + h)]), c.lerp(Color("bcd7ea"), 0.18), 3.0)
		_poly(PackedVector2Array([Vector2(x - 4, top), Vector2(x + w * 0.5, top - 18),
			Vector2(x + w + 4, top)]), Color("d0623b"), 3.0)
		for wy in [top + 18, top + 46]:
			draw_rect(Rect2(x + 8, wy, 10, 14), Color("2b4a6b"))
			draw_rect(Rect2(x + w - 18, wy, 10, 14), Color("2b4a6b"))


func _bridge() -> void:
	var iron := Color("3e4957")
	var deck_y := 236.0
	var left := 400.0
	var right := 1480.0
	var foot := 515.0
	var apex := deck_y + 18.0
	var mid := (left + right) * 0.5
	var half := (right - left) * 0.5
	# Twin arch curves (the lattice is between them).
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in 41:
		var t := float(i) / 40.0
		var x := lerpf(left, right, t)
		var u := (x - mid) / half
		outer.append(Vector2(x, apex + (foot - apex) * u * u))
		inner.append(Vector2(x, apex + 34.0 + (foot - apex - 34.0) * u * u))
	draw_polyline(outer, INK, 22.0, true)
	draw_polyline(outer, iron, 15.0, true)
	draw_polyline(inner, INK, 16.0, true)
	draw_polyline(inner, iron, 9.0, true)
	for i in range(0, 41, 2):
		draw_line(outer[i], inner[mini(i + 2, 40)], iron, 4.0, true)
		draw_line(inner[i], outer[mini(i + 2, 40)], iron, 4.0, true)
	# Columns from the arch up to the top deck.
	for i in range(2, 40, 4):
		var p := outer[i]
		if p.y > deck_y + 8.0:
			draw_line(Vector2(p.x, deck_y), p, INK, 9.0, true)
			draw_line(Vector2(p.x, deck_y), p, iron, 5.0, true)
	# Top deck, end towers.
	_poly(PackedVector2Array([Vector2(left - 120, deck_y - 16), Vector2(right + 120, deck_y - 16),
		Vector2(right + 120, deck_y + 6), Vector2(left - 120, deck_y + 6)]), iron)
	for x in [left - 40.0, right + 10.0]:
		_poly(PackedVector2Array([Vector2(x, deck_y + 6), Vector2(x + 30, deck_y + 6),
			Vector2(x + 40, foot), Vector2(x - 10, foot)]), Color("8c8478"))
	# Lower deck across the river.
	_poly(PackedVector2Array([Vector2(left - 20, 470), Vector2(right + 20, 470),
		Vector2(right + 20, 486), Vector2(left - 20, 486)]), iron)


func _rabelo(c: Vector2) -> void:
	_poly(PackedVector2Array([c + Vector2(-110, -10), c + Vector2(110, -10), c + Vector2(80, 26),
		c + Vector2(-90, 26)]), Color("7a4a2a"))
	for i in 4:
		_ellipse(c + Vector2(-60 + i * 36, -24), 15, 13, Color("a0683d"), 3.0)
	draw_line(c + Vector2(20, -10), c + Vector2(20, -120), INK, 6.0, true)
	_poly(PackedVector2Array([c + Vector2(24, -112), c + Vector2(90, -40), c + Vector2(24, -36)]),
		Color("f4ecd8"), 3.0)


# --- Chapter 2: the stadium at night -------------------------------------------------

func _draw_stadium() -> void:
	_vgrad(0, 560, Color("0b1640"), Color("2b4594"))
	for i in 70:
		var p := Vector2(_rng.randf_range(0, DESIGN.x), _rng.randf_range(0, 330))
		var r := _rng.randf_range(1.5, 3.6)
		draw_circle(p, r, Color(1, 1, 0.9, _rng.randf_range(0.5, 1.0)))
	# Moon.
	for i in 4:
		draw_circle(Vector2(290, 160), 140.0 - i * 22.0, Color(0.85, 0.9, 1.0, 0.06 + i * 0.03))
	_disc(Vector2(290, 160), 78, Color("fff6d2"), 0.0)
	for cr in [[Vector2(265, 140), 14.0], [Vector2(320, 185), 10.0], [Vector2(300, 125), 7.0]]:
		draw_circle(cr[0], cr[1], Color("efe2b4"))
	# The bowl: dark stands, a lit rim, rows of blue seats.
	var top := PackedVector2Array()
	for i in 41:
		var x := lerpf(-40, DESIGN.x + 40, float(i) / 40.0)
		var u := (x - 800.0) / 840.0
		top.append(Vector2(x, 330.0 + 70.0 * u * u))
	var stands := top.duplicate()
	stands.append(Vector2(DESIGN.x + 40, 580))
	stands.append(Vector2(-40, 580))
	_poly(stands, Color("16245a"), 0.0)
	for row in 6:
		var band := PackedVector2Array()
		for p in top:
			band.append(p + Vector2(0, 40 + row * 34))
		draw_polyline(band, Color("2f6fd6") if row % 2 == 0 else Color("e9f1ff", 0.55), 9.0, true)
	draw_polyline(top, Color("9fc3ff"), 8.0, true)
	draw_polyline(top, INK, 3.0, true)
	# Floodlights and their cones.
	for fx in [180.0, 620.0, 980.0, 1420.0]:
		var head := Vector2(fx, 150.0 + absf(fx - 800.0) * 0.06)
		draw_colored_polygon(PackedVector2Array([head + Vector2(-30, 20), head + Vector2(30, 20),
			Vector2(fx + 260 * signf(800 - fx) + 160, GROUND_Y + 60),
			Vector2(fx + 260 * signf(800 - fx) - 160, GROUND_Y + 60)]), Color(1, 1, 0.85, 0.10))
		draw_line(head, Vector2(fx, 340), INK, 12.0, true)
		draw_line(head, Vector2(fx, 340), Color("6f7f99"), 6.0, true)
		_poly(_rrect(head.x - 44, head.y - 22, 88, 42, 8), Color("dde6f5"), 4.0)
		for k in 4:
			draw_circle(head + Vector2(-30 + k * 20, -1), 7, Color("fffbe0"))
	# The pitch, striped, with its markings.
	_vgrad(560, DESIGN.y, Color("3fa34d"), Color("2a7f3a"))
	for i in 9:
		if i % 2 == 0:
			var x0 := -200.0 + i * 220.0
			draw_colored_polygon(PackedVector2Array([Vector2(x0 + 60, 560), Vector2(x0 + 170, 560),
				Vector2(x0 + 260, DESIGN.y), Vector2(x0 + 30, DESIGN.y)]), Color(1, 1, 1, 0.07))
	draw_line(Vector2(0, 560), Vector2(DESIGN.x, 560), INK, 4.0, true)
	draw_polyline(_ellipse_pts(Vector2(800, 730), 230, 70, 40), Color(1, 1, 1, 0.75), 6.0, true)
	draw_line(Vector2(800, 562), Vector2(800, DESIGN.y), Color(1, 1, 1, 0.75), 6.0, true)


# --- Chapter 3: a Porto street at sunset ------------------------------------------------

func _draw_street() -> void:
	var magic := part == "outro"
	var sky_top := Color("3b2f7a") if magic else Color("6c4fb5")
	_vgrad(0, 300, sky_top, Color("ff8e6e"))
	_vgrad(300, 560, Color("ff8e6e"), Color("ffd27a"))
	for i in 5:
		draw_circle(Vector2(1180, 420), 190.0 - i * 30.0, Color(1.0, 0.85, 0.4, 0.07 + i * 0.04))
	_disc(Vector2(1180, 420), 96, Color("ffcf55"), 0.0)
	if magic:
		for i in 40:
			draw_circle(Vector2(_rng.randf_range(0, DESIGN.x), _rng.randf_range(0, 200)),
				_rng.randf_range(1.5, 3.2), Color(1, 1, 0.9, 0.8))
	var palette := [Color("2f6db5"), Color("f2c14e"), Color("f28b9b"), Color("5bb57a"),
		Color("f6efe1"), Color("e8774a")]
	var x := -30.0
	var i := 0
	while x < DESIGN.x:
		var w := _rng.randf_range(170, 220)
		var h := _rng.randf_range(300, 420)
		_house(x, GROUND_Y - h, w, h, palette[i % palette.size()], magic)
		x += w - 2.0
		i += 1
	if magic:
		_string_lights()
	_cobbles(GROUND_Y, Color("a9a097"))


func _house(x: float, y: float, w: float, h: float, base: Color, magic: bool) -> void:
	var c := base if magic else base.lerp(Color("9a8f86"), 0.45)
	_poly(PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, GROUND_Y),
		Vector2(x, GROUND_Y)]), c)
	# Azulejo tiles on blue houses.
	if base == Color("2f6db5"):
		for ty in range(int(y) + 12, int(GROUND_Y) - 10, 22):
			for tx in range(int(x) + 8, int(x + w) - 10, 22):
				if (tx + ty) % 44 < 22:
					draw_rect(Rect2(tx, ty, 16, 16), Color(1, 1, 1, 0.22 if magic else 0.12))
	# Roof.
	_poly(PackedVector2Array([Vector2(x - 8, y), Vector2(x + w * 0.5, y - 46),
		Vector2(x + w + 8, y)]), Color("c95a33") if magic else Color("8b5a45"))
	# Windows and balconies, two columns.
	var rows := int((GROUND_Y - y - 120) / 100.0)
	for r in rows:
		for col in 2:
			var wx := x + w * (0.22 if col == 0 else 0.60)
			var wy := y + 34 + r * 100
			var win := Color("ffe9a8") if magic else Color("38404f")
			_poly(_rrect(wx, wy, w * 0.18, 56, 8), win, 4.0)
			if not magic and _rng.randf() < 0.35:
				# Boarded window: two planks.
				draw_line(Vector2(wx - 4, wy + 14), Vector2(wx + w * 0.18 + 4, wy + 30),
					Color("8a6a46"), 9.0, true)
				draw_line(Vector2(wx - 4, wy + 38), Vector2(wx + w * 0.18 + 4, wy + 24),
					Color("8a6a46"), 9.0, true)
			draw_line(Vector2(wx - 8, wy + 60), Vector2(wx + w * 0.18 + 8, wy + 60), INK, 5.0, true)
			if magic:
				for f in 3:
					draw_circle(Vector2(wx + 6 + f * w * 0.06, wy + 58), 7,
						[Color("ff6fa8"), Color("ffd84d"), Color("ff8a3c")][f])
	# Door.
	_poly(_rrect(x + w * 0.38, GROUND_Y - 110, w * 0.24, 110, 14),
		Color("6b3f2a") if magic else Color("5a4a40"), 4.0)
	if not magic:
		# A crack down the plaster.
		draw_polyline(PackedVector2Array([Vector2(x + w * 0.8, y + 20), Vector2(x + w * 0.74, y + 70),
			Vector2(x + w * 0.82, y + 110), Vector2(x + w * 0.76, y + 160)]), INK, 3.0, true)


func _string_lights() -> void:
	var pts := PackedVector2Array()
	for i in 41:
		var t := float(i) / 40.0
		pts.append(Vector2(lerpf(-20, DESIGN.x + 20, t), 210.0 + 80.0 * sin(t * PI * 3.0) ** 2))
	draw_polyline(pts, INK, 3.0, true)
	var cols := [Color("ff6fa8"), Color("ffd84d"), Color("6fe3ff"), Color("8cff8a")]
	for i in range(1, 40, 2):
		draw_circle(pts[i] + Vector2(0, 10), 13, Color(cols[i % 4], 0.35))
		_disc(pts[i] + Vector2(0, 10), 7, cols[i % 4], 3.0)


# --- Props ---------------------------------------------------------------------------------

func _draw_prop(id: String) -> void:
	match id:
		"cups":
			_trophy(Vector2(640, 600), 1.0)
			_trophy(Vector2(800, 610), 1.25)
			_trophy(Vector2(960, 600), 1.0)
		"cup_pair":
			_trophy(Vector2(1180, 610), 1.1)
			_trophy(Vector2(1330, 610), 1.1)
		"goblins":
			_goblin(Vector2(1120, GROUND_Y + 40), 1.0, Color("e8402e"), false)
			_goblin(Vector2(1320, GROUND_Y + 50), 0.9, Color("2e9e57"), true)
			_goblin(Vector2(1480, GROUND_Y + 30), 0.8, Color("e8402e"), false)
		"goblin_chief":
			_goblin(Vector2(1150, GROUND_Y + 60), 1.5, Color("e8402e"), false)
		"goblin_sack":
			_goblin(Vector2(1250, GROUND_Y + 40), 1.0, Color("2e9e57"), true)
			_poly(_ellipse_pts(Vector2(1380, GROUND_Y - 30), 70, 80, 24), Color("c9a46a"))
			_trophy(Vector2(1380, GROUND_Y - 110), 0.6)
		"dragon_sleep":
			_dragon(Vector2(520, GROUND_Y + 30), 1.0, true, false)
		"dragon":
			_dragon(Vector2(520, GROUND_Y + 30), 1.0, false, false)
		"dragon_tied":
			_dragon(Vector2(520, GROUND_Y + 30), 1.0, false, true)
		"dragon_happy":
			_dragon(Vector2(1260, GROUND_Y + 30), 0.85, false, false)
		"van":
			_van(Vector2(1180, GROUND_Y + 10))
		"fire":
			for k in 5:
				_flame(Vector2(1080 + k * 50, GROUND_Y - 80 - (k % 2) * 30), 1.0 + (k % 3) * 0.25)
		"signals":
			_signal(Vector2(1050, 170), Color("5ed65c"))
			_signal(Vector2(1350, 230), Color("f2564a"))
		"splash":
			_splash(Vector2(1150, 560), 1.4)
		"splashes":
			_splash(Vector2(900, 560), 0.9)
			_splash(Vector2(1250, 560), 1.1)
		"pandas":
			_panda(Vector2(1000, GROUND_Y + 40), 1.0, true)
			_panda(Vector2(1160, GROUND_Y + 40), 0.95, true)
			_panda(Vector2(1300, GROUND_Y + 50), 0.6, true)
			_panda(Vector2(1400, GROUND_Y + 50), 0.55, true)
		"pandas_sad":
			_panda(Vector2(1000, GROUND_Y + 40), 1.0, false)
			_panda(Vector2(1160, GROUND_Y + 40), 0.95, false)
			_panda(Vector2(1300, GROUND_Y + 50), 0.6, false)
			_panda(Vector2(1400, GROUND_Y + 50), 0.55, false)
		"suitcases":
			_suitcase(Vector2(880, GROUND_Y + 50), Color("f2564a"))
			_suitcase(Vector2(1480, GROUND_Y + 60), Color("3fa9f5"))
		"nata":
			_nata(Vector2(860, GROUND_Y - 10))
		"icecream":
			_icecream(Vector2(1240, GROUND_Y - 150))
		"sparkles":
			for k in 9:
				_sparkle(Vector2(_rng.randf_range(120, 1500), _rng.randf_range(80, 420)),
					_rng.randf_range(16, 34))
		"window":
			_window_frame()


func _trophy(base: Vector2, k: float) -> void:
	var gold := Color("ffc63d")
	var deep := Color("e0952a")
	var cup := PackedVector2Array()
	for i in 21:
		var a := float(i) / 20.0 * PI
		cup.append(base + Vector2(cos(a) * 46, -150 + sin(a) * 60) * k)
	cup.append(base + Vector2(-46, -150) * k)
	draw_arc(base + Vector2(-50, -125) * k, 30 * k, PI * 0.5, PI * 1.5, 14, INK, 13 * k, true)
	draw_arc(base + Vector2(-50, -125) * k, 30 * k, PI * 0.5, PI * 1.5, 14, deep, 7 * k, true)
	draw_arc(base + Vector2(50, -125) * k, 30 * k, -PI * 0.5, PI * 0.5, 14, INK, 13 * k, true)
	draw_arc(base + Vector2(50, -125) * k, 30 * k, -PI * 0.5, PI * 0.5, 14, deep, 7 * k, true)
	_poly(cup, gold)
	_poly(PackedVector2Array([base + Vector2(-10, -92) * k, base + Vector2(10, -92) * k,
		base + Vector2(16, -40) * k, base + Vector2(-16, -40) * k]), deep)
	_poly(_rrect(base.x - 40 * k, base.y - 42 * k, 80 * k, 42 * k, 8 * k), Color("6b4a2a"))
	draw_line(base + Vector2(-26, -140) * k, base + Vector2(-14, -110) * k, Color(1, 1, 0.9, 0.9), 6 * k, true)


func _goblin(feet: Vector2, k: float, shirt: Color, stripes: bool) -> void:
	var skin := Color("8fd14f")
	_poly(_rrect(feet.x - 44 * k, feet.y - 120 * k, 88 * k, 110 * k, 34 * k), shirt)
	if stripes:
		for s in 3:
			draw_rect(Rect2(feet.x - 40 * k, feet.y - 100 * k + s * 30 * k, 80 * k, 12 * k), Color(1, 1, 1, 0.85))
	var head := feet + Vector2(0, -170) * k
	_poly(PackedVector2Array([head + Vector2(-50, -10) * k, head + Vector2(-110, -40) * k,
		head + Vector2(-58, 22) * k]), skin)
	_poly(PackedVector2Array([head + Vector2(50, -10) * k, head + Vector2(110, -40) * k,
		head + Vector2(58, 22) * k]), skin)
	_ellipse(head, 62 * k, 56 * k, skin)
	for side in [-1.0, 1.0]:
		_disc(head + Vector2(22 * side, -12) * k, 15 * k, Color.WHITE, 3.0)
		draw_circle(head + Vector2(22 * side + 4, -10) * k, 7 * k, INK)
	var grin := _ellipse_pts(head + Vector2(0, 18) * k, 32 * k, 20 * k, 16, 0.15, PI - 0.15)
	draw_colored_polygon(grin, Color("7a1f2b"))
	draw_polyline(grin, INK, 4.0, true)
	draw_rect(Rect2(head.x - 12 * k, head.y + 18 * k, 10 * k, 9 * k), Color.WHITE)
	draw_rect(Rect2(head.x + 4 * k, head.y + 18 * k, 10 * k, 9 * k), Color.WHITE)


func _dragon(feet: Vector2, k: float, sleeping: bool, tied: bool) -> void:
	var blue := Color("2f7fe0")
	var belly := Color("bfe3ff")
	# Tail curling round the front.
	var tail := PackedVector2Array()
	for i in 21:
		var t := float(i) / 20.0
		tail.append(feet + Vector2(lerpf(160, 330, t), -20 - sin(t * PI) * 80) * k)
	draw_polyline(tail, INK, 44 * k, true)
	draw_polyline(tail, blue, 34 * k, true)
	_poly(PackedVector2Array([tail[20] + Vector2(-8, -22) * k, tail[20] + Vector2(40, -6) * k,
		tail[20] + Vector2(-6, 18) * k]), Color("ffc63d"))
	# Wing.
	_poly(PackedVector2Array([feet + Vector2(20, -210) * k, feet + Vector2(150, -330) * k,
		feet + Vector2(170, -240) * k, feet + Vector2(220, -260) * k, feet + Vector2(180, -160) * k]),
		Color("5aa2f0"))
	# Body.
	_ellipse(feet + Vector2(60, -110) * k, 180 * k, 115 * k, blue)
	_ellipse(feet + Vector2(40, -80) * k, 110 * k, 70 * k, belly, 3.0)
	# Spikes.
	for s in 5:
		var p := feet + Vector2(-60 + s * 55, -220 + absf(s - 2) * 12) * k
		_poly(PackedVector2Array([p + Vector2(-18, 8) * k, p + Vector2(0, -34) * k,
			p + Vector2(18, 8) * k]), Color("ffc63d"), 4.0)
	# Head.
	var head := feet + Vector2(-150, -170) * k
	_ellipse(head, 92 * k, 74 * k, blue)
	_ellipse(head + Vector2(-70, 22) * k, 58 * k, 40 * k, blue)
	draw_circle(head + Vector2(-100, 14) * k, 7 * k, INK)
	for horn in [-1.0, 1.0]:
		_poly(PackedVector2Array([head + Vector2(10 + horn * 30, -60) * k,
			head + Vector2(30 + horn * 40, -120) * k, head + Vector2(40 + horn * 22, -56) * k]),
			Color("fff1c9"), 4.0)
	if sleeping:
		draw_arc(head + Vector2(-18, -14) * k, 18 * k, 0.2, PI - 0.2, 10, INK, 6.0, true)
		for z in 3:
			var zp := head + Vector2(-60 + z * 40, -130 - z * 46) * k
			draw_string(UIStyle.TITLE_FONT, zp, "z", HORIZONTAL_ALIGNMENT_LEFT, -1,
				int((40 + z * 14) * k), Color("e9f1ff"))
	else:
		_disc(head + Vector2(-18, -18) * k, 20 * k, Color.WHITE, 4.0)
		draw_circle(head + Vector2(-24, -16) * k, 9 * k, INK)
		draw_arc(head + Vector2(-80, 36) * k, 26 * k, 0.3, PI - 0.6, 10, INK, 5.0, true)
	if tied:
		for r in 3:
			var y := -60.0 - r * 60.0
			draw_line(feet + Vector2(-140, y) * k, feet + Vector2(240, y + 30) * k, INK, 16 * k, true)
			draw_line(feet + Vector2(-140, y) * k, feet + Vector2(240, y + 30) * k, Color("c9925a"), 10 * k, true)


func _van(c: Vector2) -> void:
	_poly(_rrect(c.x - 230, c.y - 230, 460, 190, 40), Color("e9e4dc"))
	_poly(_rrect(c.x - 200, c.y - 205, 120, 80, 16), Color("7cc3f0"), 4.0)
	_poly(_rrect(c.x - 60, c.y - 205, 120, 80, 16), Color("7cc3f0"), 4.0)
	_poly(_rrect(c.x + 80, c.y - 205, 110, 80, 16), Color("7cc3f0"), 4.0)
	draw_rect(Rect2(c.x - 230, c.y - 112, 460, 26), Color("6a5acd"))
	# Goblins peeking out of the windows.
	for wx in [c.x - 140, c.x + 0]:
		_ellipse(Vector2(wx, c.y - 150), 30, 26, Color("8fd14f"), 3.0)
		draw_circle(Vector2(wx - 10, c.y - 156), 5, INK)
		draw_circle(Vector2(wx + 10, c.y - 156), 5, INK)
		draw_arc(Vector2(wx, c.y - 146), 12, 0.2, PI - 0.2, 8, INK, 3.0, true)
	for wx in [c.x - 140, c.x + 140]:
		_disc(Vector2(wx, c.y - 36), 40, Color("2a2a33"))
		_disc(Vector2(wx, c.y - 36), 16, Color("b9b9c4"), 3.0)


func _flame(base: Vector2, k: float) -> void:
	var pts := PackedVector2Array()
	for i in 25:
		var t := float(i) / 24.0 * TAU
		var r := 1.0 - 0.55 * maxf(0.0, -sin(t))
		pts.append(base + Vector2(sin(t) * 36 * r, -cos(t) * 60 - 30) * k)
	_poly(pts, Color("ff7a1a"), 4.0)
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(base + (p - base) * 0.55 + Vector2(0, 14) * k)
	draw_colored_polygon(inner, Color("ffd84d"))


func _signal(c: Vector2, tint: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(-60, 40), c + Vector2(60, 40),
		Vector2(c.x + 140, 900), Vector2(c.x - 40, 900)]), Color(1, 1, 0.8, 0.08))
	for i in 3:
		draw_circle(c, 120.0 - i * 26.0, Color(1, 1, 0.8, 0.10 + i * 0.07))
	_disc(c, 62, Color("fffbe0"), 4.0)
	if tint == Color("5ed65c"):
		# A dinosaur head, in profile.
		_poly(PackedVector2Array([c + Vector2(-34, 22), c + Vector2(-30, -20), c + Vector2(0, -34),
			c + Vector2(36, -24), c + Vector2(40, -4), c + Vector2(10, 0), c + Vector2(6, 30)]), tint, 4.0)
		draw_circle(c + Vector2(10, -20), 5, INK)
	else:
		# A boxing glove.
		_ellipse(c + Vector2(6, -4), 34, 30, tint, 4.0)
		_ellipse(c + Vector2(-26, 4), 14, 18, tint, 4.0)
		_poly(_rrect(c.x - 18, c.y + 20, 44, 22, 6), Color.WHITE, 4.0)


func _splash(c: Vector2, k: float) -> void:
	var pts := PackedVector2Array()
	for i in 15:
		var a := PI + float(i) / 14.0 * PI
		var r := 110.0 if i % 2 == 0 else 60.0
		pts.append(c + Vector2(cos(a) * r * 1.3, sin(a) * r) * k)
	pts.append(c + Vector2(130, 30) * k)
	pts.append(c + Vector2(-130, 30) * k)
	_poly(pts, Color("dff4ff"), 5.0)
	for d in 6:
		var a := PI * (1.1 + d * 0.16)
		_disc(c + Vector2(cos(a) * 170, sin(a) * 150) * k, 12 * k, Color("dff4ff"), 3.0)


func _panda(feet: Vector2, k: float, happy: bool) -> void:
	var black := Color("24232a")
	_ellipse(feet + Vector2(0, -80) * k, 70 * k, 82 * k, Color.WHITE)
	for side in [-1.0, 1.0]:
		_ellipse(feet + Vector2(42 * side, -14) * k, 26 * k, 18 * k, black, 3.0)
		_ellipse(feet + Vector2(62 * side, -96) * k, 20 * k, 34 * k, black, 3.0)
	var head := feet + Vector2(0, -196) * k
	for side in [-1.0, 1.0]:
		_disc(head + Vector2(46 * side, -46) * k, 22 * k, black, 3.0)
	_ellipse(head, 66 * k, 58 * k, Color.WHITE)
	for side in [-1.0, 1.0]:
		var eye := head + Vector2(24 * side, -8) * k
		var patch := _ellipse_pts(eye, 17 * k, 23 * k, 16)
		draw_colored_polygon(patch, black)
		draw_circle(eye + Vector2(2 * side, -2) * k, 7 * k, Color.WHITE)
		draw_circle(eye + Vector2(2 * side, -1) * k, 3.5 * k, black)
	_ellipse(head + Vector2(0, 16) * k, 10 * k, 7 * k, black, 0.0)
	if happy:
		draw_arc(head + Vector2(0, 22) * k, 14 * k, 0.3, PI - 0.3, 10, black, 4.0, true)
		for side in [-1.0, 1.0]:
			draw_circle(head + Vector2(42 * side, 18) * k, 9 * k, Color(1.0, 0.5, 0.6, 0.55))
	else:
		draw_arc(head + Vector2(0, 40) * k, 12 * k, PI + 0.5, TAU - 0.5, 10, black, 4.0, true)


func _suitcase(c: Vector2, tint: Color) -> void:
	draw_arc(c + Vector2(0, -112), 22, PI, TAU, 10, INK, 9.0, true)
	_poly(_rrect(c.x - 64, c.y - 112, 128, 100, 16), tint)
	draw_line(c + Vector2(-64, -62), c + Vector2(64, -62), INK, 4.0, true)
	_disc(c + Vector2(-30, -86), 12, Color("ffd84d"), 3.0)
	_poly(_rrect(c.x + 14, c.y - 100, 34, 22, 5), Color.WHITE, 3.0)


func _nata(c: Vector2) -> void:
	_poly(_rrect(c.x - 150, c.y - 20, 300, 36, 14), Color("d9b98a"))
	for i in 3:
		var p := c + Vector2(-90 + i * 90, -40)
		_ellipse(p, 38, 22, Color("e8a24a"), 4.0)
		_ellipse(p + Vector2(0, -4), 28, 14, Color("ffd36b"), 0.0)
		draw_circle(p + Vector2(-8, -8), 6, Color("8a4a1c"))


func _icecream(c: Vector2) -> void:
	_poly(PackedVector2Array([c + Vector2(-34, 0), c + Vector2(34, 0), c + Vector2(0, 110)]),
		Color("e3a85c"))
	_disc(c + Vector2(0, -24), 38, Color("ff9ec4"))
	_disc(c + Vector2(0, -74), 32, Color("fff1c9"))
	draw_circle(c + Vector2(4, -110), 9, Color("e8402e"))


## The boys' window at home: a big frame the night or sunset shows through.
func _window_frame() -> void:
	var wall := Color("f3dcb8")
	draw_rect(Rect2(0, 0, 220, DESIGN.y), wall)
	draw_rect(Rect2(DESIGN.x - 220, 0, 220, DESIGN.y), wall)
	draw_rect(Rect2(0, 0, DESIGN.x, 60), wall)
	draw_rect(Rect2(220, 60, DESIGN.x - 440, GROUND_Y - 100), INK, false, 10.0)
	draw_line(Vector2(800, 60), Vector2(800, GROUND_Y - 40), Color("8a5a36"), 18.0, true)
	draw_line(Vector2(220, 330), Vector2(DESIGN.x - 220, 330), Color("8a5a36"), 14.0, true)
	draw_rect(Rect2(200, GROUND_Y - 40, DESIGN.x - 400, 50), Color("b07a4a"))
	draw_line(Vector2(200, GROUND_Y - 40), Vector2(DESIGN.x - 200, GROUND_Y - 40), INK, 5.0, true)
