extends SceneTree
## Throwaway budget + correctness probe for TerrainBuilder. Not shipped.
##
## Run:
##   godot --headless --path . --script scripts/world/terrain/_terrain_probe.gd

const TB := preload("res://scripts/world/terrain_builder.gd")
const TerrainBatch := preload("res://scripts/world/terrain/terrain_batch.gd")

## Anything above this inside the bridge landing is standing in the arch.
const WATER_LINE := -14.9

var _fails := 0


## If _initialize() aborts on a runtime error the tree would otherwise idle
## forever with nothing to run. Quitting on the first frame keeps a broken probe
## a failed run rather than a hung one.
func _process(_delta: float) -> bool:
	return true


func _initialize() -> void:
	var root := TB.build()
	print("=== budget ===")
	for k in ["triangles", "surfaces", "near_triangles", "far_triangles",
			"near_surfaces", "far_surfaces"]:
		print("  %-16s %s" % [k, TB.last_stats[k]])
	_per_surface(root)

	print("=== corridor containment ===")
	_check_corridor(root)
	print("=== ground sheet winding ===")
	_check_winding(root)
	print("=== height query vs mesh ===")
	_check_heights()
	print("=== landmark shelves ===")
	_report_shelves()
	print("=== plots ===")
	_check_plots()
	print("=== determinism ===")
	_check_determinism()
	print("=== bounds ===")
	_check_bounds(root)
	print("=== FAILURES: %d ===" % _fails)
	quit()


func _fail(msg: String) -> void:
	_fails += 1
	print("  FAIL  " + msg)


func _meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		_meshes(c, out)


