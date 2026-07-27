extends SceneTree
## Throwaway headless harness: builds the ironwork alone and measures it.

func _initialize() -> void:
	var script := load("res://scripts/world/bridge_ironwork.gd")
	if script == null:
		print("!! bridge_ironwork.gd failed to load")
		quit(1)
		return
	var node: Node3D = script.new()
	node.set("report_budget", true)
	root.add_child(node)
	node.call("rebuild")

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
	_clearances()
	quit()


## Cheap swept-AABB overlap test between the arch's transverse cross-frames and
## the suspended road deck's envelope, printed so the clearance is a number
## rather than an assumption.
func _clearances() -> void:
	var c := load("res://scripts/world/bridge/arch_curve.gd")
	var road_top := -12.0 + 1.05
	var road_bottom := -12.0 - 1.11
	print("--- cross-frame clearance (road envelope %.2f .. %.2f) ---" % [
		road_bottom, road_top])
	var t_in: float = c.t_at_height(-12.0 + 1.7, c.LOWER)
	var t_out: float = c.t_at_height(-12.0 - 1.8, c.UPPER)
	print("  lower-chord frames end at x=%.1f, chord y there=%.2f (%.2f clear)" % [
		t_in * c.HALF_SPAN, c.chord_y(t_in, c.LOWER), c.chord_y(t_in, c.LOWER) - road_top])
	print("  upper-chord frames start at x=%.1f, chord y there=%.2f (%.2f clear)" % [
		t_out * c.HALF_SPAN, c.chord_y(t_out, c.UPPER),
		road_bottom - c.chord_y(t_out, c.UPPER)])
	print("  rib inner face at those x: %.2f and %.2f (road half-width 4.51)" % [
		c.rib_z(t_in) - c.RIB_WIDTH * 0.5, c.rib_z(t_out) - c.RIB_WIDTH * 0.5])
