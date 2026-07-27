extends RefCounted
## The architectural vocabulary the Porto landmarks are assembled from.
##
## A monument is not a box with a texture on it. What makes granite read as
## granite at 80 m is the shadow line under a moulded cornice, the black slot of
## a round-headed bell opening set deep in a thick wall, the rhythm of a
## colonnade, the notch of a merlon against the sky. Those are the parts this
## file emits; landmarks_builder.gd decides where they go.
##
## Two frames, both matching the Ribeira facade kit next door so the two are
## learnable as one thing:
##
##   PLAN frame — origin on the ground at the centre of a footprint, +Y up. Used
##   for anything that runs around a building: cornices, parapets, crenellation,
##   balustrades, colonnades, domes.
##
##   FACE frame — origin at the middle of a wall face's bottom edge, +X across
##   the face, +Y up it, +Z straight out of the wall. Used for anything that sits
##   *on* a wall: openings, pilasters, pediments, tile panels. `face_of()` turns
##   a plan frame into one of these, which is what lets a belfry opening be
##   written once and appear on all four sides of a tower — and, because a face
##   frame is just a rotation and an offset, on a bay of a circular drum too.
##
## Winding: every emitter here winds a face so the right-hand normal of its
## triangles points the way the surface should be seen. That is the convention
## facade_geo.gd states and MeshBaker's stored normals follow. See the note at
## the head of landmarks_builder.gd — the engine currently disagrees with all of
## us, and the fix belongs in one place, not five.
##
## Nothing here knows about materials. Callers hand in a MeshBaker; grouping by
## material is landmark_batch.gd's job.

## Sub-millimetre spans are the residue of clamping and subtraction, not
## geometry. Emitting them costs triangles and produces z-fighting slivers.
const EPS := 1e-4


# --- Frames ------------------------------------------------------------------

## A face frame on one side of a plan. `yaw` picks the side — 0 is +Z, PI/2 is
## +X, PI is -Z, -PI/2 is -X — `dist` is the half-extent in that direction, and
## `base_y` the height the face starts at.
##
## Any other yaw gives a face tangent to a circle of radius `dist`, which is how
## the bays of a round drum get windows without a second implementation. At r = 8
## a 1.4 m wide bay bulges 3 cm off the true cylinder: invisible, and worth it.
static func face_of(plan: Transform3D, yaw: float, dist: float, base_y: float) -> Transform3D:
	var turned := Transform3D(Basis(Vector3.UP, yaw), Vector3(0.0, base_y, 0.0))
	return plan * turned.translated_local(Vector3(0.0, 0.0, dist))


## A plan frame lifted to height `y` — for stacking a cornice, an attic and a
## dome on the same footprint without repeating the offset everywhere.
static func lift(plan: Transform3D, y: float) -> Transform3D:
	return plan.translated_local(Vector3(0.0, y, 0.0))


# --- Openings ----------------------------------------------------------------

