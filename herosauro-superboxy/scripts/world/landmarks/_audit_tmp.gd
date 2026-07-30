extends SceneTree
## TEMPORARY caller-winding audit. Delete after the mesh_baker normal fix lands.

const FB := preload("res://scripts/world/facade_builder.gd")
const FBatch := preload("res://scripts/world/facade/facade_batch.gd")
const LB := preload("res://scripts/world/landmarks_builder.gd")
const TB := preload("res://scripts/world/terrain_builder.gd")
const IW := preload("res://scripts/world/bridge_ironwork.gd")


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20250727
	var fb := FBatch.new()
	var spec := FB.random_spec(rng, 14.0, 16.0)
	spec.detail = FB.Detail.FULL
	FB.add_to_batch(fb, spec, rng)
	_walk("facade FULL", fb.commit("F"))

	_walk("skyline", LB.porto_skyline())
	_walk("terrain", TB.build())

	var root := Node3D.new()
	get_root().add_child(root)
	var iron := IW.attach(root)
	_walk("ironwork", iron)

	quit()


func _walk(label: String, node: Node) -> void:
	print("--- %s ---" % label)
	_recurse(label, node)


func _recurse(label: String, node: Node) -> void:
	var mi := node as MeshInstance3D
	if mi and mi.mesh:
		for s in mi.mesh.get_surface_count():
			_report("%s / %s[%d]" % [label, mi.name, s], mi.mesh.surface_get_arrays(s))
	for c in node.get_children():
		_recurse(label, c)


func _report(label: String, arrays: Array) -> void:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var count := idx.size() if idx.size() > 0 else verts.size()
	if count == 0:
		return
	var aabb := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		aabb = aabb.expand(v)
	var centre := aabb.get_center()
	var vol := 0.0
	var away := 0
	var toward := 0
	var up := 0
	var down := 0
	for i in range(0, count, 3):
		var ia := idx[i] if idx.size() > 0 else i
		var ib := idx[i + 1] if idx.size() > 0 else i + 1
		var ic := idx[i + 2] if idx.size() > 0 else i + 2
		var a := verts[ia]
		var b := verts[ib]
		var c := verts[ic]
		vol += a.dot(b.cross(c)) / 6.0
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-14:
			continue
		n = n.normalized()
		if n.dot(((a + b + c) / 3.0 - centre).normalized()) > 0.0:
			away += 1
		else:
			toward += 1
		if absf(n.y) > 0.8:
			if n.y > 0.0:
				up += 1
			else:
				down += 1
	print("  %-46s tris=%6d  signedvol=%+10.2f  RH away=%6d toward=%6d | flat-up=%5d flat-down=%5d" % [
		label, count / 3, vol, away, toward, up, down])
