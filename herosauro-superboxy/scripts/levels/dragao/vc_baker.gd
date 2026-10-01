extends RefCounted
## Vertex-coloured baker for the stadium chapter.
##
## MeshBaker (scripts/world/) welds geometry into one surface but carries no
## colour, so a many-coloured thing (a goblin's head with its eyes, cheeks and
## grin; a stand of blue and white seats) would cost one draw call per colour.
## This welds shapes with a colour PER VERTEX instead: a whole goblin head, or
## every seat in the stadium, is one surface and one draw call, drawn with one of
## the shared vertex-colour materials in dragao_mats.gd.
##
## Winding: Godot's front face is the one whose right-hand normal points AWAY from
## the viewer (see MeshBaker's winding contract). Primitive meshes already obey
## it, so their indices are copied (reversed under a mirroring transform). The
## hand-built quads and triangles below take the normal they should FACE and fix
## the order themselves, so a caller cannot get it wrong.
##
## Unit primitives are cached by shape, so building twelve goblins asks Godot for
## one sphere, not two hundred.

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()
var uvs := PackedVector2Array()
var idx := PackedInt32Array()

static var _prims: Dictionary = {}


func is_empty() -> bool:
	return verts.is_empty()


func triangle_count() -> int:
	return idx.size() / 3


# --- Primitives ----------------------------------------------------------------

## An ellipsoid of `radii` at `center`, turned by `basis`.
func sphere(center: Vector3, radii: Vector3, color: Color, basis: Basis = Basis(),
		seg: int = 16, rings: int = 10) -> void:
	add_arrays(_unit("sphere", seg, rings), Transform3D(basis * Basis.from_scale(radii), center), color)


## A cylinder or cone: bottom radius `r_bot` at -h/2, top `r_top` at +h/2 (local Y).
func cylinder(r_top: float, r_bot: float, h: float, xform: Transform3D, color: Color,
		seg: int = 12) -> void:
	var rb := maxf(r_bot, 0.0001)
	var ratio := snappedf(r_top / rb, 0.01)
	var arr := _unit("cyl%.2f" % ratio, seg, 1, ratio)
	add_arrays(arr, xform * Transform3D(Basis.from_scale(Vector3(rb, h, rb)), Vector3.ZERO), color)


## Capsule along local Y, total height `h`.
func capsule(r: float, h: float, xform: Transform3D, color: Color, seg: int = 12) -> void:
	# Built from two caps and a tube so a non-uniform transform keeps round ends.
	var body := maxf(h - 2.0 * r, 0.0)
	if body > 0.0:
		cylinder(r, r, body, xform, color, seg)
	sphere(xform * Vector3(0.0, body * 0.5, 0.0), Vector3.ONE * r, color, xform.basis, seg, maxi(4, seg / 2))
	sphere(xform * Vector3(0.0, -body * 0.5, 0.0), Vector3.ONE * r, color, xform.basis, seg, maxi(4, seg / 2))


## Torus in the local XZ plane: ring radius `ring`, tube radius `tube`.
func torus(ring: float, tube: float, xform: Transform3D, color: Color, seg: int = 16,
		tube_seg: int = 6) -> void:
	var ratio := snappedf(tube / maxf(ring, 0.0001), 0.01)
	var arr := _unit("tor%.2f" % ratio, seg, tube_seg, ratio)
	add_arrays(arr, xform * Transform3D(Basis.from_scale(Vector3.ONE * ring), Vector3.ZERO), color)


## Axis-aligned (in `xform`'s frame) box, written longhand: flat faces, 24 verts.
func box(size: Vector3, xform: Transform3D, color: Color) -> void:
	var h := size * 0.5
	var c := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]
	var p: Array[Vector3] = []
	for v in c:
		p.append(xform * v)
	var b := xform.basis
	quad(p[4], p[5], p[6], p[7], (b * Vector3.BACK).normalized(), color)      # +Z
	quad(p[1], p[0], p[3], p[2], (b * Vector3.FORWARD).normalized(), color)   # -Z
	quad(p[5], p[1], p[2], p[6], (b * Vector3.RIGHT).normalized(), color)     # +X
	quad(p[0], p[4], p[7], p[3], (b * Vector3.LEFT).normalized(), color)      # -X
	quad(p[7], p[6], p[2], p[3], (b * Vector3.UP).normalized(), color)        # +Y
	quad(p[0], p[1], p[5], p[4], (b * Vector3.DOWN).normalized(), color)      # -Y