## A hole in a wall, in face space: the rectangle (x0, y0)-(x1, y1), optionally
## with a semi-elliptical head rising `rise` above y1.
##
## One shape covers everything these buildings need — Romanesque round arches,
## baroque round-headed bell openings, square shuttered windows, arcade bays —
## because a round arch is only the case where the rise equals the half-width.
class Opening extends RefCounted:
	const EPS := 1e-4

	var x0: float
	var x1: float
	var y0: float
	var y1: float   ## springing line: the top of the straight part
	var rise: float ## 0 for a flat head

	## `rise < 0` means "a true semicircle", the common case.
	static func arched(cx: float, width: float, sill: float, straight_h: float,
			rise: float = -1.0) -> Opening:
		var o := Opening.new()
		o.x0 = cx - width * 0.5
		o.x1 = cx + width * 0.5
		o.y0 = sill
		o.y1 = sill + straight_h
		o.rise = (width * 0.5) if rise < 0.0 else rise
		return o

	static func flat(cx: float, width: float, sill: float, height: float) -> Opening:
		return arched(cx, width, sill, height, 0.0)

	func top() -> float:
		return y1 + rise

	func centre_x() -> float:
		return (x0 + x1) * 0.5

	func width() -> float:
		return x1 - x0

	## Half-width of the hole at height `y`, or -1 where the wall is solid.
	## Constant up the jambs, then a quarter-ellipse through the head.
	func half_at(y: float) -> float:
		if y < y0 - EPS or y > top() + EPS:
			return -1.0
		var hw := (x1 - x0) * 0.5
		if y <= y1 or rise <= EPS:
			return hw
		var t := clampf((y - y1) / rise, 0.0, 1.0)
		return hw * sqrt(maxf(0.0, 1.0 - t * t))

	## The outline as a face-space polyline, walked up the left jamb, over the
	## head and down to the bottom of the right jamb. Not closed: the sill edge
	## closes it, and callers that need it say so.
	##
	## `expand` grows it outward, which is how an archivolt, a surround or a
	## relieving arch is derived from the hole it frames rather than authored
	## twice and left to drift apart.
	func outline(bands: int, expand: float = 0.0) -> PackedVector2Array:
		var pts := PackedVector2Array()
		var hw := (x1 - x0) * 0.5 + expand
		var cx := centre_x()
		var base := y0 - expand
		pts.append(Vector2(cx - hw, base))
		if rise > EPS:
			var r := rise + expand
			var steps := maxi(bands, 2) * 2
			for i in range(steps + 1):
				var a: float = PI * (1.0 - float(i) / float(steps))
				pts.append(Vector2(cx + hw * cos(a), y1 + r * sin(a)))
		else:
			pts.append(Vector2(cx - hw, y1 + expand))
			pts.append(Vector2(cx + hw, y1 + expand))
		pts.append(Vector2(cx + hw, base))
		return pts


# --- Flat surfaces -----------------------------------------------------------

## A rectangle in the face plane at depth `z`, facing out of the wall.
static func rect(b: MeshBaker, xf: Transform3D, x0: float, y0: float, x1: float, y1: float,
		z: float) -> void:
	if x1 - x0 <= EPS or y1 - y0 <= EPS:
		return
	b.add_quad(xf * Vector3(x0, y0, z), xf * Vector3(x1, y0, z),
			xf * Vector3(x1, y1, z), xf * Vector3(x0, y1, z), Vector2(x1 - x0, y1 - y0))


## The same rectangle wound the other way, so it faces back into the wall.
static func rect_back(b: MeshBaker, xf: Transform3D, x0: float, y0: float, x1: float, y1: float,
		z: float) -> void:
	if x1 - x0 <= EPS or y1 - y0 <= EPS:
		return
	b.add_quad(xf * Vector3(x1, y0, z), xf * Vector3(x0, y0, z),
			xf * Vector3(x0, y1, z), xf * Vector3(x1, y1, z), Vector2(x1 - x0, y1 - y0))


## A box in face space, centred at (cx, cy, cz).
static func box(b: MeshBaker, xf: Transform3D, cx: float, cy: float, cz: float,
		sx: float, sy: float, sz: float) -> void:
	if sx <= EPS or sy <= EPS or sz <= EPS:
		return
	b.add_box(Vector3(sx, sy, sz), xf * Transform3D(Basis(), Vector3(cx, cy, cz)))


## A beam between two frame-space points — railings, sign frames, dome ribs.
static func beam(b: MeshBaker, xf: Transform3D, from: Vector3, to: Vector3,
		thickness: float) -> void:
	b.add_beam(xf * from, xf * to, thickness)


## A row of identical boxes evenly spaced along a segment: balusters, merlons,
## roof tiles, the bays of a blind arcade. Spacing lands on whole units so the
## run always starts and ends with one.
static func series(b: MeshBaker, xf: Transform3D, from: Vector3, to: Vector3,
		size: Vector3, pitch: float) -> void:
	var span := from.distance_to(to)
	if span <= EPS or pitch <= EPS:
		return
	var count := maxi(1, int(round(span / pitch)))
	for i in range(count + 1):
		var t := float(i) / float(count)
		box(b, xf, lerpf(from.x, to.x, t), lerpf(from.y, to.y, t), lerpf(from.z, to.z, t),
				size.x, size.y, size.z)


# --- Outlines ----------------------------------------------------------------