func _all(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_meshes(root, out)
	return out


func _per_surface(root: Node) -> void:
	for mi in _all(root):
		var arrays := (mi.mesh as ArrayMesh).surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var tris := (idx.size() if idx.size() > 0 else verts.size()) / 3
		var mat := mi.material_override as StandardMaterial3D
		print("  %-16s tris %6d  verts %6d  albedo %s  shadow %s" % [
			mi.name, tris, verts.size(),
			("-" if mat == null else mat.albedo_color.to_html(false)),
			mi.cast_shadow])


## Nothing may enter x in [-50, 50], z in [-6, 6] above y = 2 — the corridor the
## hero fights in. Checked per vertex, not per AABB.
func _check_corridor(root: Node) -> void:
	var worst := 0
	for mi in _all(root):
		var verts: PackedVector3Array = (mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for v in verts:
			if absf(v.x) < 50.0 and absf(v.z) < 6.0 and v.y > 2.0:
				worst += 1
	if worst > 0:
		_fail("%d vertices inside the play corridor" % worst)
	else:
		print("  clear: no vertex in |x|<50, |z|<6, y>2")

	# The bridge landing. Quay steps and boulders are allowed to stand out in the
	# river — that is what a quay looks like — but nothing may be inside |x| = 50
	# anywhere near the abutments (x in [49.5, 58.5], z in [-7.5, 7.5]) or it
	# fouls the arch springing at x = +-47.
	var min_ax := 1e9
	var landing := 0
	for mi in _all(root):
		var verts: PackedVector3Array = (mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for v in verts:
			min_ax = minf(min_ax, absf(v.x))
			if absf(v.x) < 50.0 and absf(v.z) < 14.0 and v.y > WATER_LINE:
				landing += 1
	print("  closest approach to the centreline: |x| = %.2f" % min_ax)
	if landing > 0:
		_fail("%d vertices in the bridge landing volume" % landing)
	if min_ax < 42.0:
		_fail("terrain reaches |x| = %.2f, well inside the arch springing" % min_ax)


## Every triangle of the cobbled platforms must face up, and must be seen from
## above. It is the cheapest test for the grid winding, which flips with the sign
## of the bank.
##
## Two things this used to get wrong, and both were invisible because the check
## silently matched nothing and passed on an empty set:
##
##   * it selected the paving by comparing `albedo_color` to the batch's raw
##    `COBBLE` constant, but ToonFactory remaps every colour through
##    `_physical_albedo` on the way into the material, so the comparison stopped
##     matching the moment that landed. It now asks TerrainBatch for the material
##     it actually uses and compares identity — the factory caches by parameter
##     set, so the paving surfaces share one instance — and fails outright if it
##     finds no paving at all.
##   * it tested the right-hand normal of the emitted vertex order, which is the
##     CULLING direction, not the shading one, and asserted it points up. Godot's
##     front face is the clockwise one, so an up-facing surface's emitted
##     right-hand normal points DOWN; asserting otherwise is asserting that the
##     paving is invisible from above, which for a long time it was. Both are
##     checked now, in the directions MeshBaker's contract gives them.
func _check_winding(root: Node) -> void:
	var paving := TerrainBatch.cobble_mat()
	var surfaces := 0
	for mi in _all(root):
		if mi.material_override != paving:
			continue
		surfaces += 1
		var arrays := (mi.mesh as ArrayMesh).surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var shaded_down := 0
		var back_facing := 0
		var n := idx.size() / 3
		for t in n:
			var a := verts[idx[t * 3]]
			var b := verts[idx[t * 3 + 1]]
			var c := verts[idx[t * 3 + 2]]
			if norms[idx[t * 3]].y < 0.3:
				shaded_down += 1
			if (b - a).cross(c - a).normalized().y > -0.3:
				back_facing += 1
		if shaded_down > 0:
			_fail("%s: %d/%d paving triangles shaded from below" % [mi.name, shaded_down, n])
		elif back_facing > 0:
			_fail("%s: %d/%d paving triangles culled from above" % [mi.name, back_facing, n])
		else:
			print("  %s: all %d paving triangles face up and render" % [mi.name, n])
	if surfaces == 0:
		_fail("no paving surfaces found — the check matched nothing and proved nothing")


## ground_height() has to be sane before anything can be placed with it: finite,
## never above the crest, water outside the banks, and continuous across the
## terrace fronts where the geometry is welded.
func _check_heights() -> void:
	var bad := 0
	var z := TB.BANK_Z_FAR
	while z <= TB.HEADLAND_Z:
		var x := -190.0
		while x <= 190.0:
			var y := TB.ground_height(x, z)
			if is_nan(y) or is_inf(y) or y < TB.WATER_Y - 0.01 or y > 26.0:
				bad += 1
			x += 2.0
		z += 3.0
	if bad > 0:
		_fail("%d ground_height samples out of range" % bad)
	else:
		print("  all samples finite and within [water, 26]")

	# Water where there should be water.
	for zz in [-100.0, -40.0, 0.0, 20.0]:
		if not is_equal_approx(TB.ground_height(0.0, zz), TB.WATER_Y):
			_fail("mid-river at z=%.0f is not water" % zz)

	# Continuity: no step bigger than the biggest riser anywhere across the bank.
	var worst := 0.0
	var worst_at := Vector2.ZERO
	for side in [TB.PORTO, TB.GAIA]:
		var zz := TB.BANK_Z_FAR + 1.0
		while zz < TB.BANK_Z_NEAR:
			var ax := 53.0
			while ax < 178.0:
				var d := absf(TB.ground_height(side * ax, zz) - TB.ground_height(side * (ax + 0.5), zz))
				if d > worst:
					worst = d
					worst_at = Vector2(side * ax, zz)
				ax += 0.5
			zz += 2.0
	print("  largest 0.5 m step in the ground: %.2f at (%.1f, %.1f)" % [worst, worst_at.x, worst_at.y])
	if worst > 5.6:
		_fail("ground steps %.2f in half a metre — a terrace riser is discontinuous" % worst)

	# Reported terrace tops, for the integration notes.
	for side in [TB.PORTO, TB.GAIA]:
		var label := "PORTO" if side < 0.0 else "GAIA "
		for l in TB.level_count(side):
			print("  %s L%d  front |x|=%6.2f  top y=%6.2f  ground(front+3)=%6.2f" % [
				label, l, absf(TB.front_x(side, l, 0.0)), TB.terrace_top(side, l, 0.0),
				TB.ground_height(TB.front_x(side, l, 0.0) + (-side) * -3.0, 0.0)])


## Flat ground the landmark stream needs: the Serra do Pilar plateau on Gaia and
## the shoulder on Porto that Clerigos has to clear the rooflines from.
func _report_shelves() -> void:
	for x in [100.0, 106.0, 112.0, 118.0]:
		print("  Serra plateau  x=%6.1f  z=-40: %6.2f  z=-34: %6.2f  z=-24: %6.2f" % [
			x, TB.ground_height(x, -40.0), TB.ground_height(x, -34.0),
			TB.ground_height(x, -24.0)])
	for x in [-136.0, -150.0, -164.0, -180.0]:
		print("  Porto upland   x=%6.1f  z=-40: %6.2f  z=-20: %6.2f  z=  0: %6.2f" % [
			x, TB.ground_height(x, -40.0), TB.ground_height(x, -20.0),
			TB.ground_height(x, 0.0)])


func _check_plots() -> void:
	for side in [TB.PORTO, TB.GAIA]:
		var plots := TB.building_plots(side)
		var label := "PORTO" if side < 0.0 else "GAIA "
		var per_level := {}
		var floating := 0
		var in_corridor := 0
		for p in plots:
			var c: Vector3 = p["center"]
			per_level[p["level"]] = int(per_level.get(p["level"], 0)) + 1
			if absf(c.y - TB.ground_height(c.x, c.z)) > 0.001:
				floating += 1
			if absf(c.x) < 55.0:
				in_corridor += 1
		print("  %s %d plots %s" % [label, plots.size(), per_level])
		if floating > 0:
			_fail("%s: %d plot centres do not sit on ground_height()" % [label, floating])
		if in_corridor > 0:
			_fail("%s: %d plots inside |x| < 55" % [label, in_corridor])

		# Overlap within a level.
		var overlaps := 0
		for i in range(plots.size() - 1):
			var a: Dictionary = plots[i]
			var b: Dictionary = plots[i + 1]
			if int(a["level"]) != int(b["level"]):
				continue
			var az: float = (a["center"] as Vector3).z + float(a["width"]) * 0.5
			var bz: float = (b["center"] as Vector3).z - float(b["width"]) * 0.5
			if bz < az - 0.001:
				overlaps += 1
		if overlaps > 0:
			_fail("%s: %d overlapping plots" % [label, overlaps])

		# Facing and depth sanity.
		for p in plots:
			if (p["facing"] as Vector3).length() < 0.99:
				_fail("plot facing is not unit")
				break
			if float(p["depth"]) < 4.0 or float(p["width"]) < 2.5:
				_fail("plot too small: %.2f x %.2f" % [p["depth"], p["width"]])
				break


func _check_determinism() -> void:
	var a := TB.build()
	var first: Dictionary = TB.last_stats.duplicate()
	var b := TB.build()
	var second: Dictionary = TB.last_stats.duplicate()
	if first != second:
		_fail("build() is not deterministic: %s vs %s" % [first, second])
	else:
		print("  two builds agree on %d triangles" % first["triangles"])
	a.free()
	b.free()


func _check_bounds(root: Node) -> void:
	var total := AABB()
	var first := true
	for mi in _all(root):
		var box := (mi.mesh as ArrayMesh).get_aabb()
		if first:
			total = box
			first = false
		else:
			total = total.merge(box)
	print("  aabb pos %s size %s" % [total.position, total.size])
	print("  x %.1f..%.1f   y %.1f..%.1f   z %.1f..%.1f" % [
		total.position.x, total.end.x, total.position.y, total.end.y,
		total.position.z, total.end.z])
	# What this is really protecting is the LANDMARKS' skyline: the Sé's towers top
	# out at 41.2 and Clérigos at 53, and if the ground or its planting climbs into
	# that band the one thing that makes the far bank Porto stops being the tallest
	# thing on it. 26 was the right number while the upland was bare ground; the
	# crest now carries cypresses, which is what a Douro ridge line actually is, and
	# they reach 29. 33 keeps eight metres of clear sky under the Sé.
	if total.end.y > 33.0:
		_fail("terrain reaches y = %.1f, into the landmarks' skyline" % total.end.y)
