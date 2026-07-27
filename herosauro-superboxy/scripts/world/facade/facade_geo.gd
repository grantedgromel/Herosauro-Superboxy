extends RefCounted
## Face-local geometry emitters for the Ribeira facade system.
##
## Everything here authors into a *face frame*: a Transform3D whose origin sits
## at the middle of a wall face's bottom edge, with +X running across the face,
## +Y up it and +Z pointing straight out of the wall. A window written once as
## (x, y, depth) then works on the street front, on a return elevation or on a
## gable end without a second implementation — the frame does the placing.
##
## Winding is load-bearing here. MeshBaker derives a flat normal from each
## triangle's vertex order, so a quad wound the wrong way is not merely
## back-facing, it is a black hole in a sunlit facade. Every emitter below states
## which direction its faces end up pointing.
##
## Nothing in this file knows about materials or architecture; it is handed a
## MeshBaker and fills it. FacadeBuilder decides which baker.

## Sub-millimetre spans are the residue of clamping and subtraction, not
## geometry. Emitting them costs triangles and produces z-fighting slivers.
const EPS := 1e-4


# --- Points ------------------------------------------------------------------

## Face space -> world space.
static func p(xf: Transform3D, x: float, y: float, z: float) -> Vector3:
	return xf * Vector3(x, y, z)


# --- Flat surfaces -----------------------------------------------------------

## A rectangle in the face plane at depth `z`, facing out of the wall (+Z).
static func rect(b: MeshBaker, xf: Transform3D, x0: float, y0: float, x1: float, y1: float,
		z: float) -> void:
	if x1 - x0 <= EPS or y1 - y0 <= EPS:
		return
	b.add_quad(p(xf, x0, y0, z), p(xf, x1, y0, z), p(xf, x1, y1, z), p(xf, x0, y1, z),
			Vector2(x1 - x0, y1 - y0))


## The same rectangle wound the other way, so it faces back into the wall (-Z).
## Used for the far side of anything the camera can get behind.
static func rect_back(b: MeshBaker, xf: Transform3D, x0: float, y0: float, x1: float, y1: float,
		z: float) -> void:
	if x1 - x0 <= EPS or y1 - y0 <= EPS:
		return
	b.add_quad(p(xf, x1, y0, z), p(xf, x0, y0, z), p(xf, x0, y1, z), p(xf, x1, y1, z),
			Vector2(x1 - x0, y1 - y0))


## An arbitrarily oriented quad given four face-space corners, wound a->b->c->d.
## For railings and consoles, which do not lie in the wall plane.
static func quad(b: MeshBaker, xf: Transform3D, a: Vector3, bb: Vector3, c: Vector3, d: Vector3,
		uv: Vector2 = Vector2.ONE) -> void:
	b.add_quad(xf * a, xf * bb, xf * c, xf * d, uv)


## A single triangle in face space.
##
## MeshBaker only exposes quads, but a quad with a doubled last corner
## degenerates its second triangle and _tri_uv drops degenerates — so this costs
## exactly one triangle, not two. Balcony consoles and gable infills want that.
static func tri(b: MeshBaker, xf: Transform3D, a: Vector3, c: Vector3, d: Vector3) -> void:
	b.add_quad(xf * a, xf * c, xf * d, xf * d)


# --- Frames and reveals ------------------------------------------------------

## A flat picture frame at depth `z`: the ring of wall between an inner opening
## (x0,y0)-(x1,y1) and an outer rectangle grown by the four band widths. Four
## rectangles, all facing out. Pass bottom = 0 where a projecting sill will take
## that edge instead, which is how a real window surround is put together.
static func ring(b: MeshBaker, xf: Transform3D, x0: float, y0: float, x1: float, y1: float,
		left: float, right: float, bottom: float, top: float, z: float) -> void:
	var ox0 := x0 - left
	var ox1 := x1 + right
	rect(b, xf, ox0, y0 - bottom, ox1, y0, z)   # under the opening
	rect(b, xf, ox0, y1, ox1, y1 + top, z)      # over it (the lintel band)
	rect(b, xf, ox0, y0, x0, y1, z)             # left jamb face
	rect(b, xf, x1, y0, ox1, y1, z)             # right jamb face


## The rectangle `ring` would draw around that opening — the hole a wall panel
## has to leave for it.
static func ring_bounds(x0: float, y0: float, x1: float, y1: float,
		left: float, right: float, bottom: float, top: float) -> Rect2:
	return Rect2(x0 - left, y0 - bottom, (x1 - x0) + left + right, (y1 - y0) + bottom + top)