## The flat band between two offsets of the same outline: an archivolt, a window
## surround, the moulded ring round a rose window. Faces out of the wall.
static func outline_band(b: MeshBaker, xf: Transform3D, inner: PackedVector2Array,
		outer: PackedVector2Array, z: float) -> void:
	var n := mini(inner.size(), outer.size())
	for i in range(n - 1):
		b.add_quad(
			xf * Vector3(inner[i].x, inner[i].y, z),
			xf * Vector3(inner[i + 1].x, inner[i + 1].y, z),
			xf * Vector3(outer[i + 1].x, outer[i + 1].y, z),
			xf * Vector3(outer[i].x, outer[i].y, z),
			Vector2(inner[i].distance_to(inner[i + 1]), inner[i].distance_to(outer[i])))


## The perpendicular return of an outline between two depths — the reveal inside
## an opening, or the side of a moulding standing proud of the wall. `inward`
## turns the faces toward the outline's centre, which is what makes a deep
## window read as a hole with bright returns rather than a decal.
static func outline_return(b: MeshBaker, xf: Transform3D, poly: PackedVector2Array,
		z_far: float, z_near: float, inward: bool) -> void:
	if absf(z_near - z_far) <= EPS:
		return
	for i in range(poly.size() - 1):
		var a := poly[i]
		var c := poly[i + 1]
		var uv := Vector2(a.distance_to(c), absf(z_near - z_far))
		if inward:
			b.add_quad(xf * Vector3(a.x, a.y, z_far), xf * Vector3(c.x, c.y, z_far),
					xf * Vector3(c.x, c.y, z_near), xf * Vector3(a.x, a.y, z_near), uv)
		else:
			b.add_quad(xf * Vector3(a.x, a.y, z_near), xf * Vector3(c.x, c.y, z_near),
					xf * Vector3(c.x, c.y, z_far), xf * Vector3(a.x, a.y, z_far), uv)


## Fill an outline as a fan from its centroid — the dark plate at the back of an
## opening, the tympanum of a pediment, a tile panel with a shaped top. The loop
## is closed from the last point back to the first.
static func fill_outline(b: MeshBaker, xf: Transform3D, poly: PackedVector2Array, z: float,
		face_out: bool = true) -> void:
	var n := poly.size()
	if n < 3:
		return
	var mid := Vector2.ZERO
	for p in poly:
		mid += p
	mid /= float(n)
	var c := xf * Vector3(mid.x, mid.y, z)
	for i in range(n):
		var a := poly[i]
		var d := poly[(i + 1) % n]
		var pa := xf * Vector3(a.x, a.y, z)
		var pd := xf * Vector3(d.x, d.y, z)
		var uv := Vector2(a.distance_to(d), a.distance_to(mid))
		# A quad with a doubled corner degenerates its second triangle and
		# MeshBaker drops degenerates, so a fan blade costs exactly one triangle.
		if face_out:
			b.add_quad(c, pd, pa, pa, uv)
		else:
			b.add_quad(c, pa, pd, pd, uv)


# --- Punched walls -----------------------------------------------------------

## A wall face with openings punched clean through it, emitted as the horizontal
## bands left over. Round heads fall out of the same loop as square ones: each
## band asks every opening how wide it is at that height.
##
## Bands sample the *narrowest* point of an arch head within the band, so the
## masonry always slightly overlaps the true curve rather than leaving a sliver
## of daylight at every step. The archivolt drawn over the joint hides the step;
## a gap would have to be found by eye at runtime.
static func panel(b: MeshBaker, xf: Transform3D, x0: float, y0: float, x1: float, y1: float,
		openings: Array, z: float, bands: int = 6) -> void:
	if x1 - x0 <= EPS or y1 - y0 <= EPS:
		return
	if openings.is_empty():
		rect(b, xf, x0, y0, x1, y1, z)
		return

	var cuts: Array[float] = [y0, y1]
	for k in openings.size():
		var o: Opening = openings[k]
		if o.top() <= y0 + EPS or o.y0 >= y1 - EPS:
			continue
		cuts.append(clampf(o.y0, y0, y1))
		cuts.append(clampf(o.y1, y0, y1))
		if o.rise > EPS:
			for i in range(1, bands + 1):
				cuts.append(clampf(o.y1 + o.rise * float(i) / float(bands), y0, y1))
	cuts.sort()

	for i in range(cuts.size() - 1):
		var ya := cuts[i]
		var yb := cuts[i + 1]
		if yb - ya <= EPS:
			continue
		var spans: Array[Vector2] = []
		for k in openings.size():
			var o: Opening = openings[k]
			var ha := o.half_at(ya + EPS)
			var hb := o.half_at(yb - EPS)
			if ha <= EPS or hb <= EPS:
				continue
			var half := minf(ha, hb)
			spans.append(Vector2(o.centre_x() - half, o.centre_x() + half))
		spans.sort_custom(func(l: Vector2, r: Vector2) -> bool: return l.x < r.x)

		var cursor := x0
		for s in spans:
			if s.x > cursor:
				rect(b, xf, cursor, ya, s.x, yb, z)
			cursor = maxf(cursor, s.y)
		if cursor < x1:
			rect(b, xf, cursor, ya, x1, yb, z)


