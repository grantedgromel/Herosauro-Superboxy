extends RefCounted
## Shared building blocks for chapter "pandas": a vertex-coloured MeshBaker, the
## level's shared materials and the small procedural meshes (sparkles, petals,
## stars, droplets). Everything is built once and cached, so a material here is
## shared by every house, panda and pile that asks for it (ARCHITECTURE rule 7):
## nothing in this level mutates one except the two the LEVEL owns outright
## (window glow and lamp glow), which it dims and brightens with the evening.
##
## Why vertex colour: a Porto facade is twenty colours of the same plaster. One
## material per colour would be one draw call per colour per house; with the
## colour baked into the vertices a whole house look is three draw calls (body,
## granite trim, roof) however many colours it carries, and the ToonFactory
## detail maps underneath still give every surface its grain.

## A MeshBaker that also writes a vertex colour, plus the smooth primitives the
## stock baker lacks (ellipsoids for pandas and flowers, a puffy star).
class VBaker extends MeshBaker:
	func _init() -> void:
		if _st == null:
			_st = SurfaceTool.new()
			_st.begin(Mesh.PRIMITIVE_TRIANGLES)
		# Before the first vertex, so the colour channel exists for all of them.
		_st.set_color(Color.WHITE)

	func is_empty() -> bool:
		return _tri_count == 0

	func col(c: Color) -> void:
		_st.set_color(c)

	## Axis-aligned (or Euler-rotated) box centred on `pos`.
	func box(size: Vector3, pos: Vector3, c: Color, rot: Vector3 = Vector3.ZERO) -> void:
		_st.set_color(c)
		add_box(size, Transform3D(Basis.from_euler(rot), pos))

	func box_xf(size: Vector3, xf: Transform3D, c: Color) -> void:
		_st.set_color(c)
		add_box(size, xf)

	func beam(a: Vector3, b: Vector3, thick: float, c: Color) -> void:
		_st.set_color(c)
		add_beam(a, b, thick)

	func cyl(radius: float, height: float, xf: Transform3D, c: Color, segments: int = 10) -> void:
		_st.set_color(c)
		add_cylinder(radius, height, xf, segments, true)

	func quad(a: Vector3, b: Vector3, c2: Vector3, d: Vector3, c: Color) -> void:
		_st.set_color(c)
		add_quad(a, b, c2, d, Vector2((b - a).length(), (d - a).length()))

	func prism(width: float, height: float, depth: float, xf: Transform3D, c: Color) -> void:
		_st.set_color(c)
		add_roof_prism(width, height, depth, xf)

	## Smooth-shaded ellipsoid. `xf` places and orients the unit sphere scaled
	## by `radii`. Low segment counts read as cartoon chunks, which is the look.
	func blob(radii: Vector3, xf: Transform3D, c: Color, segs: int = 12, rings: int = 7) -> void:
		_st.set_color(c)
		var nb := xf.basis.inverse().transposed()
		for r in rings:
			var t0 := PI * float(r) / float(rings)
			var t1 := PI * float(r + 1) / float(rings)
			for s in segs:
				var p0 := TAU * float(s) / float(segs)
				var p1 := TAU * float(s + 1) / float(segs)
				var u00 := _unit(t0, p0)
				var u01 := _unit(t0, p1)
				var u10 := _unit(t1, p0)
				var u11 := _unit(t1, p1)
				_smooth_tri(xf, nb, radii, u00, u10, u11)
				_smooth_tri(xf, nb, radii, u00, u11, u01)

	## A five-point star in the local XY plane, facing +Z, puffed `depth` front
	## and back so it reads as a chunky gem from any angle.
	func star(r_out: float, r_in: float, depth: float, xf: Transform3D, c: Color) -> void:
		_st.set_color(c)
		var front := xf * Vector3(0.0, 0.0, depth)
		var back := xf * Vector3(0.0, 0.0, -depth)
		var pts: Array[Vector3] = []
		for i in 10:
			var a := PI * 0.5 + TAU * float(i) / 10.0
			var r := r_out if i % 2 == 0 else r_in
			pts.append(xf * Vector3(cos(a) * r, sin(a) * r, 0.0))
		for i in 10:
			var p := pts[i]
			var q := pts[(i + 1) % 10]
			# Right-hand normals out of the star, per MeshBaker's contract.
			_tri(front, p, q, Vector2.ONE)
			_tri(back, q, p, Vector2.ONE)

	func bake(mat: Material, node_name: String, shadows: bool = true) -> MeshInstance3D:
		if _tri_count == 0:
			return null
		var mi := commit(mat, node_name, false)
		if not shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return mi

	func bake_mesh() -> ArrayMesh:
		_st.index()
		_st.generate_tangents()
		return _st.commit()

	func _unit(theta: float, phi: float) -> Vector3:
		return Vector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))

	func _smooth_tri(xf: Transform3D, nb: Basis, radii: Vector3, a: Vector3, b: Vector3, c: Vector3) -> void:
		var pa := xf * (a * radii)
		var pb := xf * (b * radii)
		var pc := xf * (c * radii)
		var rh := (pb - pa).cross(pc - pa)
		if rh.length_squared() < 1e-14:
			return
		var na := (nb * (a / radii)).normalized()
		var nbv := (nb * (b / radii)).normalized()
		var nc := (nb * (c / radii)).normalized()
		# Godot keeps the triangle whose right-hand normal points AWAY from the
		# viewer (see MeshBaker), so an outward-facing triangle is emitted with
		# its right-hand normal pointing in.
		if rh.dot(na + nbv + nc) > 0.0:
			_v(pa, na, Vector2(a.x, a.y))
			_v(pc, nc, Vector2(c.x, c.y))
			_v(pb, nbv, Vector2(b.x, b.y))
		else:
			_v(pa, na, Vector2(a.x, a.y))
			_v(pb, nbv, Vector2(b.x, b.y))
			_v(pc, nc, Vector2(c.x, c.y))
		_tri_count += 1

	func _v(p: Vector3, n: Vector3, uv: Vector2) -> void:
		_st.set_normal(n)
		_st.set_uv(uv)
		_st.add_vertex(p)