## The four side walls of a rectangular opening, spanning `z_far` to `z_near`
## (near meaning further out of the wall).
##
## `inward` turns them to face the opening's centre — a window reveal, seen from
## outside as bright returns around a dark hole. Otherwise they face away, which
## is the return of a moulding standing proud of the wall.
static func tube(b: MeshBaker, xf: Transform3D, x0: float, y0: float, x1: float, y1: float,
		z_far: float, z_near: float, inward: bool) -> void:
	if x1 - x0 <= EPS or y1 - y0 <= EPS or absf(z_near - z_far) <= EPS:
		return
	# Corners counter-clockwise seen from +Z, so consecutive pairs walk the
	# perimeter and the cross product of (edge, depth) lands consistently.
	var corner := [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]
	for i in 4:
		var a: Vector2 = corner[i]
		var c: Vector2 = corner[(i + 1) % 4]
		var uv := Vector2(a.distance_to(c), absf(z_near - z_far))
		if inward:
			b.add_quad(p(xf, a.x, a.y, z_near), p(xf, c.x, c.y, z_near),
					p(xf, c.x, c.y, z_far), p(xf, a.x, a.y, z_far), uv)
		else:
			b.add_quad(p(xf, a.x, a.y, z_far), p(xf, c.x, c.y, z_far),
					p(xf, c.x, c.y, z_near), p(xf, a.x, a.y, z_near), uv)


# --- Punched wall panel ------------------------------------------------------

## A wall panel with rectangular holes punched through it, emitted as the
## smallest set of rectangles that tiles what is left.
##
## This is what turns a facade from a painted picture into architecture: the
## outer skin genuinely has holes in it, and the window reveals behind show
## through them. Doing it generically — rather than hard-coding "pier, lintel,
## spandrel" per storey — means arches, shopfronts and irregular bays all fall
## out of the same code.
##
## Bands are cut at every distinct hole edge in Y; within a band the holes that
## straddle it split the remaining width into strips. Overlapping holes are
## handled by the running cursor, so callers need not merge them first.
static func panel(b: MeshBaker, xf: Transform3D, x0: float, y0: float, x1: float, y1: float,
		holes: Array[Rect2], z: float) -> void:
	var bounds := Rect2(x0, y0, x1 - x0, y1 - y0)
	if bounds.size.x <= EPS or bounds.size.y <= EPS:
		return

	var live: Array[Rect2] = []
	for h in holes:
		var c := h.intersection(bounds)
		if c.size.x > EPS and c.size.y > EPS:
			live.append(c)
	if live.is_empty():
		rect(b, xf, x0, y0, x1, y1, z)
		return

	var cuts: Array[float] = [y0, y1]
	for h in live:
		cuts.append(h.position.y)
		cuts.append(h.end.y)
	cuts.sort()

	for i in range(cuts.size() - 1):
		var ya := cuts[i]
		var yb := cuts[i + 1]
		if yb - ya <= EPS:
			continue
		# Sample at the band's midpoint: a hole either spans the whole band or
		# does not touch it, because the band edges are the hole edges.
		var ym := (ya + yb) * 0.5
		var spans: Array[Vector2] = []
		for h in live:
			if h.position.y < ym and h.end.y > ym:
				spans.append(Vector2(h.position.x, h.end.x))
		spans.sort_custom(func(l: Vector2, r: Vector2) -> bool: return l.x < r.x)

		var cursor := x0
		for s in spans:
			if s.x > cursor:
				rect(b, xf, cursor, ya, s.x, yb, z)
			cursor = maxf(cursor, s.y)
		if cursor < x1:
			rect(b, xf, cursor, ya, x1, yb, z)


# --- Solids ------------------------------------------------------------------

## A box in face space, centred at (cx, cy, cz).
static func box(b: MeshBaker, xf: Transform3D, cx: float, cy: float, cz: float,
		sx: float, sy: float, sz: float) -> void:
	if sx <= EPS or sy <= EPS or sz <= EPS:
		return
	b.add_box(Vector3(sx, sy, sz), xf * Transform3D(Basis(), Vector3(cx, cy, cz)))


## A box rotated about its own Y axis, then placed — a shutter leaf swung on its
## hinge, an awning bracket. `pivot` is where the rotation happens, `offset` is
## the box centre relative to that pivot after rotating.
static func box_hinged(b: MeshBaker, xf: Transform3D, pivot: Vector3, angle: float,
		offset: Vector3, size: Vector3) -> void:
	var hinge := Transform3D(Basis(Vector3.UP, angle), pivot)
	b.add_box(size, xf * hinge * Transform3D(Basis(), offset))


## A beam between two face-space points — rails, laundry lines, sign posts.
static func beam(b: MeshBaker, xf: Transform3D, from: Vector3, to: Vector3,
		thickness: float) -> void:
	b.add_beam(xf * from, xf * to, thickness)


## A cylinder lying along the face's X axis: ridge caps, gutters, awning rolls.
## MeshBaker builds cylinders along local Y, so this tips one over first.
static func cylinder_x(b: MeshBaker, xf: Transform3D, cx: float, cy: float, cz: float,
		radius: float, length: float, segments: int = 6, capped: bool = false) -> void:
	var lay := Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3(cx, cy, cz))
	b.add_cylinder(radius, length, xf * lay, segments, capped)