## The reveal inside an opening: its jambs and arch soffit, turned to face the
## hole, running from the wall skin back to `z_back`.
static func opening_reveal(b: MeshBaker, xf: Transform3D, o: Opening, z_face: float,
		z_back: float, bands: int = 6) -> void:
	outline_return(b, xf, o.outline(bands), z_back, z_face, true)


## What is behind the hole. Flat, unlit, and it has to read as an absence rather
## than as a dark surface — see landmark_batch.void_dark().
static func opening_back(b: MeshBaker, xf: Transform3D, o: Opening, z: float,
		bands: int = 6) -> void:
	fill_outline(b, xf, o.outline(bands), z, true)


## The moulded ring standing proud of the wall around an opening: face band,
## inner return toward the hole, outer return away from it. Romanesque portals
## get several of these stepping outward; a baroque bell opening gets one.
static func archivolt(b: MeshBaker, xf: Transform3D, o: Opening, band: float,
		z_wall: float, z_proud: float, bands: int = 6) -> void:
	var inner := o.outline(bands)
	var outer := o.outline(bands, band)
	outline_band(b, xf, inner, outer, z_proud)
	outline_return(b, xf, inner, z_wall, z_proud, true)
	outline_return(b, xf, outer, z_wall, z_proud, false)


# --- Surfaces of revolution --------------------------------------------------

## Revolve a profile of (radius, height) points about the frame's Y axis: domes,
## drums, finial balls, column shafts, barrels. A radius of 0 at either end
## closes the surface to a point, which is exactly what a dome apex is — the
## quads there degenerate to triangles and MeshBaker drops the spare half.
static func revolve(b: MeshBaker, xf: Transform3D, profile: PackedVector2Array, segments: int,
		outward: bool = true) -> void:
	if profile.size() < 2 or segments < 3:
		return
	var step := TAU / float(segments)
	for i in range(profile.size() - 1):
		var lo := profile[i]
		var hi := profile[i + 1]
		var uv := Vector2(step * maxf(lo.x, hi.x), (hi - lo).length())
		for s in segments:
			var a0 := step * float(s)
			var a1 := step * float(s + 1)
			var lo0 := xf * Vector3(cos(a0) * lo.x, lo.y, sin(a0) * lo.x)
			var lo1 := xf * Vector3(cos(a1) * lo.x, lo.y, sin(a1) * lo.x)
			var hi0 := xf * Vector3(cos(a0) * hi.x, hi.y, sin(a0) * hi.x)
			var hi1 := xf * Vector3(cos(a1) * hi.x, hi.y, sin(a1) * hi.x)
			if outward:
				b.add_quad(lo0, hi0, hi1, lo1, uv)
			else:
				b.add_quad(lo0, lo1, hi1, hi0, uv)


## A plain open cylinder — a drum, a well, a tower shaft.
static func cyl_shell(b: MeshBaker, xf: Transform3D, radius: float, y0: float, y1: float,
		segments: int, outward: bool = true) -> void:
	revolve(b, xf, PackedVector2Array([Vector2(radius, y0), Vector2(radius, y1)]),
			segments, outward)