static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}

const WHITEISH := Color(0.9, 0.9, 0.9)


## The vertex-coloured version of a ToonFactory material: same detail maps,
## albedo from the vertices. kind: plaster, stone, wood, roof, iron, soft.
static func vc(kind: String) -> StandardMaterial3D:
	var key := "vc_" + kind
	if _mats.has(key):
		return _mats[key]
	var base: StandardMaterial3D
	match kind:
		"stone":
			base = ToonFactory.stone(WHITEISH, 1.6)
		"wood":
			base = ToonFactory.wood(WHITEISH)
		"roof":
			base = ToonFactory.terracotta(WHITEISH, 0.7)
		"iron":
			base = ToonFactory.iron(WHITEISH, 1.2, 0.0, 0.55)
		"soft":
			base = ToonFactory.cloth(WHITEISH, 0.35)
		"glossy":
			base = ToonFactory.ceramic(WHITEISH, 0.4)
		_:
			base = ToonFactory.plaster(WHITEISH, 1.6)
	var m: StandardMaterial3D = base.duplicate()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	_mats[key] = m
	return m


## Unshaded, instance/vertex coloured: sparkles, lamp globes, bulbs, petals.
static func unshaded(double_sided: bool = false) -> StandardMaterial3D:
	var key := "unshaded_%d" % int(double_sided)
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	if double_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


## Lit petals (two-sided, vertex/instance coloured) so confetti catches the sun.
static func petal_material() -> StandardMaterial3D:
	if _mats.has("petal"):
		return _mats["petal"]
	var m: StandardMaterial3D = ToonFactory.cloth(WHITEISH, 0.2).duplicate()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["petal"] = m
	return m


## Warm lit windows. The LEVEL owns this one and raises its energy as evening
## falls; it is created here, never taken from ToonFactory's shared cache.
static func window_glow() -> StandardMaterial3D:
	if _mats.has("window_glow"):
		return _mats["window_glow"]
	var m: StandardMaterial3D = ToonFactory.glow(Color(1.0, 0.7, 0.36), 0.8).duplicate()
	m.albedo_color = Color(1.0, 0.8, 0.52)
	m.roughness = 0.12
	_mats["window_glow"] = m
	return m


