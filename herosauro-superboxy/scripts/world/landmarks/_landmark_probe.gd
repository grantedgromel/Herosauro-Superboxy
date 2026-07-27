extends SceneTree
## Throwaway budget + correctness probe for LandmarksBuilder. Not shipped.
##
##   godot --headless --path . --script res://scripts/world/landmarks/_landmark_probe.gd
##
## Three questions it answers, none of which a running scene would answer any
## faster and two of which nothing but a render would answer at all:
##   1. what each landmark costs in triangles and draw calls, per detail level;
##   2. whether the emitters point the way they claim to (a dome facing inward
##      is invisible, and looks exactly like a dome that was never built);
##   3. whether anything lands in the playable corridor.

const LB := preload("res://scripts/world/landmarks_builder.gd")
const Geo := preload("res://scripts/world/landmarks/landmark_geo.gd")

var _fails := 0


func _initialize() -> void:
	print("=== per-landmark budget ===")
	for detail in [LB.Detail.FULL, LB.Detail.MEDIUM, LB.Detail.LOW]:
		var label: String = ["LOW", "MEDIUM", "FULL"][detail]
		print("-- detail %s" % label)
		_report("Clerigos", LB.clerigos_tower(detail))
		_report("Se", LB.se_cathedral(detail))
		_report("SerraDoPilar", LB.serra_do_pilar(detail))
		_report("IgrejaAzulejo", LB.igreja_azulejo(detail))
		_report("GaiaLodges x4", LB.gaia_lodges(4, detail))

	print("\n=== whole skyline, one batch ===")
	for detail in [LB.Detail.FULL, LB.Detail.MEDIUM, LB.Detail.LOW]:
		var label: String = ["LOW", "MEDIUM", "FULL"][detail]
		var sky := LB.porto_skyline(detail)
		var stats := _stats(sky)
		print("%-7s triangles=%6d  draw_calls=%d  surfaces_per_node=%s" % [
			label, stats.tris, stats.surfaces, str(stats.per_node)])
		if detail == LB.Detail.FULL:
			_corridor(sky)
			_heights(sky)
		sky.free()

	print("\n=== orientation ===")
	_check_orientation()

	print("\n=== build cost and tree entry ===")
	_check_build_cost()

	print("\n=== %s ===" % ("ALL CLEAR" if _fails == 0 else "%d FAILURES" % _fails))
	quit(1 if _fails > 0 else 0)


## Baking moves cost from per-frame to per-load, so the per-load number is the
## one that has to stay small — it lands on the loading screen either way, but a
## second of it would be felt.
func _check_build_cost() -> void:
	# Split the two phases: emitting geometry is cheap, and welding + tangents +
	# LOD generation in MeshBaker.commit() is where the milliseconds go.
	var batch = LB.Batch.new()
	var t0 := Time.get_ticks_usec()
	LB.add_clerigos_tower(batch, Transform3D.IDENTITY, LB.Detail.FULL)
	LB.add_se_cathedral(batch, Transform3D.IDENTITY, LB.Detail.FULL)
	LB.add_serra_do_pilar(batch, Transform3D.IDENTITY, LB.Detail.FULL)
	LB.add_igreja_azulejo(batch, Transform3D.IDENTITY, LB.Detail.FULL)
	var emit_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	var node: Node3D = batch.commit("Timing")
	var commit_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("  four landmarks: emit %.1f ms, commit (weld + tangents + LODs) %.1f ms"
			% [emit_ms, commit_ms])
	node.free()

	t0 = Time.get_ticks_usec()
	var sky := LB.porto_skyline(LB.Detail.FULL)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("  porto_skyline(FULL) built in %.1f ms" % ms)
	_expect("build stays under 250 ms", ms < 250.0, "%.1f ms" % ms)
	root.add_child(sky)
	_expect("enters the tree", sky.get_parent() == root and sky.get_child_count() > 0,
			"parent=%s children=%d" % [str(sky.get_parent()), sky.get_child_count()])
	sky.queue_free()


