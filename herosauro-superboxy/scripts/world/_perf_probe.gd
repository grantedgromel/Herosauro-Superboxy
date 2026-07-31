extends SceneTree
## TEMPORARY probe — measurement only, delete before commit.
##
## Two questions tools/budget.tscn cannot answer:
##
##   1. WHERE the 1.1M triangles are. budget.tscn reports one total; this reports
##      it per baked surface with the surface's world AABB and its distance from
##      the deck, which is what decides whether a lever can reach it.
##
##   2. How many triangles are submitted to the DIRECTIONAL SHADOW CASCADES, as a
##      function of directional_shadow_max_distance. That is the number the
##      shadow-distance change moved and it is invisible to a scene-graph count:
##      a caster 200 m out costs nothing at max_distance 100 and costs a full
##      re-render of its geometry at 260.
##
## The cascade model mirrors Godot's own. Each cascade covers a slice of the view
## frustum; Godot bounds that slice with a SPHERE (for rotation stability) and
## builds a light-space orthographic box around it. Anything between the light and
## that box also has to be drawn, so in light space the test is a DISC of the
## cascade's radius, unbounded along the light axis. That is what _casts_into()
## implements, so the count here is the real submitted set rather than a proxy.
##
##   godot --headless --path . --script scripts/world/_perf_probe.gd

const CAMERA_NEAR := 0.05
## tools/shots.json, the two shots the review gate compares.
const SHOTS := [
	["01_deck_mid", Vector3(0, 5, 16), Vector3(0, 2.5, 0), 55.0],
	["07_ribeira", Vector3(0, 12, 20), Vector3(0, 10, -60), 55.0],
	["06_river_wide", Vector3(-70, 18, 70), Vector3(10, -2, -20), 50.0],
]
const DISTANCES := [80.0, 100.0, 120.0, 140.0, 160.0, 200.0, 260.0]


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/world/bridge_arena.tscn")
	var root: Node3D = scene.instantiate()
	get_root().add_child(root)
	await process_frame
	await process_frame
	await process_frame

	var entries: Array = []
	_collect(root, entries)
	entries.sort_custom(func(a, b): return a["tris"] > b["tris"])

	var total := 0
	var caster_tris := 0
	var groups: Dictionary = {}
	for e in entries:
		var g: String = String(e["path"]).split("/")[0]
		if String(e["path"]).begins_with("SkyBackground/"):
			g = String(e["path"]).split("/")[1]
		var row: Array = groups.get(g, [0, 0, 0, 0])
		row[0] += 1
		row[1] += e["tris"]
		if e["shadow"]:
			row[2] += 1
			row[3] += e["tris"]
		groups[g] = row
	print("=== GROUPS (%s) ===" % RenderingServer.get_current_rendering_method())
	print("%-22s %8s %10s %8s %10s" % ["group", "surfs", "tris", "castSurf", "castTris"])
	for g in groups:
		var row: Array = groups[g]
		print("%-22s %8d %10d %8d %10d" % [g, row[0], row[1], row[2], row[3]])
	print("=== GEOMETRY BY SURFACE ===")
	print("%-28s %9s %6s %8s  %s" % ["node", "tris", "shadow", "dist_m", "world aabb"])
	for e in entries:
		total += e["tris"]
		if e["shadow"]:
			caster_tris += e["tris"]
		if e["tris"] >= 4000:
			print("%-28s %9d %6s %8.1f  %s .. %s" % [
				e["path"], e["tris"], "Y" if e["shadow"] else "-", e["dist"],
				str(e["aabb"].position.round()), str(e["aabb"].end.round())])
	print("TOTAL triangles %d, of which shadow-casting %d" % [total, caster_tris])

	var sun := _find_sun(root)
	if sun == null:
		print("!! no sun")
		quit(1)
		return
	var light_dir := -sun.global_transform.basis.z.normalized()
	var splits := _splits_of(sun)
	var live := sun.directional_shadow_max_distance
	print("\n=== SHADOW CASCADE SUBMISSION (triangles re-rendered per frame) ===")
	print("cascades %d, splits %s, live max_distance %.0f" % [splits.size() + 1, str(splits), live])
	for shot in SHOTS:
		print("\n-- %s --" % shot[0])
		print("%10s %10s %10s %10s %10s %12s" % [
			"max_dist", "casc0", "casc1", "casc2", "casc3", "TOTAL"])
		var sweep: Array = DISTANCES.duplicate()
		if not sweep.has(live):
			sweep.append(live)
		sweep.sort()
		for d in sweep:
			var per := _cascade_tris(entries, shot[1], shot[2], shot[3], d, light_dir, splits)
			var sum := 0
			for v in per:
				sum += v
			print("%10.0f %10d %10d %10d %10d %12d%s" % [
				d, per[0], per[1] if per.size() > 1 else 0,
				per[2] if per.size() > 2 else 0, per[3] if per.size() > 3 else 0,
				sum, "   <- live" if is_equal_approx(d, live) else ""])
	quit()


## The cascade split fractions this light is actually configured with, so the
## report describes the tier it is running in rather than a hard-coded desktop.
func _splits_of(sun: DirectionalLight3D) -> Array[float]:
	match sun.directional_shadow_mode:
		DirectionalLight3D.SHADOW_ORTHOGONAL:
			return []
		DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS:
			return [sun.directional_shadow_split_1]
	return [sun.directional_shadow_split_1, sun.directional_shadow_split_2,
			sun.directional_shadow_split_3]