## Dull, unlit glass for the broken houses' windows.
static func dark_glass() -> StandardMaterial3D:
	if _mats.has("dark_glass"):
		return _mats["dark_glass"]
	var m := ToonFactory.build(Color(0.14, 0.16, 0.2), ToonFactory.Surface.FLAT, 0.08)
	_mats["dark_glass"] = m
	return m


static func water(alpha: float = 0.72) -> StandardMaterial3D:
	var key := "water_%.2f" % alpha
	if _mats.has(key):
		return _mats[key]
	var m: StandardMaterial3D = ToonFactory.water(Color(0.32, 0.62, 0.78), alpha)
	_mats[key] = m
	return m


# --- Azulejos -------------------------------------------------------------------

## Blue-and-white (style 0), green-and-white (1) or blue-on-cream (2) tile glaze,
## generated once at load: albedo, a grout normal map and a roughness map, so the
## glaze is glossy and the grout matte. One tile = TILE_METERS.
const TILE_METERS := 0.34
const TILE_PX := 64

static func azulejo(style: int) -> StandardMaterial3D:
	var key := "azulejo_%d" % style
	if _mats.has(key):
		return _mats[key]
	var ink: Color
	var glaze: Color
	match style:
		1:
			ink = Color(0.1, 0.46, 0.4)
			glaze = Color(0.95, 0.96, 0.93)
		2:
			ink = Color(0.14, 0.3, 0.7)
			glaze = Color(0.98, 0.92, 0.74)
		_:
			ink = Color(0.1, 0.25, 0.66)
			glaze = Color(0.95, 0.96, 0.99)
	var n := TILE_PX
	var alb := Image.create(n, n, true, Image.FORMAT_RGB8)
	var nrm := Image.create(n, n, true, Image.FORMAT_RGB8)
	var rough := Image.create(n, n, true, Image.FORMAT_L8)
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for y in n:
		for x in n:
			var u := (float(x) + 0.5) / float(n)
			var v := (float(y) + 0.5) / float(n)
			var edge := minf(minf(u, 1.0 - u), minf(v, 1.0 - v))
			var h := clampf(edge / 0.05, 0.0, 1.0)
			heights[y * n + x] = h
			var c := glaze
			var m := _azulejo_motif(u, v, style)
			c = c.lerp(ink, m)
			# A little brush variation in the ink and the glaze.
			var wob := 0.04 * sin(u * 37.0 + v * 11.0) * sin(v * 23.0 - u * 7.0)
			c = Color(c.r + wob, c.g + wob, c.b + wob)
			if h < 1.0:
				c = c.lerp(Color(0.72, 0.7, 0.66), 1.0 - h)
			alb.set_pixel(x, y, c)
			rough.set_pixel(x, y, Color(0.12 + 0.75 * (1.0 - h), 0.0, 0.0))
	for y in n:
		for x in n:
			var hl := heights[y * n + posmod(x - 1, n)]
			var hr := heights[y * n + posmod(x + 1, n)]
			var hu := heights[posmod(y - 1, n) * n + x]
			var hd := heights[posmod(y + 1, n) * n + x]
			var nv := Vector3((hl - hr) * 1.6, (hd - hu) * 1.6, 1.0).normalized()
			nrm.set_pixel(x, y, Color(nv.x * 0.5 + 0.5, nv.y * 0.5 + 0.5, nv.z * 0.5 + 0.5))
	alb.generate_mipmaps()
	nrm.generate_mipmaps()
	rough.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(alb)
	m.normal_enabled = true
	m.normal_texture = ImageTexture.create_from_image(nrm)
	m.normal_scale = 0.8
	m.roughness = 1.0
	m.roughness_texture = ImageTexture.create_from_image(rough)
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.metallic_specular = 0.7
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE / TILE_METERS
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.rim_enabled = true
	m.rim = 0.1
	_mats[key] = m
	return m