## A flat ring: the top of an entablature, a cloister roof, the tread of a round
## step. `r_inner` of 0 gives a solid disc.
static func annulus(b: MeshBaker, xf: Transform3D, r_inner: float, r_outer: float, y: float,
		segments: int, face_up: bool = true) -> void:
	if r_outer <= EPS or segments < 3:
		return
	var step := TAU / float(segments)
	for s in segments:
		var a0 := step * float(s)
		var a1 := step * float(s + 1)
		var i0 := xf * Vector3(cos(a0) * r_inner, y, sin(a0) * r_inner)
		var i1 := xf * Vector3(cos(a1) * r_inner, y, sin(a1) * r_inner)
		var o0 := xf * Vector3(cos(a0) * r_outer, y, sin(a0) * r_outer)
		var o1 := xf * Vector3(cos(a1) * r_outer, y, sin(a1) * r_outer)
		var uv := Vector2(step * r_outer, r_outer - r_inner)
		if face_up:
			b.add_quad(i0, i1, o1, o0, uv)
		else:
			b.add_quad(i0, o0, o1, i1, uv)


## A stack of concentric circular steps — the podium a round church stands on.
## Returns the height of the top tread.
static func round_steps(b: MeshBaker, xf: Transform3D, r_top: float, y0: float, count: int,
		rise: float, tread: float, segments: int) -> float:
	var y := y0
	for i in range(count):
		var r := r_top + tread * float(count - i)
		cyl_shell(b, xf, r, y, y + rise, segments)
		annulus(b, xf, r - tread, r, y + rise, segments)
		y += rise
	return y


# --- Mouldings and trim ------------------------------------------------------

## A cornice as a stack of stepped courses rather than one slab. Each course is
## a Vector2 of (outset beyond the plan half-extents, height); the overhang of
## the deepest one is what throws the shadow line that tells the eye a wall has
## stopped. Returns the top of the stack.
##
## `courses` is a plain Array rather than Array[Vector2] on purpose: every call
## site passes an inline literal, and an untyped literal handed to a typed array
## parameter is a runtime conversion waiting to fail.
static func moulded_band(b: MeshBaker, plan: Transform3D, y: float, hx: float, hz: float,
		courses: Array) -> float:
	var top := y
	for i in courses.size():
		var c: Vector2 = courses[i]
		b.add_box(Vector3((hx + c.x) * 2.0, c.y, (hz + c.x) * 2.0),
				plan * Transform3D(Basis(), Vector3(0.0, top + c.y * 0.5, 0.0)))
		top += c.y
	return top


## The same, revolved: a cornice round a drum or a lantern.
static func moulded_ring(b: MeshBaker, plan: Transform3D, y: float, radius: float,
		courses: Array, segments: int) -> float:
	var top := y
	for i in courses.size():
		var c: Vector2 = courses[i]
		var r := radius + c.x
		cyl_shell(b, plan, r, top, top + c.y, segments)
		annulus(b, plan, radius, r, top, segments, false)
		annulus(b, plan, radius, r, top + c.y, segments, true)
		top += c.y
	return top


## A flat pilaster on a wall face, with a base block and a capital. Four of these
## on a tower stage are most of what makes it read as architecture: they catch
## the low sun down one edge and shade the other.
##
## The base and capital courses are stated in metres, not as fractions of the
## shaft, because a capital is a course of stone and a course of stone is 30 cm
## whether it caps a chapel or a cathedral.
static func pilaster(b: MeshBaker, xf: Transform3D, cx: float, y0: float, y1: float,
		width: float, proud: float, capital: bool = true) -> void:
	var h := y1 - y0
	if h <= EPS:
		return
	box(b, xf, cx, y0 + h * 0.5, proud * 0.5, width, h, proud)
	if not capital:
		return
	box(b, xf, cx, y0 + 0.16, proud * 0.62, width * 1.3, 0.32, proud * 1.24)
	box(b, xf, cx, y1 - 0.20, proud * 0.62, width * 1.3, 0.40, proud * 1.24)
	box(b, xf, cx, y1 - 0.02, proud * 0.72, width * 1.5, 0.16, proud * 1.44)


