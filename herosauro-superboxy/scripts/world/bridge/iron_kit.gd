class_name BridgeIronKit
extends RefCounted
## Riveted wrought-iron members, built into a MeshBaker.
##
## Everything Seyrig's ironwork is made of reduces to four moves: a FLAT BAR
## between two points (every lattice diagonal, batten and hanger), a SWEPT TUBE
## along a curve (the arch chords and the handrails, which must not show a gap or
## a crease at a joint), a PLATE (gussets, splice covers, hinge cheeks) and a
## LATTICED FRAME (the spandrel columns). They are here rather than inline in
## bridge_ironwork.gd so the arch, the deck girders and the parapet are provably
## the same construction system — which is what makes a bridge read as designed
## rather than assembled.
##
## Two rules the callers rely on:
##
##   * Members are RECTANGULAR, not square. Real lattice bars are flats — wide in
##     the plane of the truss, thin across it — and that is why a lattice reads as
##     a lace of edges from the side and almost vanishes head-on. Every function
##     that draws a member therefore takes a `normal`: the plane the member lies
##     in. Passing a square section is the single fastest way to make this look
##     like scaffolding again.
##
##   * Rivets cannot be modelled at 1 mm on a 94 m arch. What sells them is the
##     PLATE: a gusset at every place members meet, a splice cover every few
##     metres along a chord. Each is one box, 12 triangles, and it does more for
##     the read than another hundred bars would. gusset() and splice() exist to
##     make that cheap to spam.

const MIN_LENGTH := 1e-4


# --- Members ------------------------------------------------------------------

## A flat bar from `from` to `to`: `width` across the run inside the plane,
## `thick` across the plane. `normal` is the plane's normal and is orthogonalised
## against the run, so a caller can hand over a constant axis for a whole truss.
static func bar(b: MeshBaker, from: Vector3, to: Vector3, width: float,
		thick: float, normal: Vector3 = Vector3.BACK) -> void:
	var d := to - from
	var length := d.length()
	if length < MIN_LENGTH:
		return
	b.add_box(Vector3(length, width, thick), Transform3D(_frame(d / length, normal),
			(from + to) * 0.5))


## A rectangular tube swept along a polyline, mitred at every station.
##
## Chords are the one thing that cannot be a chain of boxes: at 15 m of rise the
## bend per bay is enough that abutted boxes leave wedge-shaped gaps on the
## outside of the curve, and a hundred of those twinkling along the arch is the
## first thing an eye catches. Sweeping shares the corner ring between bays, so
## the chord is continuous by construction — and it is 8 triangles a bay against
## a box's 12.
##
##   width  across the rib (Z-ish), height  in the plane of the arch (Y-ish)
static func sweep(b: MeshBaker, points: PackedVector3Array, width: float,
		height: float, cap_ends: bool = true) -> void:
	var n := points.size()
	if n < 2:
		return
	var hw := width * 0.5
	var hh := height * 0.5
	var rings: Array[PackedVector3Array] = []
	for i in n:
		var tangent := _tangent(points, i)
		var side := tangent.cross(Vector3.UP)
		if side.length_squared() < 1e-8:
			side = tangent.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := side.cross(tangent).normalized()
		var p := points[i]
		var ring := PackedVector3Array()
		ring.resize(4)
		ring[0] = p - side * hw - up * hh
		ring[1] = p + side * hw - up * hh
		ring[2] = p + side * hw + up * hh
		ring[3] = p - side * hw + up * hh
		rings.append(ring)

	for i in n - 1:
		var a := rings[i]
		var c := rings[i + 1]
		var run := points[i].distance_to(points[i + 1])
		b.add_quad(a[1], c[1], c[2], a[2], Vector2(run, height))   # +side
		b.add_quad(a[3], c[3], c[0], a[0], Vector2(run, height))   # -side
		b.add_quad(a[2], c[2], c[3], a[3], Vector2(run, width))    # +up
		b.add_quad(a[0], c[0], c[1], a[1], Vector2(run, width))    # -up
	if cap_ends:
		var f := rings[0]
		var l := rings[n - 1]
		b.add_quad(f[0], f[1], f[2], f[3], Vector2(width, height))
		b.add_quad(l[3], l[2], l[1], l[0], Vector2(width, height))


# --- Plates -------------------------------------------------------------------