# --- Budget ------------------------------------------------------------------

func _report(label: String, node: Node3D) -> void:
	var s := _stats(node)
	var aabb: AABB = s.aabb
	print("  %-14s tris=%6d  draws=%d  size=%s  top=%.1f" % [
		label, s.tris, s.surfaces, str(aabb.size.round()), aabb.end.y])
	if s.nan_verts > 0:
		_fail("%s has %d NaN vertices" % [label, s.nan_verts])
	node.free()


func _stats(node: Node3D) -> Dictionary:
	var tris := 0
	var surfaces := 0
	var nan_verts := 0
	var per_node: Array[int] = []
	var aabb := AABB()
	var first := true
	for child in _meshes(node):
		var mesh: Mesh = child.mesh
		var here := 0
		for s in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			here += (idx.size() / 3) if idx.size() > 0 else (verts.size() / 3)
			for v in verts:
				if is_nan(v.x) or is_nan(v.y) or is_nan(v.z):
					nan_verts += 1
			surfaces += 1
		per_node.append(here)
		tris += here
		var box := child.transform * mesh.get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
	return {"tris": tris, "surfaces": surfaces, "aabb": aabb, "nan_verts": nan_verts,
			"per_node": per_node}


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		found.append(node as MeshInstance3D)
	for child in node.get_children():
		found.append_array(_meshes(child))
	return found


## Nothing may sit above the walkable surface inside the fighting box.
func _corridor(node: Node3D) -> void:
	var bad := 0
	for mi in _meshes(node):
		for s in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var w: Vector3 = mi.transform * v
				if w.y > 2.001 and absf(w.x) < 50.0 and absf(w.z) < 6.0:
					bad += 1
	_expect("playable corridor is clear", bad == 0, "%d vertices inside it" % bad)


## Silhouette sanity: Clérigos has to be the tallest thing out there, by a
## margin big enough to survive being seen from a moving camera.
func _heights(node: Node3D) -> void:
	var tower := LB.clerigos_tower(LB.Detail.FULL)
	var top: float = _stats(tower).aabb.end.y + LB.CLERIGOS_ANCHOR.y
	tower.free()
	var others := {
		"Se": LB.SE_ANCHOR.y + _stats_of(LB.se_cathedral(LB.Detail.FULL)),
		"Serra": LB.SERRA_ANCHOR.y + _stats_of(LB.serra_do_pilar(LB.Detail.FULL)),
		"Igreja": LB.IGREJA_ANCHOR.y + _stats_of(LB.igreja_azulejo(LB.Detail.FULL)),
		"Lodges": LB.LODGE_ANCHOR.y + _stats_of(LB.gaia_lodges(4, LB.Detail.FULL)),
	}
	print("  skyline tops (world y): Clerigos=%.1f %s" % [top, str(others)])
	for key in others:
		_expect("Clerigos clears %s" % key, top > float(others[key]) + 6.0,
				"only %.1f m above it" % (top - float(others[key])))


func _stats_of(node: Node3D) -> float:
	var y: float = _stats(node).aabb.end.y
	node.free()
	return snappedf(y, 0.1)


# --- Orientation -------------------------------------------------------------

