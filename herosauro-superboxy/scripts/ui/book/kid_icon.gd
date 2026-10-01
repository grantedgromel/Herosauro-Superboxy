class_name KidIcon
extends Control
## Pictograms drawn in code, for a UI whose players mostly cannot read.
##
## Every button in the storybook frame carries one of these next to (or
## instead of) its word, so a four-year-old can find "next", "settings" or
## "play again" by shape. They are vector: crisp at any size, no texture
## memory, no import step, and they take the kit's ink keyline like every
## other drawn thing in the game.
##
## Drawn in a 100x100 design box, centred and scaled to the control.

enum Kind {
	NEXT, BACK, PLAY, SKIP, PAUSE, GEAR, GLOBE, BOOK, STAR, STAR_EMPTY, ROBOT,
	HEART, SPEAKER, MUSIC, SPEECH, BUBBLE, TURTLE, CLOSE, CHECK, RETRY, PERSON,
	TWO_PEOPLE, INFO, TAP, MINUS, PLUS,
}

const INK := Color(0.016, 0.043, 0.078, 0.96)

var kind: int = Kind.STAR
var fill: Color = Color("fff3df")
## Second colour some icons use (the robot's eyes, the globe's land).
var accent: Color = Color("ffc12b")
var stroke: float = 5.0


static func make(which: int, px: float, main: Color = Color("fff3df"),
		second: Color = Color("ffc12b")) -> KidIcon:
	var ic := KidIcon.new()
	ic.kind = which
	ic.fill = main
	ic.accent = second
	ic.custom_minimum_size = Vector2(px, px)
	ic.size = Vector2(px, px)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ic


func set_kind(which: int) -> void:
	kind = which
	queue_redraw()


func set_fill(c: Color) -> void:
	fill = c
	queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y) / 100.0
	var off := (size - Vector2(100.0, 100.0) * s) * 0.5
	draw_set_transform(off, 0.0, Vector2(s, s))
	# Thinner strokes at small sizes would vanish; thicker ones at big sizes
	# look like a colouring book, which is the look.
	var w := clampf(stroke / maxf(s, 0.01) * 0.62, 3.5, 9.0)
	match kind:
		Kind.NEXT:
			_poly([Vector2(16, 38), Vector2(52, 38), Vector2(52, 16), Vector2(86, 50),
				Vector2(52, 84), Vector2(52, 62), Vector2(16, 62)], fill, w)
		Kind.BACK:
			_poly([Vector2(84, 38), Vector2(48, 38), Vector2(48, 16), Vector2(14, 50),
				Vector2(48, 84), Vector2(48, 62), Vector2(84, 62)], fill, w)
		Kind.PLAY:
			_poly([Vector2(28, 16), Vector2(86, 50), Vector2(28, 84)], fill, w)
		Kind.SKIP:
			_poly([Vector2(12, 22), Vector2(48, 50), Vector2(12, 78)], fill, w)
			_poly([Vector2(46, 22), Vector2(82, 50), Vector2(46, 78)], fill, w)
			_poly([Vector2(82, 22), Vector2(92, 22), Vector2(92, 78), Vector2(82, 78)], fill, w)
		Kind.PAUSE:
			_poly(_rect(24, 18, 18, 64), fill, w)
			_poly(_rect(58, 18, 18, 64), fill, w)
		Kind.GEAR:
			_gear(w)
		Kind.GLOBE:
			_globe(w)
		Kind.BOOK:
			_book(w)
		Kind.STAR:
			_poly(_star(Vector2(50, 53), 44, 19), fill, w)
		Kind.STAR_EMPTY:
			_poly(_star(Vector2(50, 53), 44, 19), Color("e9dcc4"), w)
		Kind.ROBOT:
			_robot(w)
		Kind.HEART:
			_poly(_heart(Vector2(50, 54), 40), fill, w)
		Kind.SPEAKER:
			_speaker(w)
		Kind.MUSIC:
			_music(w)
		Kind.SPEECH:
			_speech(w)
		Kind.BUBBLE:
			_bubble(w)
		Kind.TURTLE:
			_turtle(w)
		Kind.CLOSE:
			_stroke_line(Vector2(24, 24), Vector2(76, 76), 14.0, w)
			_stroke_line(Vector2(76, 24), Vector2(24, 76), 14.0, w)
		Kind.CHECK:
			_stroke_poly([Vector2(18, 52), Vector2(40, 74), Vector2(84, 26)], 14.0, w)
		Kind.RETRY:
			_retry(w)
		Kind.PERSON:
			_person(Vector2(50, 50), 1.0, fill, w)
		Kind.TWO_PEOPLE:
			_person(Vector2(34, 54), 0.82, accent, w)
			_person(Vector2(64, 48), 0.9, fill, w)
		Kind.INFO:
			_circle(Vector2(50, 50), 40, fill, w)
			_circle(Vector2(50, 30), 7, INK, 0.0)
			_poly(_rect(43, 42, 14, 34), INK, 0.0)
		Kind.TAP:
			_tap(w)
		Kind.MINUS:
			_stroke_line(Vector2(22, 50), Vector2(78, 50), 16.0, w)
		Kind.PLUS:
			# Both inks first, then both fills, so the cross has no seam.
			for seg in [[Vector2(22, 50), Vector2(78, 50)], [Vector2(50, 22), Vector2(50, 78)]]:
				draw_line(seg[0], seg[1], INK, 16.0 + w * 2.0, true)
				for v in seg:
					draw_circle(v, (16.0 + w * 2.0) * 0.5, INK)
			for seg in [[Vector2(22, 50), Vector2(78, 50)], [Vector2(50, 22), Vector2(50, 78)]]:
				draw_line(seg[0], seg[1], fill, 16.0, true)
				for v in seg:
					draw_circle(v, 8.0, fill)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- Primitives ---------------------------------------------------------------