## A flat plate centred on `at`, lying in the plane whose normal is `normal`,
## with its long axis along `along`. The workhorse behind gussets and cover
## plates.
static func plate(b: MeshBaker, at: Vector3, length: float, width: float,
		thick: float, normal: Vector3 = Vector3.BACK,
		along: Vector3 = Vector3.RIGHT) -> void:
	var dir := along - normal * along.dot(normal)
	if dir.length_squared() < 1e-8:
		dir = normal.cross(Vector3.UP)
		if dir.length_squared() < 1e-8:
			dir = normal.cross(Vector3.RIGHT)
	b.add_box(Vector3(length, width, thick),
			Transform3D(_frame(dir.normalized(), normal), at))


## A gusset at a joint: the stubby plate that in real ironwork carries the rivets
## tying diagonals into a chord. Drawn as a squat plate proud of the members it
## joins, so at any distance the joints read as thickened and riveted rather than
## as bars crossing in mid-air.
static func gusset(b: MeshBaker, at: Vector3, size: float, thick: float,
		normal: Vector3 = Vector3.BACK, along: Vector3 = Vector3.RIGHT) -> void:
	plate(b, at, size, size * 0.72, thick, normal, along)


## A splice cover wrapped around a chord: the joint where two rolled lengths were
## butted and plated over. One oversized short box; from 40 m it is a shadow line
## every few metres down the chord, which is exactly what riveted plate does.
static func splice(b: MeshBaker, at: Vector3, tangent: Vector3, width: float,
		height: float, length: float) -> void:
	b.add_box(Vector3(length, width, height),
			Transform3D(_frame(tangent.normalized(), Vector3.UP), at))


# --- Trusses ------------------------------------------------------------------

## Fill the space between two chord polylines with a lattice web.
##
## Pattern: an X in every bay plus a vertical every `vertical_every` stations.
## That is the dense multiple-lattice ("treillis") of the 1880s, not the sparse
## N-truss of a modern bridge, and it is the reason the real arch looks woven.
##
## Bays whose depth has closed to under `min_depth` are skipped: on a crescent
## the chords converge to a pin, and a lattice drawn all the way in degenerates
## into a knot of overlapping bars right where the eye is drawn.
##
## `gussets` is a SEPARATE baker on purpose: the plates are chord-coloured
## structure, the web bars are the darker steel behind them, and splitting them
## here is what lets both land in the right one of the two iron draw calls.
static func lattice_web(b: MeshBaker, upper: PackedVector3Array,
		lower: PackedVector3Array, bar_width: float, bar_thick: float,
		normal: Vector3, vertical_every: int = 2, min_depth: float = 0.6,
		gussets: MeshBaker = null, gusset_size: float = 0.0) -> void:
	var n := mini(upper.size(), lower.size())
	if n < 2:
		return
	for i in n - 1:
		var d0 := upper[i].distance_to(lower[i])
		var d1 := upper[i + 1].distance_to(lower[i + 1])
		if maxf(d0, d1) < min_depth:
			continue
		bar(b, lower[i], upper[i + 1], bar_width, bar_thick, normal)
		bar(b, upper[i], lower[i + 1], bar_width, bar_thick, normal)
	var every := maxi(vertical_every, 1)
	for i in n:
		if upper[i].distance_to(lower[i]) < min_depth:
			continue
		if i % every == 0:
			bar(b, lower[i], upper[i], bar_width * 1.15, bar_thick, normal)
		if gussets != null and gusset_size > 0.0 and i % every == 0:
			gusset(gussets, upper[i], gusset_size, bar_thick * 2.4, normal,
					_tangent(upper, i))
			gusset(gussets, lower[i], gusset_size, bar_thick * 2.4, normal,
					_tangent(lower, i))