# --- Collection --------------------------------------------------------------

func _collect(n: Node, out: Array, path: String = "") -> void:
	var here: String = (path + "/" + n.name) if path != "" else String(n.name)
	var geo := n as GeometryInstance3D
	if geo != null:
		var mesh: Mesh = null
		var count := 1
		if n is MeshInstance3D:
			mesh = (n as MeshInstance3D).mesh
		elif n is MultiMeshInstance3D:
			var mm := (n as MultiMeshInstance3D).multimesh
			if mm != null:
				mesh = mm.mesh
				count = mm.instance_count
		if mesh != null:
			var tris := 0
			for s in mesh.get_surface_count():
				var arr := mesh.surface_get_arrays(s)
				if arr.is_empty():
					continue
				var idx: Variant = arr[Mesh.ARRAY_INDEX]
				var vtx: Variant = arr[Mesh.ARRAY_VERTEX]
				if idx != null and (idx as PackedInt32Array).size() > 0:
					tris += (idx as PackedInt32Array).size() / 3
				elif vtx != null:
					tris += (vtx as PackedVector3Array).size() / 3
			var aabb := geo.global_transform * _instance_aabb(geo, mesh)
			var centre := aabb.position + aabb.size * 0.5
			out.append({
				"path": here.substr(here.find("/") + 1),
				"tris": tris * count,
				"shadow": geo.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"aabb": aabb,
				"dist": Vector2(centre.x, centre.z).length(),
			})
	for c in n.get_children():
		_collect(c, out, here)


func _instance_aabb(geo: GeometryInstance3D, mesh: Mesh) -> AABB:
	if geo is MultiMeshInstance3D:
		var mm := (geo as MultiMeshInstance3D).multimesh
		if mm != null and mm.custom_aabb.size != Vector3.ZERO:
			return mm.custom_aabb
		var box := mesh.get_aabb()
		var merged := box
		if mm != null:
			for i in mm.instance_count:
				merged = merged.merge(mm.get_instance_transform(i) * box)
		return merged
	return mesh.get_aabb()


# --- Cascades ----------------------------------------------------------------

func _cascade_tris(entries: Array, pos: Vector3, look: Vector3, fov: float,
		max_dist: float, light_dir: Vector3, splits: Array[float]) -> Array:
	var fwd := (look - pos).normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var up := right.cross(fwd).normalized()
	var tan_v := tan(deg_to_rad(fov) * 0.5)
	var tan_h := tan_v * 1280.0 / 720.0

	# Light space: any orthonormal basis whose Z is the light axis.
	var lz := light_dir
	var lx := (Vector3.UP if absf(lz.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).cross(lz).normalized()
	var ly := lz.cross(lx).normalized()

	var bounds: Array[float] = [CAMERA_NEAR]
	for s in splits:
		bounds.append(max_dist * s)
	bounds.append(max_dist)

	var out: Array = []
	for c in bounds.size() - 1:
		var sphere := _slice_sphere(pos, fwd, right, up, tan_h, tan_v, bounds[c], bounds[c + 1])
		var centre: Vector3 = sphere[0]
		var radius: float = sphere[1]
		var c2 := Vector2(centre.dot(lx), centre.dot(ly))
		var tris := 0
		for e in entries:
			if not e["shadow"]:
				continue
			if _overlaps_disc(e["aabb"], lx, ly, c2, radius):
				tris += e["tris"]
		out.append(tris)
	return out


## Bounding sphere of the frustum slice between `near` and `far`.
func _slice_sphere(pos: Vector3, fwd: Vector3, right: Vector3, up: Vector3,
		tan_h: float, tan_v: float, near: float, far: float) -> Array:
	var corners: Array[Vector3] = []
	for d in [near, far]:
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				corners.append(pos + fwd * d + right * (sx * tan_h * d) + up * (sy * tan_v * d))
	var centre := Vector3.ZERO
	for c in corners:
		centre += c
	centre /= float(corners.size())
	var r := 0.0
	for c in corners:
		r = maxf(r, centre.distance_to(c))
	return [centre, r]


## Does this AABB, projected onto the plane perpendicular to the light, touch the
## cascade's disc? Unbounded along the light axis, which is what makes an occluder
## standing between the sun and the cascade count.
func _overlaps_disc(box: AABB, lx: Vector3, ly: Vector3, disc: Vector2, radius: float) -> bool:
	# Projected AABB of the box's 8 corners in the light's XY plane.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var p := box.position + Vector3(
			box.size.x if (i & 1) else 0.0,
			box.size.y if (i & 2) else 0.0,
			box.size.z if (i & 4) else 0.0)
		var q := Vector2(p.dot(lx), p.dot(ly))
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	var nearest := Vector2(clampf(disc.x, lo.x, hi.x), clampf(disc.y, lo.y, hi.y))
	return nearest.distance_squared_to(disc) <= radius * radius


func _find_sun(n: Node) -> DirectionalLight3D:
	var l := n as DirectionalLight3D
	if l != null and l.shadow_enabled:
		return l
	for c in n.get_children():
		var found := _find_sun(c)
		if found != null:
			return found
	return null
