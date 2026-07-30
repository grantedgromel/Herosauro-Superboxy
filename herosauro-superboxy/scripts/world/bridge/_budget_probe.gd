extends SceneTree
## Throwaway headless harness: builds the ironwork alone and measures it, then
## checks the tram rail's own geometry.

const DeckKit := preload("res://scripts/world/bridge/deck_kit.gd")


func _initialize() -> void:
	_rail_winding()
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


## The rail crown must face UP, on both rails.
##
## This check exists because it caught a real one. MeshBaker derives a flat normal
## from each triangle's vertex order, so a crown wound the wrong way is not simply
## back-facing — it is a polished metal shaded as though it were looking at the
## riverbed, and it renders as a black line down a sunlit deck. That is exactly
## what the first render of this rail produced, and no amount of material tuning
## would have found it.
##
## Both rails are checked because the winding has to flip between them: the arc is
## walked from the gauge face outward, which is +Z on one rail and -Z on the other.
func _rail_winding() -> void:
	print("--- tram rail ---")
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var steel := MeshBaker.new()
		var rust := MeshBaker.new()
		DeckKit.grooved_rail(steel, rust, -4.0, 4.0, s * 0.72, 2.004, 1.98, 4801)
		var mi := steel.commit(null, "Crown", false)
		var arrays: Array = (mi.mesh as ArrayMesh).surface_get_arrays(0)
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var up := 0
		var down := 0
		for n in normals:
			if n.y > 0.3:
				up += 1
			elif n.y < -0.3:
				down += 1
		print("  rail z=%+.2f  steel tris=%d  up-facing verts=%d  down-facing=%d  %s" % [
			s * 0.72, steel.triangle_count(), up, down,
			"ok" if down == 0 and up > 0 else "!! CROWN IS INVERTED"])
		print("  rail z=%+.2f  furniture tris=%d" % [s * 0.72, rust.triangle_count()])
		mi.free()


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