## Crenellation round a rectangular parapet — the single feature that says
## "fortress" from a kilometre away, which is exactly how the Sé reads.
static func merlons(b: MeshBaker, plan: Transform3D, y: float, hx: float, hz: float,
		merlon: float, gap: float, height: float, thick: float) -> void:
	var pitch := merlon + gap
	var size := Vector3(merlon, height, thick)
	var y_mid := y + height * 0.5
	series(b, plan, Vector3(-hx, y_mid, hz - thick * 0.5), Vector3(hx, y_mid, hz - thick * 0.5),
			size, pitch)
	series(b, plan, Vector3(-hx, y_mid, -hz + thick * 0.5), Vector3(hx, y_mid, -hz + thick * 0.5),
			size, pitch)
	var side := Vector3(thick, height, merlon)
	series(b, plan, Vector3(hx - thick * 0.5, y_mid, -hz + pitch), Vector3(hx - thick * 0.5, y_mid, hz - pitch),
			side, pitch)
	series(b, plan, Vector3(-hx + thick * 0.5, y_mid, -hz + pitch), Vector3(-hx + thick * 0.5, y_mid, hz - pitch),
			side, pitch)


## A balustrade along one straight run in a face frame: bottom plinth, top rail
## and the balusters between. Two boxes per baluster, not a turned profile —
## these are read at 40 m and up, where the silhouette of the gaps is the whole
## effect and a lathe-turned vase is 40 triangles of nothing.
static func balustrade_run(b: MeshBaker, xf: Transform3D, x0: float, x1: float, y: float,
		z: float, height: float, pitch: float, solid: bool = false) -> void:
	var span := x1 - x0
	if span <= EPS:
		return
	var cx := (x0 + x1) * 0.5
	var rail := height * 0.16
	box(b, xf, cx, y + rail * 0.5, z, span, rail, 0.34)
	box(b, xf, cx, y + height - rail * 0.5, z, span, rail, 0.40)
	if solid:
		box(b, xf, cx, y + height * 0.5, z, span, height, 0.22)
		return
	var mid := y + height * 0.5
	series(b, xf, Vector3(x0 + pitch * 0.5, mid, z), Vector3(x1 - pitch * 0.5, mid, z),
			Vector3(pitch * 0.42, height - rail * 2.0, 0.20), pitch)


## A balustrade round a rectangular plan, with a pier on each corner.
static func balustrade_rect(b: MeshBaker, plan: Transform3D, y: float, hx: float, hz: float,
		height: float, pitch: float, solid: bool = false) -> void:
	for i in 4:
		var yaw := PI * 0.5 * float(i)
		var dist := hz if i % 2 == 0 else hx
		var across := hx if i % 2 == 0 else hz
		balustrade_run(b, face_of(plan, yaw, dist, y), -across + 0.5, across - 0.5, 0.0, -0.2,
				height, pitch, solid)
	# Corner piers, sized off the baluster pitch rather than in absolute metres so
	# a balustrade round a 5 m gallery and one round a 20 m terrace both look
	# like balustrades.
	var pier := Vector3(pitch * 1.9, height * 1.24, pitch * 1.9)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.add_box(pier, plan * Transform3D(Basis(),
					Vector3(sx * hx, y + pier.y * 0.5, sz * hz)))


## A balustrade round a circle — the gallery at the foot of a dome.
static func balustrade_ring(b: MeshBaker, plan: Transform3D, radius: float, y: float,
		height: float, count: int, segments: int) -> void:
	var rail := height * 0.18
	moulded_ring(b, plan, y, radius - 0.18, [Vector2(0.36, rail)], segments)
	moulded_ring(b, plan, y + height - rail, radius - 0.22, [Vector2(0.44, rail)], segments)
	var mid := y + height * 0.5
	for i in count:
		var a := TAU * float(i) / float(count)
		b.add_box(Vector3(0.22, height - rail * 2.0, 0.22), plan * Transform3D(
				Basis(Vector3.UP, a), Vector3(sin(a) * radius, mid, cos(a) * radius)))


