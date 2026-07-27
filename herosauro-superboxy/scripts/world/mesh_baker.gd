class_name MeshBaker
extends RefCounted
## Accumulates many transformed primitives into ONE ArrayMesh surface.
##
## The scenery used to be one `MeshInstance3D` per box — a house was a wall box
## plus a roof prism plus a window quad, and that ceiling on part count is why it
## read as a stack of blocks. Every added mesh cost a draw call, so detail was
## unaffordable.
##
## Baking removes that ceiling: a building can be assembled from two hundred
## boxes — window reveals, sills, shutters, balcony balusters, cornices, roof
## tiles — and still cost a single draw call, because they are welded into one
## surface up front. Cost moves from per-frame (draw calls) to per-load (a few
## milliseconds of SurfaceTool), which is exactly the trade we want.
##
## Usage:
##     var b := MeshBaker.new()
##     b.add_box(Vector3(2, 3, 0.4), Transform3D(Basis(), Vector3(0, 1.5, 0)))
##     b.add_box(...)                       # ...as many as the detail needs
##     var mi := b.commit(material, "House")  # -> MeshInstance3D, 1 surface
##
## Positions are baked in the transform you pass, so build in a convenient local
## space and let the caller place the finished MeshInstance3D.

var _st: SurfaceTool
var _tri_count: int = 0


func _init() -> void:
	_st = SurfaceTool.new()
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)


## Triangles accumulated so far — useful for budgeting.
func triangle_count() -> int:
	return _tri_count


# --- Primitives --------------------------------------------------------------

## An axis-aligned box of `size`, placed by `xform`.
##
## Written out longhand rather than via BoxMesh so each face gets its own flat
## normal and a sane 0..1 UV; a shared-vertex cube would smear lighting across
## the corners, which on a facade full of small boxes reads as mush.
func add_box(size: Vector3, xform: Transform3D, uv_scale: float = 1.0) -> void:
	var h := size * 0.5
	# 8 corners of the box in local space.
	var c := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z),
		Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z),
		Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z),
		Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]
	# face = 4 corner indices (CCW seen from outside) + the face's extent, so UVs
	# can be scaled in world units and stay consistent across differently-sized
	# boxes (a 6 m wall and a 0.4 m sill get the same texel density).
	var faces := [
		[3, 2, 1, 0, Vector2(size.x, size.z)],  # -Y
		[4, 5, 6, 7, Vector2(size.x, size.z)],  # +Y
		[0, 1, 5, 4, Vector2(size.x, size.y)],  # -Z
		[2, 3, 7, 6, Vector2(size.x, size.y)],  # +Z
		[1, 2, 6, 5, Vector2(size.z, size.y)],  # +X
		[3, 0, 4, 7, Vector2(size.z, size.y)],  # -X
	]
	for f in faces:
		var a: Vector3 = xform * c[f[0]]
		var b: Vector3 = xform * c[f[1]]
		var d: Vector3 = xform * c[f[2]]
		var e: Vector3 = xform * c[f[3]]
		var ext: Vector2 = f[4] * uv_scale
		_quad(a, b, d, e, ext)


## A quad from four corners wound a->b->c->d.
func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv_extent: Vector2 = Vector2.ONE) -> void:
	_quad(a, b, c, d, uv_extent)


## A triangular prism: the classic pitched roof. Ridge runs along local X.
func add_roof_prism(width: float, height: float, depth: float, xform: Transform3D,
		uv_scale: float = 1.0) -> void:
	var hw := width * 0.5
	var hd := depth * 0.5
	var a := xform * Vector3(-hw, 0.0, -hd)
	var b := xform * Vector3(hw, 0.0, -hd)
	var c := xform * Vector3(hw, 0.0, hd)
	var d := xform * Vector3(-hw, 0.0, hd)
	var r0 := xform * Vector3(-hw, height, 0.0)
	var r1 := xform * Vector3(hw, height, 0.0)
	var slope := Vector2(width, sqrt(height * height + hd * hd)) * uv_scale
	_quad(d, c, r1, r0, slope)                       # +Z pitch
	_quad(b, a, r0, r1, slope)                       # -Z pitch
	_tri(a, b, c, Vector2(width, depth) * uv_scale)  # underside
	_tri(a, c, d, Vector2(width, depth) * uv_scale)
	# Gable ends, in the x = -hw and x = +hw planes. These were previously
	# (a, r0, r1) and (b, r1, r0): both span the full width, so they were two
	# coincident copies of the -Z pitch with opposing normals -- guaranteed
	# z-fighting on that slope -- while leaving both actual ends open.
	# Winding differs per end so each faces outward: (d - a) x (r0 - a) gives -X,
	# and (r1 - b) x (c - b) gives +X.
	_tri(a, d, r0, Vector2(depth, height) * uv_scale)
	_tri(b, r1, c, Vector2(depth, height) * uv_scale)