func _poly(pts: Array, c: Color, w: float) -> void:
	var p := PackedVector2Array(pts)
	if w <= 0.0:
		draw_colored_polygon(p, c)
		return
	# The keyline is the shape grown by half a stroke, filled in ink, with the
	# shape shrunk by half a stroke filled on top: a solid, even outline at any
	# size, where a thick polyline breaks up into dashes on short segments.
	var outer := Geometry2D.offset_polygon(p, w * 0.5, Geometry2D.JOIN_ROUND)
	for o in outer:
		draw_colored_polygon(o, INK)
		var edge := o.duplicate()
		edge.append(o[0])
		draw_polyline(edge, INK, 1.5, true)
	var inner := Geometry2D.offset_polygon(p, -w * 0.5, Geometry2D.JOIN_ROUND)
	if inner.is_empty():
		draw_colored_polygon(p, c)
	for q in inner:
		draw_colored_polygon(q, c)
		var rim := q.duplicate()
		rim.append(q[0])
		draw_polyline(rim, c, 1.2, true)


func _circle(c: Vector2, r: float, col: Color, w: float) -> void:
	if w > 0.0:
		draw_circle(c, r + w * 0.5, INK)
	draw_circle(c, r - (w * 0.5 if w > 0.0 else 0.0), col)


func _stroke_line(a: Vector2, b: Vector2, thick: float, w: float) -> void:
	_stroke_poly([a, b], thick, w)


## A fat round-capped stroke in `fill`, keylined in ink.
func _stroke_poly(pts: Array, thick: float, w: float) -> void:
	var p := PackedVector2Array(pts)
	draw_polyline(p, INK, thick + w * 2.0, true)
	for v in p:
		draw_circle(v, (thick + w * 2.0) * 0.5, INK)
	draw_polyline(p, fill, thick, true)
	for v in p:
		draw_circle(v, thick * 0.5, fill)


func _rect(x: float, y: float, rw: float, rh: float) -> Array:
	return [Vector2(x, y), Vector2(x + rw, y), Vector2(x + rw, y + rh), Vector2(x, y + rh)]