## A ring of free-standing columns: base, shaft with a little entasis, necking,
## abacus and — for the Ionic order Serra do Pilar actually uses — a pair of
## volute scrolls turned to face out of the circle.
##
## `skip_from`/`skip_to` cut an arc out of the ring, which is where the church
## joins the cloister and a column would stand inside a wall.
static func colonnade(b: MeshBaker, plan: Transform3D, radius: float, count: int, y0: float,
		height: float, col_r: float, segments: int, volutes: bool = true,
		skip_from: float = 0.0, skip_to: float = 0.0) -> void:
	var base_h := height * 0.06
	var cap_h := height * 0.05
	var shaft_top := height - cap_h * 2.0
	for i in count:
		var a := TAU * float(i) / float(count)
		if skip_to > skip_from and a >= skip_from and a <= skip_to:
			continue
		var at := plan * Transform3D(Basis(Vector3.UP, a),
				Vector3(sin(a) * radius, y0, cos(a) * radius))
		b.add_box(Vector3(col_r * 2.7, base_h, col_r * 2.7),
				at * Transform3D(Basis(), Vector3(0.0, base_h * 0.5, 0.0)))
		revolve(b, at, PackedVector2Array([
			Vector2(col_r * 1.04, base_h),
			Vector2(col_r, height * 0.34),
			Vector2(col_r * 0.88, shaft_top),
		]), segments)
		b.add_box(Vector3(col_r * 2.3, cap_h, col_r * 2.3),
				at * Transform3D(Basis(), Vector3(0.0, shaft_top + cap_h * 0.5, 0.0)))
		b.add_box(Vector3(col_r * 2.9, cap_h, col_r * 2.9),
				at * Transform3D(Basis(), Vector3(0.0, shaft_top + cap_h * 1.5, 0.0)))
		if not volutes:
			continue
		for sx in [-1.0, 1.0]:
			b.add_box(Vector3(col_r * 0.9, cap_h * 1.5, col_r * 1.1), at * Transform3D(
					Basis(), Vector3(sx * col_r * 1.15, shaft_top + cap_h * 0.6, 0.0)))


# --- Set pieces --------------------------------------------------------------

## A rose window: a recessed disc, a moulded ring round it and radiating
## tracery. Twelve spokes on a wheel two and a half metres across is what the
## eye picks up at 80 m — the cusping inside them is not.
static func rose_window(b_stone: MeshBaker, b_void: MeshBaker, xf: Transform3D, cx: float,
		cy: float, radius: float, spokes: int, z: float, depth: float) -> void:
	# Author the wheel in a plan frame tipped so its +Y points out of the wall:
	# the ring helpers then work on it unchanged, which is cheaper than a second
	# set of emitters that only ever draw circles standing up.
	var ring := xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(cx, cy, z))
	var sides := maxi(spokes * 2, 12)
	annulus(b_void, ring, 0.0, radius, -depth, sides, true)
	cyl_shell(b_stone, ring, radius, -depth, 0.0, sides, false)
	moulded_ring(b_stone, ring, 0.0, radius, [Vector2(0.34, 0.16), Vector2(0.18, 0.14)], sides)
	annulus(b_stone, ring, 0.0, radius * 0.17, -depth * 0.45, sides, true)
	# Half as many bars as spokes: each is a full diameter, so it does the work of
	# two and costs one.
	var bars := maxi(2, spokes / 2)
	for i in bars:
		var a := PI * float(i) / float(bars)
		b_stone.add_box(Vector3(radius * 1.94, 0.15, 0.15),
				xf * Transform3D(Basis(Vector3.BACK, a), Vector3(cx, cy, z - depth * 0.45)))


## A triangular pediment: tympanum, raking cornices and the horizontal cornice
## under it. `band` is the cornice thickness.
static func pediment(b: MeshBaker, xf: Transform3D, half_w: float, y0: float, riseto: float,
		depth: float, band: float) -> void:
	var apex := Vector2(0.0, y0 + riseto)
	var left := Vector2(-half_w, y0)
	var right := Vector2(half_w, y0)
	fill_outline(b, xf, PackedVector2Array([left, apex, right]), depth * 0.5)
	outline_return(b, xf, PackedVector2Array([left, apex, right]), 0.0, depth * 0.5, false)
	box(b, xf, 0.0, y0 - band * 0.5, depth * 0.62, half_w * 2.0 + band * 2.0, band, depth * 1.24)
	# Raking cornices, thickened along the slope so the two meet cleanly at the
	# apex instead of leaving a notch there.
	var slope := Vector2(half_w, riseto).length()
	var ang := atan2(riseto, half_w)
	for sx in [-1.0, 1.0]:
		var basis := Basis(Vector3.BACK, sx * -ang)
		var mid := Vector3(sx * half_w * 0.5, y0 + riseto * 0.5, depth * 0.62)
		b.add_box(Vector3(slope + band, band, depth * 1.24), xf * Transform3D(basis, mid))


