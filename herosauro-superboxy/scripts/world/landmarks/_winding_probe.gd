extends SceneTree
## The winding gate for MeshBaker. Permanent, and it exits non-zero.
##
##   godot --headless --path . --script res://scripts/world/landmarks/_winding_probe.gd
##
## MeshBaker's contract (stated in full at the top of mesh_baker.gd) is that a
## face is wound so the RIGHT-HAND cross product of its vertex order points the
## way the surface faces. Every emitter in that file and every caller in
## `scripts/world/` is written to it. Godot's rasteriser wants the mirror image —
## its front face is the one whose right-hand normal points away from the camera
## — so `_tri_uv` reverses the vertices on the way into the surface and keeps
## `+RH` as the shading normal.
##
## That leaves two independent ways to be wrong, and a primitive can be wrong in
## either without anything erroring:
##
##   NORMAL  — the stored shading normal points into the solid. The surface
##             renders, but `N.L < 0` for every light outside it, so it returns
##             ambient and nothing else. This is what round 1 measured on the
##             ironwork: mean RGB (11, 16, 27), sigma 3, no specular anywhere
##             along a top rail standing against a 210-blue sky.
##   CULLING — the emitted vertex order makes the triangle back-facing, so the
##             surface is not dark, it is ABSENT, and only visible from the side
##             it does not face. Round 1's "full-width polygon that receives no
##             light, RGB (0, 1, 2), sigma 0.0" under the deck was a hole of
##             exactly this kind, and so were the terrace ground sheets, the
##             punched facade skins, the grooved tram rail and the landmark
##             roofs.
##
## So every primitive is checked BOTH ways here, and both checks are made against
## measured references rather than against the convention as remembered:
##
##   1. Godot's own BoxMesh / SphereMesh / CylinderMesh, whose ARRAY_NORMALs are
##      known-good, so the sign between their winding-derived normal and their
##      stored normal *is* the engine's convention.
##   2. SurfaceTool.generate_normals(), which derives a normal from vertex order
##      using that same convention.
##
## Both are asserted before anything about MeshBaker is, so if a future Godot
## ever changes its front face this file fails on the references first and says
## so, rather than quietly passing a now-inverted MeshBaker.
##
## ADDING A PRIMITIVE TO MeshBaker MEANS ADDING IT HERE. A new emitter that is
## culled or lit inside out looks like an art problem for weeks; it took three
## rounds of critics asking for "more material work" to find this one.

const MB := preload("res://scripts/world/mesh_baker.gd")

## Numerical slack on a dot product that should be a clean +1 or -1. Everything
## measured here is flat-shaded, so the only error is float rounding.
const EPS := 1e-5

var _fails := 0


func _initialize() -> void:
	print("=== engine convention (references) ===")
	_check_references()
	print("=== MeshBaker primitives ===")
	_check_primitives()
	print("=== %s: %d failure(s) ===" % ["FAIL" if _fails > 0 else "PASS", _fails])
	quit(1 if _fails > 0 else 0)


# --- References ---------------------------------------------------------------

## Godot's own primitives, and the sign between their winding and their normals.
## The expectation is `opposite`: a Godot outward normal is -RH(a, b, c).
func _check_references() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(2, 2, 2)
	_reference("godot BoxMesh", box)

	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	_reference("godot SphereMesh", sph)

	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 2.0
	_reference("godot CylinderMesh", cyl)

	# One triangle, wound a->b->c with a right-hand normal of exactly +Z.
	# Whatever SurfaceTool decides its normal is, that is the engine's front
	# direction, derived a second way.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.add_vertex(Vector3(0, 0, 0))
	st.add_vertex(Vector3(1, 0, 0))
	st.add_vertex(Vector3(1, 1, 0))
	st.index()
	st.generate_normals()
	var norms: PackedVector3Array = st.commit().surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	_expect("SurfaceTool.generate_normals(+Z right-hand tri) = -Z",
			norms[0].dot(Vector3(0, 0, -1)) > 1.0 - EPS, "got %s" % str(norms[0]))


func _reference(label: String, mesh: Mesh) -> void:
	var same := 0
	var opposite := 0
	for t in _triangles(mesh):
		var rh: Vector3 = t[3]
		if rh.dot(t[4]) > 0.0:
			same += 1
		else:
			opposite += 1
	_expect("%s stores -RH as its outward normal" % label, same == 0 and opposite > 0,
			"same=%d opposite=%d" % [same, opposite])


# --- MeshBaker ----------------------------------------------------------------