## A latticed column: four legs, battens at every level, and a single diagonal
## per panel on each of the two faces you see in elevation, its lean alternating
## up the column so the frame zig-zags.
##
## The spandrel columns are what carries the deck down onto the arch, and on the
## real bridge they are the tallest, most obviously hand-riveted things on it.
## Drawing them as plain posts is the difference between an iron bridge and a
## table with legs, so they are latticed even though it costs six members a panel.
##
## `base` and `top` are centres; the column may rake between them (the ribs splay
## outward under a deck that does not, so every column but the middle ones leans).
static func lattice_tower(b: MeshBaker, base: Vector3, top: Vector3,
		width_x: float, width_z: float, leg: float, panel: float,
		bar_width: float, bar_thick: float) -> void:
	var height := top.y - base.y
	var hx := width_x * 0.5
	var hz := width_z * 0.5
	if height < panel * 0.55:
		# Too short to lattice: a real one would be a cast pedestal, so build that.
		var mid := (base + top) * 0.5
		b.add_box(Vector3(width_x, maxf(height, 0.12), width_z),
				Transform3D(Basis(), mid))
		return

	var panels := maxi(int(round(height / panel)), 1)
	var levels: PackedVector3Array = PackedVector3Array()
	levels.resize(panels + 1)
	for k in panels + 1:
		levels[k] = base.lerp(top, float(k) / float(panels))

	# Legs. Straight runs, so one box each — the rake is in the endpoints. The
	# section is square, so the plane they are quoted in does not matter.
	for i in 4:
		var lx := (-1.0 if i < 2 else 1.0) * hx
		var lz := (-1.0 if i % 2 == 0 else 1.0) * hz
		var off := Vector3(lx, 0.0, lz)
		bar(b, base + off, top + off, leg, leg, Vector3.BACK)

	for k in panels + 1:
		var p := levels[k]
		# Battens close the box at every level: two across the elevation faces,
		# two across the ends. Without them the four legs read as four posts.
		for i in 2:
			var sz := -hz if i == 0 else hz
			bar(b, p + Vector3(-hx, 0.0, sz), p + Vector3(hx, 0.0, sz),
					bar_width, bar_thick, Vector3.BACK)
			var sx := -hx if i == 0 else hx
			bar(b, p + Vector3(sx, 0.0, -hz), p + Vector3(sx, 0.0, hz),
					bar_width, bar_thick, Vector3.RIGHT)

	for k in panels:
		var lo := levels[k]
		var hi := levels[k + 1]
		var flip := 1.0 if k % 2 == 0 else -1.0
		for i in 2:
			var sz := -hz if i == 0 else hz
			bar(b, lo + Vector3(-hx * flip, 0.0, sz), hi + Vector3(hx * flip, 0.0, sz),
					bar_width, bar_thick, Vector3.BACK)


## A straight lattice girder in the XY plane at a fixed z: top and bottom flanges,
## a vertical stiffener every `pitch`, and a diagonal in every panel with its lean
## alternating. Used for the deck fascia and the parapet frieze, so the deck edge
## and the handrail belong to the same ironwork as the arch under them.
static func lattice_girder(b: MeshBaker, x0: float, x1: float, y_top: float,
		y_bottom: float, z: float, pitch: float, flange: Vector2,
		bar_width: float, bar_thick: float, post_width: float = 0.0) -> void:
	var span := x1 - x0
	if span <= 0.0 or y_top <= y_bottom:
		return
	var bays := maxi(int(round(span / pitch)), 1)
	var inner_top := y_top - flange.y
	var inner_bottom := y_bottom + flange.y
	b.add_box(Vector3(span, flange.y, flange.x),
			Transform3D(Basis(), Vector3((x0 + x1) * 0.5, y_top - flange.y * 0.5, z)))
	b.add_box(Vector3(span, flange.y, flange.x),
			Transform3D(Basis(), Vector3((x0 + x1) * 0.5, y_bottom + flange.y * 0.5, z)))
	var post := post_width if post_width > 0.0 else bar_width * 1.4
	for i in bays + 1:
		var x := lerpf(x0, x1, float(i) / float(bays))
		bar(b, Vector3(x, inner_bottom, z), Vector3(x, inner_top, z),
				post, bar_thick, Vector3.BACK)
	for i in bays:
		var xa := lerpf(x0, x1, float(i) / float(bays))
		var xb := lerpf(x0, x1, float(i + 1) / float(bays))
		if i % 2 == 0:
			bar(b, Vector3(xa, inner_bottom, z), Vector3(xb, inner_top, z),
					bar_width, bar_thick, Vector3.BACK)
		else:
			bar(b, Vector3(xa, inner_top, z), Vector3(xb, inner_bottom, z),
					bar_width, bar_thick, Vector3.BACK)


# --- Internals ----------------------------------------------------------------

## Right-handed orthonormal basis with +X along `dir` and +Z along `normal`,
## `normal` orthogonalised against `dir` first. MeshBaker.add_box() then lays a
## (length, width, thick) box out exactly as a rolled flat would be.
static func _frame(dir: Vector3, normal: Vector3) -> Basis:
	var n := normal - dir * normal.dot(dir)
	if n.length_squared() < 1e-8:
		n = dir.cross(Vector3.UP)
		if n.length_squared() < 1e-8:
			n = dir.cross(Vector3.RIGHT)
	n = n.normalized()
	var basis := Basis()
	basis.x = dir
	basis.y = n.cross(dir).normalized()
	basis.z = n
	return basis


## Central-difference tangent along a polyline, forward/backward at the ends.
static func _tangent(points: PackedVector3Array, i: int) -> Vector3:
	var n := points.size()
	var a := points[maxi(i - 1, 0)]
	var b := points[mini(i + 1, n - 1)]
	var d := b - a
	if d.length_squared() < 1e-10:
		return Vector3.RIGHT
	return d.normalized()