## A pitched roof with eaves, ridge along the frame's X axis. The overhangs are
## separate: eaves project over the long walls, but a gable end often wants none
## at all, because the roof's own gable triangle then sits exactly where the
## whitewashed wall behind it does and the two z-fight. The shadow a deep eave
## throws across the top of a wall is half of what makes a roof look like a roof.
static func gable_roof(b: MeshBaker, plan: Transform3D, y: float, hx: float, hz: float,
		riseto: float, over_x: float, over_z: float, ridge: bool = true,
		segments: int = 6) -> void:
	var ex := hx + over_x
	var ez := hz + over_z
	b.add_roof_prism(ex * 2.0, riseto, ez * 2.0,
			plan * Transform3D(Basis(), Vector3(0.0, y, 0.0)))
	# Fascia: the eave has to have a thickness or it reads as a sheet of paper.
	b.add_box(Vector3(ex * 2.0 + 0.1, 0.22, 0.16),
			plan * Transform3D(Basis(), Vector3(0.0, y - 0.06, ez)))
	b.add_box(Vector3(ex * 2.0 + 0.1, 0.22, 0.16),
			plan * Transform3D(Basis(), Vector3(0.0, y - 0.06, -ez)))
	if ridge:
		var lay := Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3(0.0, y + riseto, 0.0))
		revolve(b, plan * lay, PackedVector2Array([
			Vector2(0.16, -ex), Vector2(0.16, ex)]), segments)


## A cross on a spike, the finial every church here ends in. Thin, but it is the
## last centimetre of the silhouette and its absence is felt.
static func cross_finial(b: MeshBaker, plan: Transform3D, y: float, height: float,
		arm: float, thick: float) -> void:
	box(b, plan, 0.0, y + height * 0.5, 0.0, thick, height, thick)
	box(b, plan, 0.0, y + height * 0.72, 0.0, arm, thick * 1.1, thick)


## A ball on a moulded base — the join between a dome and its cross.
static func finial_ball(b: MeshBaker, plan: Transform3D, y: float, radius: float,
		segments: int) -> float:
	var prof := PackedVector2Array()
	var rings := 4
	for i in range(rings + 1):
		var a: float = PI * float(i) / float(rings)
		prof.append(Vector2(sin(a) * radius, y + radius - cos(a) * radius))
	revolve(b, plan, prof, segments)
	return y + radius * 2.0


## A dome as a profile of revolution. `ogee` bulges the section outward the way
## a baroque cupola does; 0 gives the plain hemisphere Serra do Pilar has.
static func dome(b: MeshBaker, plan: Transform3D, radius: float, y: float, riseto: float,
		segments: int, rings: int, ogee: float = 0.0) -> void:
	var prof := PackedVector2Array()
	for i in range(rings + 1):
		var t := float(i) / float(rings)
		var a := PI * 0.5 * t
		var r := cos(a) * radius * (1.0 + ogee * sin(a * 2.0))
		prof.append(Vector2(r, y + sin(a) * riseto))
	revolve(b, plan, prof, segments)


## Ribs running up a dome's meridians. Cheap, and they are what keeps a dome
## from reading as a grey balloon when the sun is behind it.
static func dome_ribs(b: MeshBaker, plan: Transform3D, radius: float, y: float, riseto: float,
		count: int, thickness: float, steps: int = 4) -> void:
	for i in count:
		var yaw := TAU * float(i) / float(count)
		var turn := Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO)
		for s in range(steps):
			var a0 := PI * 0.5 * float(s) / float(steps)
			var a1 := PI * 0.5 * float(s + 1) / float(steps)
			beam(b, plan * turn,
					Vector3(0.0, y + sin(a0) * riseto, cos(a0) * radius),
					Vector3(0.0, y + sin(a1) * riseto, cos(a1) * radius), thickness)