func _check_primitives() -> void:
	var b := MB.new()
	b.add_box(Vector3(2, 2, 2), Transform3D.IDENTITY)
	_solid("add_box", b, Vector3.ZERO, 12)

	# The same box moved and turned. A transform applied in the wrong order, or a
	# basis that mirrors, flips the winding back without touching the table above.
	var turned := Transform3D(Basis(Vector3(0.3, 1.0, 0.2).normalized(), 0.9),
			Vector3(5.0, -2.0, 3.0))
	var b_turned := MB.new()
	b_turned.add_box(Vector3(3, 1, 2), turned)
	_solid("add_box (rotated, translated)", b_turned, turned.origin, 12)

	var cyl := MB.new()
	cyl.add_cylinder(1.0, 2.0, Transform3D.IDENTITY, 8, true)
	_solid("add_cylinder (capped)", cyl, Vector3.ZERO, 32)

	var open_cyl := MB.new()
	open_cyl.add_cylinder(1.0, 2.0, Transform3D.IDENTITY, 8, false)
	_solid("add_cylinder (open)", open_cyl, Vector3.ZERO, 16)

	# A prism is not centred on its own origin: its interior sits low, between the
	# base and the ridge.
	var roof := MB.new()
	roof.add_roof_prism(4.0, 2.0, 4.0, Transform3D.IDENTITY)
	_solid("add_roof_prism", roof, Vector3(0.0, 0.6, 0.0), 8)

	var beam := MB.new()
	beam.add_beam(Vector3(-2, 0, 0), Vector3(2, 0, 0), 0.5)
	_solid("add_beam (horizontal)", beam, Vector3.ZERO, 12)

	# Near-vertical beams take the other branch for their reference perpendicular,
	# which builds a different basis and could differ in handedness.
	var post := MB.new()
	post.add_beam(Vector3(1, -1.5, -1), Vector3(1, 1.5, -1), 0.4)
	_solid("add_beam (vertical)", post, Vector3(1, 0, -1), 12)

	# add_quad is the raw interface, so it is checked against the direction the
	# caller asked for rather than against an interior point: a ground quad wound
	# to the contract faces +Y.
	var ground := MB.new()
	ground.add_quad(Vector3(-1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, -1))
	_faces("add_quad (ground, right-hand normal +Y)", ground, Vector3.UP, 2)

	var wall := MB.new()
	wall.add_quad(Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(1, 2, 0), Vector3(-1, 2, 0))
	_faces("add_quad (wall, right-hand normal +Z)", wall, Vector3(0, 0, 1), 2)

	# The degenerate-fourth-corner idiom several callers use to emit one triangle
	# for the price of writing a quad.
	var tri := MB.new()
	tri.add_quad(Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 2, 0), Vector3(0, 2, 0))
	_faces("add_quad (degenerate 4th corner)", tri, Vector3(0, 0, 1), 1)


## A closed primitive: `interior` is a point inside it, so "outward" is knowable
## per triangle without being told face by face.
func _solid(label: String, baker: Variant, interior: Vector3, want_tris: int) -> void:
	var tris := _baked(baker)
	var bad_normal := 0
	var bad_cull := 0
	for t in tris:
		var out: Vector3 = ((t[0] + t[1] + t[2]) / 3.0 - interior).normalized()
		if (t[4] as Vector3).dot(out) <= 0.0:
			bad_normal += 1                       # shading normal points inward
		if (t[3] as Vector3).dot(out) >= 0.0:
			bad_cull += 1                         # emitted winding is back-facing
	_report(label, tris.size(), want_tris, bad_normal, bad_cull)


## An open surface: every triangle should face `want` and be seen from that side.
func _faces(label: String, baker: Variant, want: Vector3, want_tris: int) -> void:
	var tris := _baked(baker)
	var bad_normal := 0
	var bad_cull := 0
	for t in tris:
		if (t[4] as Vector3).dot(want) <= 1.0 - EPS:
			bad_normal += 1
		if (t[3] as Vector3).dot(want) >= 0.0:
			bad_cull += 1
	_report(label, tris.size(), want_tris, bad_normal, bad_cull)


func _report(label: String, got_tris: int, want_tris: int, bad_normal: int, bad_cull: int) -> void:
	_expect("%-34s emits %d triangles" % [label, want_tris], got_tris == want_tris,
			"got %d" % got_tris)
	_expect("%-34s stores outward normals" % label, bad_normal == 0,
			"%d of %d point inward" % [bad_normal, got_tris])
	_expect("%-34s renders from outside" % label, bad_cull == 0,
			"%d of %d are back-facing" % [bad_cull, got_tris])


# --- Machinery ----------------------------------------------------------------

func _baked(baker: Variant) -> Array:
	# LODs off: the simplifier is allowed to move vertices, and this measures the
	# geometry the baker authored.
	var mi: MeshInstance3D = baker.commit(null, "probe", false)
	var tris := _triangles(mi.mesh)
	mi.free()
	return tris


## Every triangle as [a, b, c, right-hand normal of the EMITTED order, stored
## normal]. The two normals are the two independent things that can be wrong:
## the fourth entry decides culling, the fifth decides shading.
func _triangles(mesh: Mesh) -> Array:
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var count := idx.size() if idx.size() > 0 else verts.size()
	var out := []
	for i in range(0, count, 3):
		var ia := idx[i] if idx.size() > 0 else i
		var ib := idx[i + 1] if idx.size() > 0 else i + 1
		var ic := idx[i + 2] if idx.size() > 0 else i + 2
		var a := verts[ia]
		var b := verts[ib]
		var c := verts[ic]
		var rh := (b - a).cross(c - a)
		if rh.length_squared() < 1e-14:
			continue
		out.append([a, b, c, rh.normalized(), norms[ia]])
	return out


func _expect(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok    %s" % label)
	else:
		_fails += 1
		print("  FAIL  %s  --  %s" % [label, detail])
