extends SceneTree
## Throwaway headless harness: builds the ironwork alone and measures it.

func _initialize() -> void:
	var script := load("res://scripts/world/bridge_ironwork.gd")
	var node: Node3D = script.new()
	node.set("report_budget", true)
	root.add_child(node)

	var tris := 0
	var surfaces := 0
	var corridor := 0
	var lowest := 1e9
	var highest := -1e9
	for child in node.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var mesh: Mesh = mi.mesh
		var t := 0
		for s in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			t += (idx.size() / 3) if idx.size() > 0 else (verts.size() / 3)
			for v in verts:
				if is_nan(v.x) or is_nan(v.y) or is_nan(v.z):
					print("  !! NaN vertex in ", mi.name)
					break
				lowest = minf(lowest, v.y)
				highest = maxf(highest, v.y)
				# The playable corridor: nothing may sit above the walkable
				# surface inside the fighting box.
				if v.y > 2.001 and absf(v.x) < 50.0 and absf(v.z) < 6.0:
					corridor += 1
			surfaces += 1
		var aabb := mesh.get_aabb()
		print("  %-16s surfaces=%d  tris=%6d  aabb pos=%s size=%s" % [
			mi.name, mesh.get_surface_count(), t,
			str(aabb.position.round()), str(aabb.size.round())])
		tris += t
	print("TOTAL  triangles=%d  draw_calls=%d" % [tris, surfaces])
	print("Y range: %.2f .. %.2f" % [lowest, highest])
	print("Corridor violations (y>2 inside |x|<50,|z|<6): %d" % corridor)
	quit()