## 0..1 ink coverage of the tile motif at (u, v). Quarter circles in the corners
## join four tiles into a ring; a four-petal flower sits in the middle.
static func _azulejo_motif(u: float, v: float, style: int) -> float:
	var ink := 0.0
	for cx: float in [0.0, 1.0]:
		for cy: float in [0.0, 1.0]:
			var d := Vector2(u - cx, v - cy).length()
			if d > 0.27 and d < 0.33:
				ink = 1.0
			if d < 0.13:
				ink = 1.0
	var p := Vector2(u - 0.5, v - 0.5)
	var r := p.length()
	var a := atan2(p.y, p.x)
	var petal := 0.3 * (0.55 + 0.45 * absf(cos(2.0 * a)))
	if style == 1:
		petal = 0.28 * (0.5 + 0.5 * absf(cos(2.0 * a + PI * 0.25)))
	if r < petal and r > 0.07:
		ink = maxf(ink, 1.0)
	if r < 0.035:
		ink = 1.0
	# The diamond that links the flower to the corner rings.
	var dia := absf(p.x) + absf(p.y)
	if dia > 0.43 and dia < 0.47:
		ink = maxf(ink, 0.85)
	return ink


# --- Small shared meshes ----------------------------------------------------------

## A stretched octahedron: the twinkle shape used by every sparkle in the level.
static func sparkle_mesh() -> ArrayMesh:
	if _meshes.has("sparkle"):
		return _meshes["sparkle"]
	var b := VBaker.new()
	var pts := [Vector3(0.0, 1.0, 0.0), Vector3(0.0, -1.0, 0.0)]
	var ring := [Vector3(0.38, 0.0, 0.0), Vector3(0.0, 0.0, 0.38), Vector3(-0.38, 0.0, 0.0), Vector3(0.0, 0.0, -0.38)]
	for i in 4:
		var a: Vector3 = ring[i]
		var c: Vector3 = ring[(i + 1) % 4]
		b._tri(pts[0], c, a, Vector2.ONE)
		b._tri(pts[1], a, c, Vector2.ONE)
	var m := b.bake_mesh()
	_meshes["sparkle"] = m
	return m


## A rounded petal, flat in XZ. Two-sided material.
static func petal_mesh() -> ArrayMesh:
	if _meshes.has("petal"):
		return _meshes["petal"]
	var b := VBaker.new()
	var o := Vector3.ZERO
	var pts: Array[Vector3] = []
	for i in 6:
		var a := TAU * float(i) / 6.0
		pts.append(Vector3(cos(a) * 1.0, 0.0, sin(a) * 0.55))
	for i in 6:
		b._tri(o, pts[(i + 1) % 6], pts[i], Vector2.ONE)
	var m := b.bake_mesh()
	_meshes["petal"] = m
	return m


static func droplet_mesh() -> ArrayMesh:
	if _meshes.has("droplet"):
		return _meshes["droplet"]
	var b := VBaker.new()
	b.blob(Vector3(0.09, 0.14, 0.09), Transform3D.IDENTITY, Color.WHITE, 6, 4)
	var m := b.bake_mesh()
	_meshes["droplet"] = m
	return m


static func bulb_mesh() -> ArrayMesh:
	if _meshes.has("bulb"):
		return _meshes["bulb"]
	var b := VBaker.new()
	b.blob(Vector3(0.11, 0.15, 0.11), Transform3D.IDENTITY, Color.WHITE, 8, 5)
	var m := b.bake_mesh()
	_meshes["bulb"] = m
	return m


## A bunting pennant: a triangle hanging from its top edge, flat in XY.
static func flag_mesh() -> ArrayMesh:
	if _meshes.has("flag"):
		return _meshes["flag"]
	var b := VBaker.new()
	b._tri(Vector3(-0.22, 0.0, 0.0), Vector3(0.22, 0.0, 0.0), Vector3(0.0, -0.42, 0.0), Vector2.ONE)
	var m := b.bake_mesh()
	_meshes["flag"] = m
	return m


## A MultiMeshInstance3D with per-instance colour, every instance hidden at
## scale zero. The caller fills transforms and colours.
static func multimesh(mesh: Mesh, count: int, mat: Material, bounds: AABB,
		node_name: String, custom_data: bool = false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = custom_data
	mm.mesh = mesh
	mm.instance_count = count
	var zero := Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3.ZERO)
	for i in count:
		mm.set_instance_transform(i, zero)
		mm.set_instance_color(i, Color.WHITE)
	mm.custom_aabb = bounds
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


## Where transient spawns go (main.gd clears it every run).
static func spawn_parent(from: Node) -> Node:
	var root := from.get_tree().get_first_node_in_group("spawn_root")
	if root == null:
		root = from.get_tree().current_scene
	return root