func _rounded(x: float, y: float, rw: float, rh: float, r: float) -> Array:
	var pts: Array = []
	var corners := [Vector2(x + rw - r, y + r), Vector2(x + rw - r, y + rh - r),
		Vector2(x + r, y + rh - r), Vector2(x + r, y + r)]
	for i in 4:
		var a0 := -PI * 0.5 + i * PI * 0.5
		for k in 5:
			var a := a0 + k * (PI * 0.5) / 4.0
			pts.append(corners[i] + Vector2(cos(a), sin(a)) * r)
	return pts


func _star(c: Vector2, outer: float, inner: float) -> Array:
	var pts: Array = []
	for i in 10:
		var a := -PI * 0.5 + i * PI / 5.0
		var r := outer if i % 2 == 0 else inner
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


func _heart(c: Vector2, r: float) -> Array:
	var pts: Array = []
	for i in 40:
		var t := TAU * i / 40.0
		var x := 16.0 * pow(sin(t), 3)
		var y := -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
		pts.append(c + Vector2(x, y) * (r / 17.0))
	return pts


func _ellipse(c: Vector2, rx: float, ry: float, n: int = 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


# --- Composite icons -------------------------------------------------------------

func _gear(w: float) -> void:
	var pts: Array = []
	var teeth := 8
	for i in teeth:
		var a := TAU * i / teeth
		for k in [[-0.30, 30.0], [-0.17, 44.0], [0.17, 44.0], [0.30, 30.0]]:
			var ang: float = a + float(k[0])
			pts.append(Vector2(50, 50) + Vector2(cos(ang), sin(ang)) * float(k[1]))
	_poly(pts, fill, w)
	_circle(Vector2(50, 50), 13, INK, 0.0)
	_circle(Vector2(50, 50), 7, fill.darkened(0.25), 0.0)


func _globe(w: float) -> void:
	_circle(Vector2(50, 50), 40, Color("3fa9f5"), w)
	# Two blobs of land so it reads as the world, not a ball with lines.
	draw_colored_polygon(PackedVector2Array([Vector2(30, 30), Vector2(44, 24), Vector2(50, 36),
		Vector2(42, 48), Vector2(30, 46), Vector2(24, 38)]), Color("5ed65c"))
	draw_colored_polygon(PackedVector2Array([Vector2(56, 56), Vector2(70, 52), Vector2(76, 64),
		Vector2(66, 78), Vector2(56, 72)]), Color("5ed65c"))
	var lw := w * 0.55
	draw_polyline(_ellipse(Vector2(50, 50), 16, 40), INK, lw, true)
	draw_line(Vector2(10, 50), Vector2(90, 50), INK, lw, true)
	draw_polyline(_ellipse(Vector2(50, 50), 40, 40), INK, w, true)


func _book(w: float) -> void:
	_poly([Vector2(50, 28), Vector2(14, 20), Vector2(14, 76), Vector2(50, 84)], fill, w)
	_poly([Vector2(50, 28), Vector2(86, 20), Vector2(86, 76), Vector2(50, 84)], fill.darkened(0.08), w)
	var lw := w * 0.5
	for i in 3:
		var y := 38.0 + i * 12.0
		draw_line(Vector2(22, y - 4), Vector2(42, y), INK, lw, true)
		draw_line(Vector2(58, y), Vector2(78, y - 4), INK, lw, true)


func _robot(w: float) -> void:
	_stroke_line(Vector2(50, 24), Vector2(50, 12), 4.0, w * 0.6)
	_circle(Vector2(50, 11), 7, accent, w * 0.8)
	_poly(_rounded(16, 24, 68, 56, 16), fill, w)
	_circle(Vector2(36, 48), 9, accent, w * 0.7)
	_circle(Vector2(64, 48), 9, accent, w * 0.7)
	draw_line(Vector2(38, 66), Vector2(62, 66), INK, w, true)
	_poly(_rect(8, 42, 8, 16), fill, w * 0.7)
	_poly(_rect(84, 42, 8, 16), fill, w * 0.7)


func _speaker(w: float) -> void:
	_poly([Vector2(12, 38), Vector2(28, 38), Vector2(50, 18), Vector2(50, 82),
		Vector2(28, 62), Vector2(12, 62)], fill, w)
	draw_arc(Vector2(52, 50), 18, -0.9, 0.9, 12, INK, w, true)
	draw_arc(Vector2(52, 50), 32, -0.9, 0.9, 16, INK, w, true)


func _music(w: float) -> void:
	_poly([Vector2(36, 22), Vector2(82, 12), Vector2(82, 26), Vector2(40, 36)], fill, w)
	_stroke_line(Vector2(38, 26), Vector2(38, 72), 6.0, w * 0.7)
	_stroke_line(Vector2(80, 16), Vector2(80, 62), 6.0, w * 0.7)
	_poly(_ellipse(Vector2(28, 74), 14, 11, 20), fill, w)
	_poly(_ellipse(Vector2(70, 64), 14, 11, 20), fill, w)


func _speech(w: float) -> void:
	# Tail first, body over it, then a patch of fill over the body's keyline
	# where the two meet, so the outline wraps both as one shape.
	_poly([Vector2(24, 62), Vector2(18, 90), Vector2(46, 68)], fill, w)
	_poly(_rounded(8, 12, 84, 60, 24), fill, w)
	draw_colored_polygon(PackedVector2Array([Vector2(26, 64), Vector2(39, 64),
		Vector2(38, 76), Vector2(25, 76)]), fill)
	for i in 3:
		_circle(Vector2(32 + i * 18, 42), 6, INK, 0.0)


func _bubble(w: float) -> void:
	_circle(Vector2(50, 50), 40, Color("cfeaff"), w)
	draw_arc(Vector2(50, 50), 28, PI * 1.05, PI * 1.45, 10, Color(1, 1, 1, 0.95), w * 1.3, true)
	_circle(Vector2(68, 30), 5, Color(1, 1, 1, 0.95), 0.0)


func _turtle(w: float) -> void:
	_circle(Vector2(84, 58), 10, accent, w)
	for x in [26.0, 66.0]:
		_poly(_rounded(x - 7, 60, 14, 18, 6), accent, w * 0.8)
	var shell := PackedVector2Array()
	for i in 17:
		var a := PI + PI * i / 16.0
		shell.append(Vector2(46, 66) + Vector2(cos(a) * 38, sin(a) * 36))
	_poly(Array(shell), fill, w)
	draw_line(Vector2(8, 66), Vector2(84, 66), INK, w, true)
	draw_circle(Vector2(87, 55), 2.6, INK)
	var lw := w * 0.5
	draw_line(Vector2(30, 42), Vector2(62, 42), INK, lw, true)
	draw_line(Vector2(46, 30), Vector2(46, 64), INK, lw, true)


func _retry(w: float) -> void:
	var c := Vector2(50, 52)
	draw_arc(c, 30, -PI * 0.35, PI * 1.45, 28, INK, 14.0 + w * 2.0, true)
	draw_arc(c, 30, -PI * 0.33, PI * 1.43, 28, fill, 14.0, true)
	var tip := c + Vector2(cos(-PI * 0.35), sin(-PI * 0.35)) * 30.0
	_poly([tip + Vector2(-16, -14), tip + Vector2(14, -6), tip + Vector2(-4, 20)], fill, w)


func _person(c: Vector2, k: float, col: Color, w: float) -> void:
	_circle(c + Vector2(0, -18) * k, 15 * k, col, w)
	var body := PackedVector2Array()
	for i in 17:
		var a := PI + PI * i / 16.0
		body.append(c + Vector2(cos(a) * 26 * k, 40 * k + sin(a) * 34 * k))
	_poly(Array(body), col, w)


func _tap(w: float) -> void:
	draw_arc(Vector2(50, 50), 40, 0, TAU, 40, Color(fill, 0.45), w, true)
	draw_arc(Vector2(50, 50), 27, 0, TAU, 32, Color(fill, 0.75), w, true)
	_circle(Vector2(50, 50), 18, fill, w)