## Box between two corners, axis-aligned in world space. The stands' workhorse.
func block(lo: Vector3, hi: Vector3, color: Color) -> void:
	box(hi - lo, Transform3D(Basis(), (lo + hi) * 0.5), color)


## A flat quad that faces `n`. Corner order may be either way round.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, color: Color,
		uv_a: Vector2 = Vector2(0, 0), uv_c: Vector2 = Vector2(1, 1)) -> void:
	var base := verts.size()
	verts.append_array([a, b, c, d])
	norms.append_array([n, n, n, n])
	cols.append_array([color, color, color, color])
	uvs.append_array([uv_a, Vector2(uv_c.x, uv_a.y), uv_c, Vector2(uv_a.x, uv_c.y)])
	var rh := (b - a).cross(c - a)
	if rh.dot(n) >= 0.0:
		idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	else:
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


## A flat triangle that faces `n`.
func tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, color: Color) -> void:
	var base := verts.size()
	verts.append_array([a, b, c])
	norms.append_array([n, n, n])
	cols.append_array([color, color, color])
	uvs.append_array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)])
	if (b - a).cross(c - a).dot(n) >= 0.0:
		idx.append_array([base, base + 2, base + 1])
	else:
		idx.append_array([base, base + 1, base + 2])


## A double-sided flat triangle (wing membranes, flags).
func tri2(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	tri(a, b, c, n, color)
	tri(a, c, b, -n, color)


## A five-point star prism in the local XY plane, `thick` deep along Z.
func star(radius: float, thick: float, xform: Transform3D, color: Color) -> void:
	var pts: Array[Vector3] = []
	for i in 10:
		var ang := PI * 0.5 + TAU * float(i) / 10.0
		var r := radius if i % 2 == 0 else radius * 0.45
		pts.append(Vector3(cos(ang) * r, sin(ang) * r, 0.0))
	var hz := Vector3(0, 0, thick * 0.5)
	var fz := (xform.basis * Vector3.BACK).normalized()
	for i in 10:
		var p0 := pts[i]
		var p1 := pts[(i + 1) % 10]
		tri(xform * hz, xform * (p0 + hz), xform * (p1 + hz), fz, color)
		tri(xform * -hz, xform * (p1 - hz), xform * (p0 - hz), -fz, color)
		var side := (xform.basis * (p1 - p0).cross(Vector3.BACK)).normalized()
		quad(xform * (p0 + hz), xform * (p1 + hz), xform * (p1 - hz), xform * (p0 - hz), side, color)


## A surface of revolution about local Y. `profile` is (radius, height) pairs,
## bottom to top. `color_at` (optional) maps a profile index to a colour.
func lathe(profile: PackedVector2Array, xform: Transform3D, color: Color, seg: int = 16,
		color_at: Callable = Callable()) -> void:
	var rows := profile.size()
	var base := verts.size()
	var nb := xform.basis.inverse().transposed()
	for r in rows:
		var p := profile[r]
		# Profile tangent -> outward normal in the (radius, y) plane.
		var prev := profile[maxi(r - 1, 0)]
		var next := profile[mini(r + 1, rows - 1)]
		var t := (next - prev)
		var n2 := Vector2(t.y, -t.x).normalized() if t.length() > 1e-5 else Vector2(1, 0)
		var col: Color = color_at.call(r) if color_at.is_valid() else color
		for s in seg + 1:
			var ang := TAU * float(s) / float(seg)
			var dir := Vector3(cos(ang), 0.0, sin(ang))
			verts.append(xform * Vector3(dir.x * p.x, p.y, dir.z * p.x))
			norms.append((nb * (dir * n2.x + Vector3.UP * n2.y)).normalized())
			cols.append(col)
			uvs.append(Vector2(float(s) / float(seg), float(r) / float(maxi(rows - 1, 1))))
	var flip := xform.basis.determinant() < 0.0
	for r in rows - 1:
		for s in seg:
			var a := base + r * (seg + 1) + s
			var b := a + 1
			var c := a + seg + 1
			var d := c + 1
			# (a, b, c) has its right-hand normal pointing INTO the solid, which is
			# Godot's front face seen from outside (ring order runs +angle toward
			# +Z, rows run +Y).
			if flip:
				idx.append_array([a, c, b, b, c, d])
			else:
				idx.append_array([a, b, c, b, d, c])


## A round tube through `points` (rope, handles, wire). Colours alternate per
## ring between `color` and `alt` to suggest a twist.
func tube(points: PackedVector3Array, radius: float, color: Color, alt: Color,
		seg: int = 6) -> void:
	var n := points.size()
	if n < 2:
		return
	var base := verts.size()
	var up := Vector3.UP
	for i in n:
		var t := (points[mini(i + 1, n - 1)] - points[maxi(i - 1, 0)]).normalized()
		if absf(t.dot(up)) > 0.95:
			up = Vector3.RIGHT
		var side := t.cross(up).normalized()
		var nup := side.cross(t).normalized()
		var col := color if (i / 2) % 2 == 0 else alt
		for s in seg + 1:
			var ang := TAU * float(s) / float(seg)
			var dir := side * cos(ang) + nup * sin(ang)
			verts.append(points[i] + dir * radius)
			norms.append(dir)
			cols.append(col)
			uvs.append(Vector2(float(s) / float(seg), float(i)))
	for i in n - 1:
		for s in seg:
			var a := base + i * (seg + 1) + s
			var b := a + 1
			var c := a + seg + 1
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])
	# Which way round that is depends on the frame's handedness; test one quad
	# and flip the whole run if it faces inward.
	var k := base
	var rh := (verts[k + seg + 1] - verts[k]).cross(verts[k + 1] - verts[k])
	if rh.dot(norms[k]) < 0.0:
		for j in range(idx.size() - (n - 1) * seg * 6, idx.size(), 3):
			var tmp := idx[j + 1]
			idx[j + 1] = idx[j + 2]
			idx[j + 2] = tmp