## A cylinder along local Y — columns, balusters, poles, barrel roof tiles.
func add_cylinder(radius: float, height: float, xform: Transform3D, segments: int = 8,
		capped: bool = true) -> void:
	var hy := height * 0.5
	var prev := Vector3(radius, -hy, 0.0)
	var prev_t := Vector3(radius, hy, 0.0)
	for i in range(1, segments + 1):
		var ang := TAU * float(i) / float(segments)
		var cur := Vector3(cos(ang) * radius, -hy, sin(ang) * radius)
		var cur_t := Vector3(cos(ang) * radius, hy, sin(ang) * radius)
		_quad(xform * prev, xform * cur, xform * cur_t, xform * prev_t,
			Vector2(TAU * radius / float(segments), height))
		if capped:
			_tri(xform * Vector3(0, hy, 0), xform * prev_t, xform * cur_t, Vector2(radius, radius))
			_tri(xform * Vector3(0, -hy, 0), xform * cur, xform * prev, Vector2(radius, radius))
		prev = cur
		prev_t = cur_t


## A beam spanning two points — iron members, railings, laundry lines.
func add_beam(from: Vector3, to: Vector3, thickness: float) -> void:
	var d := to - from
	var len := d.length()
	if len < 1e-5:
		return
	var dir := d / len
	# Any stable perpendicular; Y unless the beam is near-vertical.
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var basis := Basis()
	basis.x = dir
	basis.z = dir.cross(up).normalized()
	basis.y = basis.z.cross(dir).normalized()
	add_box(Vector3(len, thickness, thickness), Transform3D(basis, (from + to) * 0.5))


# --- Internals ---------------------------------------------------------------

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ext: Vector2) -> void:
	_tri_uv(a, b, c, Vector2(0, 0), Vector2(ext.x, 0), Vector2(ext.x, ext.y))
	_tri_uv(a, c, d, Vector2(0, 0), Vector2(ext.x, ext.y), Vector2(0, ext.y))


func _tri(a: Vector3, b: Vector3, c: Vector3, ext: Vector2) -> void:
	_tri_uv(a, b, c, Vector2(0, 0), Vector2(ext.x, 0), Vector2(ext.x, ext.y))


func _tri_uv(a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return   # degenerate; skip rather than emit a NaN normal
	n = n.normalized()
	_st.set_normal(n)
	_st.set_uv(ua)
	_st.add_vertex(a)
	_st.set_normal(n)
	_st.set_uv(ub)
	_st.add_vertex(b)
	_st.set_normal(n)
	_st.set_uv(uc)
	_st.add_vertex(c)
	_tri_count += 1


## Weld, generate tangents, and return a ready MeshInstance3D with one surface.
##
## Tangents matter: every PBR material here uses a detail normal map, and
## without tangents Godot cannot orient it, so normal mapping silently does
## nothing on baked geometry.
func commit(material: Material, name: String = "Baked",
		generate_lods: bool = true) -> MeshInstance3D:
	_st.index()
	_st.generate_tangents()
	var mesh := _st.commit()
	if generate_lods and mesh.get_surface_count() > 0:
		# Cheap at load, and lets distant terraces drop detail automatically.
		var im := ImporterMesh.new()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(0))
		im.generate_lods(25.0, 60.0, [])
		mesh = im.get_mesh()
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	if material:
		mi.material_override = material
	return mi