## Every emitter states which way its faces point. Check the ones whose failure
## mode is silent: a dome wound inward is not a dark dome, it is no dome.
func _check_orientation() -> void:
	var b := MeshBaker.new()
	Geo.dome(b, Transform3D.IDENTITY, 4.0, 0.0, 3.0, 12, 4)
	_expect_outward("dome faces outward", b, Vector3(0, 1.0, 0))

	b = MeshBaker.new()
	Geo.cyl_shell(b, Transform3D.IDENTITY, 3.0, 0.0, 5.0, 12)
	_expect_outward("cyl_shell faces outward", b, Vector3(0, 2.5, 0))

	b = MeshBaker.new()
	Geo.annulus(b, Transform3D.IDENTITY, 1.0, 3.0, 0.0, 12, true)
	_expect_axis("annulus face_up points +Y", b, Vector3.UP)

	b = MeshBaker.new()
	Geo.annulus(b, Transform3D.IDENTITY, 1.0, 3.0, 0.0, 12, false)
	_expect_axis("annulus face down points -Y", b, Vector3.DOWN)

	b = MeshBaker.new()
	Geo.rect(b, Transform3D.IDENTITY, -1.0, 0.0, 1.0, 2.0, 0.0)
	_expect_axis("rect faces +Z", b, Vector3.BACK)

	b = MeshBaker.new()
	Geo.rect_back(b, Transform3D.IDENTITY, -1.0, 0.0, 1.0, 2.0, 0.0)
	_expect_axis("rect_back faces -Z", b, Vector3.FORWARD)

	b = MeshBaker.new()
	var o := Geo.Opening.arched(0.0, 2.0, 1.0, 2.0, -1.0)
	Geo.fill_outline(b, Transform3D.IDENTITY, o.outline(6), 0.0, true)
	_expect_axis("opening_back faces +Z", b, Vector3.BACK)

	# The punched panel: every surviving strip still faces the street, and the
	# hole is genuinely absent rather than covered over.
	b = MeshBaker.new()
	Geo.panel(b, Transform3D.IDENTITY, -3.0, 0.0, 3.0, 8.0, [o], 0.0, 6)
	_expect_axis("panel faces +Z", b, Vector3.BACK)
	var inside := 0
	for t in _tris(b):
		var c: Vector3 = t[0]
		# Sample well inside the opening, clear of the banding steps.
		if absf(c.x) < 0.7 and c.y > 1.4 and c.y < 2.6:
			inside += 1
	_expect("panel hole is empty", inside == 0, "%d triangles inside the opening" % inside)

	# The reveal turns toward the hole; the archivolt's outer return turns away.
	b = MeshBaker.new()
	Geo.opening_reveal(b, Transform3D.IDENTITY, o, 0.0, -0.5, 6)
	var wrong := 0
	for t in _tris(b):
		var c: Vector3 = t[0]
		var n: Vector3 = t[1]
		var to_axis := Vector3(0.0, 2.0, c.z) - c   # the opening's centre line
		if Vector2(n.x, n.y).dot(Vector2(to_axis.x, to_axis.y)) < 0.0:
			wrong += 1
	_expect("reveal faces into the opening", wrong == 0, "%d faces turned outward" % wrong)


func _tris(b: MeshBaker) -> Array:
	var mi: MeshInstance3D = b.commit(null, "probe", false)
	var arrays: Array = mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var out: Array = []
	for i in range(0, idx.size(), 3):
		var a := verts[idx[i]]
		var c := verts[idx[i + 1]]
		var d := verts[idx[i + 2]]
		out.append([(a + c + d) / 3.0, norms[idx[i]]])
	return out


func _expect_outward(label: String, b: MeshBaker, interior: Vector3) -> void:
	var wrong := 0
	for t in _tris(b):
		var c: Vector3 = t[0]
		if (t[1] as Vector3).dot((c - interior).normalized()) <= 0.0:
			wrong += 1
	_expect(label, wrong == 0, "%d faces turned inward" % wrong)


func _expect_axis(label: String, b: MeshBaker, axis: Vector3) -> void:
	var worst := 1.0
	for t in _tris(b):
		worst = minf(worst, (t[1] as Vector3).dot(axis))
	_expect(label, worst > 0.99, "worst dot = %.3f" % worst)


func _expect(label: String, ok: bool, detail: String) -> void:
	print("  [%s] %s%s" % ["ok" if ok else "FAIL", label, "" if ok else "  (%s)" % detail])
	if not ok:
		_fails += 1


func _fail(msg: String) -> void:
	print("  [FAIL] %s" % msg)
	_fails += 1