## Copy a primitive's arrays through `xform`, in one colour (or per-vertex via
## `color_fn(local_pos: Vector3) -> Color`).
func add_arrays(arr: Array, xform: Transform3D, color: Color, color_fn: Callable = Callable()) -> void:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uv: Variant = arr[Mesh.ARRAY_TEX_UV]
	var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var base := verts.size()
	var nb := xform.basis.inverse().transposed()
	var has_uv := uv is PackedVector2Array and (uv as PackedVector2Array).size() == v.size()
	for k in v.size():
		verts.append(xform * v[k])
		norms.append((nb * nrm[k]).normalized())
		cols.append(color_fn.call(v[k]) if color_fn.is_valid() else color)
		uvs.append((uv as PackedVector2Array)[k] if has_uv else Vector2.ZERO)
	if xform.basis.determinant() < 0.0:
		for k in range(0, ix.size(), 3):
			idx.append_array([base + ix[k], base + ix[k + 2], base + ix[k + 1]])
	else:
		for k in ix:
			idx.append(base + k)


## Ellipsoid with a per-vertex colour function over the UNIT sphere's local
## position (hoops on a shirt, a lighter belly).
func sphere_fn(center: Vector3, radii: Vector3, basis: Basis, color_fn: Callable,
		seg: int = 16, rings: int = 12) -> void:
	add_arrays(_unit("sphere", seg, rings), Transform3D(basis * Basis.from_scale(radii), center),
		Color.WHITE, color_fn)


# --- Output ---------------------------------------------------------------------

func mesh() -> ArrayMesh:
	var m := ArrayMesh.new()
	if verts.is_empty():
		return m
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func commit(material: Material, node_name: String, shadows: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh()
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# --- Unit primitive cache ----------------------------------------------------------

static func _unit(kind: String, a: int, b: int, ratio: float = 1.0) -> Array:
	var key := "%s|%d|%d" % [kind, a, b]
	if _prims.has(key):
		return _prims[key]
	var pm: PrimitiveMesh
	if kind == "sphere":
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = a
		s.rings = b
		pm = s
	elif kind.begins_with("cyl"):
		var c := CylinderMesh.new()
		c.top_radius = ratio
		c.bottom_radius = 1.0
		c.height = 1.0
		c.radial_segments = a
		c.rings = 1
		pm = c
	else:
		var t := TorusMesh.new()
		t.inner_radius = 1.0 - ratio
		t.outer_radius = 1.0 + ratio
		t.rings = a
		t.ring_segments = b
		pm = t
	var arr := pm.get_mesh_arrays()
	_prims[key] = arr
	return arr
