extends SceneTree
## Evidence for the MeshBaker normal issue. Throwaway; run it, read it, and it
## can go the moment mesh_baker.gd is fixed.
##
##   godot --headless --path . --script res://scripts/world/landmarks/_winding_probe.gd
##
## What it shows: Godot's own BoxMesh, SphereMesh and CylinderMesh all store
## normals *opposite* to the right-hand cross product of their vertex order, and
## SurfaceTool.generate_normals() on a triangle whose right-hand normal is +Z
## returns (0, 0, -1). Both say the same thing — the engine's front face is the
## clockwise one, so a triangle's outward normal is -RH(a, b, c).
##
## MeshBaker stores +RH(a, b, c). Its geometry is therefore lit as though every
## surface faced inward. The fix is one place (mesh_baker.gd) and one line, and
## it must not be worked around in the callers; see landmarks_builder.gd's
## header note.
##
## A baked surface whose triangles wind the wrong way is culled from outside and
## solid from inside, and no headless test catches that unless it is asked. Two
## independent references are used here:
##
##   1. Godot's own BoxMesh / SphereMesh / CylinderMesh, whose ARRAY_NORMALs are
##      known-good, so the sign between their winding-derived normal and their
##      stored normal *is* the engine's convention.
##   2. SurfaceTool.generate_normals(), which derives a normal from vertex order
##      using that same engine convention.

const MB := preload("res://scripts/world/mesh_baker.gd")


func _initialize() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(2, 2, 2)
	_measure("godot BoxMesh", box, Vector3.ZERO)

	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	_measure("godot SphereMesh", sph, Vector3.ZERO)

	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 2.0
	_measure("godot CylinderMesh", cyl, Vector3.ZERO)

	var b1 = MB.new()
	b1.add_box(Vector3(2, 2, 2), Transform3D.IDENTITY)
	_measure("MeshBaker.add_box", b1.commit(null, "p", false).mesh, Vector3.ZERO)

	var b2 = MB.new()
	b2.add_cylinder(1.0, 2.0, Transform3D.IDENTITY, 8, true)
	_measure("MeshBaker.add_cylinder", b2.commit(null, "p", false).mesh, Vector3.ZERO)

	var b3 = MB.new()
	b3.add_roof_prism(4.0, 2.0, 4.0, Transform3D.IDENTITY)
	_measure("MeshBaker.add_roof_prism", b3.commit(null, "p", false).mesh, Vector3(0, 0.6, 0))

	var b4 = MB.new()
	b4.add_beam(Vector3(-2, 0, 0), Vector3(2, 0, 0), 0.5)
	_measure("MeshBaker.add_beam", b4.commit(null, "p", false).mesh, Vector3.ZERO)

	_generated_normal()
	quit()


## `interior` is a point inside the convex shape: a triangle's winding normal
## (the right-hand cross product of its vertex order) points away from it or
## toward it, and that sign is the whole question.
func _measure(label: String, mesh: Mesh, interior: Vector3) -> void:
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var away := 0
	var toward := 0
	var normal_agrees := 0
	var normal_opposes := 0
	var count := idx.size() if idx.size() > 0 else verts.size()
	for i in range(0, count, 3):
		var ia := idx[i] if idx.size() > 0 else i
		var ib := idx[i + 1] if idx.size() > 0 else i + 1
		var ic := idx[i + 2] if idx.size() > 0 else i + 2
		var a := verts[ia]
		var b := verts[ib]
		var c := verts[ic]
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-12:
			continue
		n = n.normalized()
		var centroid := (a + b + c) / 3.0
		if n.dot((centroid - interior).normalized()) > 0.0:
			away += 1
		else:
			toward += 1
		if norms.size() > 0:
			if n.dot(norms[ia]) > 0.0:
				normal_agrees += 1
			else:
				normal_opposes += 1
	print("%-24s winding-normal: away=%4d toward=%4d | vs stored normal: same=%4d opposite=%4d" % [
		label, away, toward, normal_agrees, normal_opposes])


## One triangle, wound a->b->c with a right-hand normal of exactly +Z. Whatever
## SurfaceTool decides its normal is, that is the engine's front direction.
func _generated_normal() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.add_vertex(Vector3(0, 0, 0))
	st.add_vertex(Vector3(1, 0, 0))
	st.add_vertex(Vector3(1, 1, 0))
	st.index()
	st.generate_normals()
	var arrays: Array = st.commit().surface_get_arrays(0)
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	print("SurfaceTool.generate_normals on a +Z right-hand triangle -> %s" % str(norms[0]))
