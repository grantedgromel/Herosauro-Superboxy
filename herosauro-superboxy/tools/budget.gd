extends Node
## Measures the rendering budget for the assembled world.
##
## This container has no GPU, so a framerate here would be meaningless. What IS
## meaningful is hardware-independent: how much work the scene asks the GPU to
## do. Draw calls, primitives, texture and buffer memory and the shadow-caster
## count are the numbers that actually decide whether a mid-range card holds 60,
## so those are what we report — measured, not estimated.
##
## Two halves, answering two different questions:
##
##   1. THE CENSUS. Everything in the assembled world, whether or not anyone is
##      looking at it. This is the ceiling: the cost if culling achieved nothing.
##
##   2. THE SWEEP. The live per-frame counters with a camera standing at each
##      canonical world vantage from tools/shots.json. This is what a player
##      actually pays, and the gap between it and the census is exactly what
##      culling is buying.
##
## The sweep exists because this tool used to print "objects in frame", "draw
## calls in frame" and "primitives in frame" as 0 on every single run, and the
## reason was not a broken counter — it was that budget.tscn had no Camera3D.
## With nothing rendering 3D those numbers are honestly zero, and a zero that
## looks like a measurement is worse than no measurement, because the ceilings in
## tools/profile.gd are written against exactly these counters and this is the
## tool you would reach for to set them.
##
##   godot --path . tools/budget.tscn --rendering-driver vulkan

const WorldScene: PackedScene = preload("res://scenes/world/bridge_arena.tscn")

## The shot manifest is the single source of truth for camera vantages, shared
## with tools/baseline.gd and tools/harness.py. A budget measured at a vantage
## the review gate does not look at is a budget for a frame nobody sees.
const SHOTS_MANIFEST := "res://tools/shots.json"

## Frames pumped after the world is built, before anything is measured. The
## world assembles over several frames (bakes, MultiMesh fills, AABB updates).
const SETTLE_FRAMES := 30

## Frames pumped after each camera move. The counters describe the frame that
## was just drawn, and culling state takes a frame or two to follow the camera.
const CAMERA_FRAMES := 12


func _ready() -> void:
	var world: Node3D = WorldScene.instantiate()
	add_child(world)
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame

	_census(world)
	await _sweep(world)

	print("=== END BUDGET ===")
	get_tree().quit(0)


# --- The census --------------------------------------------------------------

func _census(root: Node3D) -> void:
	var meshes: Array[MeshInstance3D] = []
	var multis: Array[MultiMeshInstance3D] = []
	var lights: Array[Light3D] = []
	var bodies := 0
	var shadow_casters := 0
	_walk(root, meshes, multis, lights)
	for m in meshes:
		if m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadow_casters += 1
	for n in _all(root):
		if n is CollisionObject3D:
			bodies += 1

	var surfaces := 0
	var mesh_tris := 0
	for m in meshes:
		if m.mesh == null:
			continue
		surfaces += m.mesh.get_surface_count()
		mesh_tris += _tris_of(m.mesh)

	var mm_instances := 0
	var mm_tris := 0
	for mm in multis:
		if mm.multimesh == null:
			continue
		mm_instances += mm.multimesh.instance_count
		if mm.multimesh.mesh != null:
			mm_tris += _tris_of(mm.multimesh.mesh) * mm.multimesh.instance_count

	print("=== RENDER BUDGET (measured, %s) ===" % RenderingServer.get_current_rendering_method())
	print("  adapter                 : %s" % RenderingServer.get_video_adapter_name())
	print("--- census: the whole world, culled or not ---")
	print("  MeshInstance3D          : %d" % meshes.size())
	print("  ... surfaces (draw calls): %d" % surfaces)
	print("  ... of which cast shadow : %d" % shadow_casters)
	print("  MultiMeshInstance3D     : %d  (%d instances)" % [multis.size(), mm_instances])
	print("  Lights                  : %d" % lights.size())
	print("  Collision bodies        : %d" % bodies)
	print("  Triangles (mesh arrays) : %d" % mesh_tris)
	print("  Triangles (multimesh)   : %d" % mm_tris)
	print("  Triangles (total)       : %d" % (mesh_tris + mm_tris))
	# Memory is resident whether or not a camera exists, so unlike the in-frame
	# counters these were always honest.
	print("  texture memory (MiB)    : %.1f" % _mib(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED))
	print("  buffer memory  (MiB)    : %.1f" % _mib(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED))
	print("  video memory   (MiB)    : %.1f" % _mib(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED))


func _mib(info: int) -> float:
	return float(RenderingServer.get_rendering_info(info)) / 1048576.0


func _tris_of(mesh: Mesh) -> int:
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
	return tris


# --- The sweep ---------------------------------------------------------------

func _sweep(world: Node3D) -> void:
	var shots := _world_shots()
	if shots.is_empty():
		push_error("budget: no world-kind shots readable from " + SHOTS_MANIFEST)
		get_tree().quit(2)
		return

	var cam := Camera3D.new()
	cam.name = "BudgetCamera"
	world.add_child(cam)
	cam.current = true

	print("--- sweep: what a frame actually costs, per canonical vantage ---")
	print("  %-18s %10s %12s %14s" % ["shot", "objects", "draw calls", "primitives"])
	var worst_name := ""
	var worst_prims := -1
	var worst_draws := 0
	for s in shots:
		cam.fov = float(s["fov"])
		cam.global_position = s["pos"]
		cam.look_at(s["look"], Vector3.UP)
		for _i in CAMERA_FRAMES:
			await get_tree().process_frame
		var objects := int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		var prims := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		print("  %-18s %10d %12d %14d" % [s["name"], objects, draws, prims])
		if prims > worst_prims:
			worst_prims = prims
			worst_draws = draws
			worst_name = String(s["name"])

	cam.queue_free()
	print("  worst vantage           : %s  (%d primitives, %d draw calls)"
			% [worst_name, worst_prims, worst_draws])
	print("  NOTE: static world only — no heroes, no giant, no FX. A live frame")
	print("        costs more. tools/profile.gd measures that and gates on it.")


## The `world` shots from the manifest, in manifest order. `game` and `menu`
## shots are skipped: they need scenes/main.tscn and its own camera, which is
## what tools/profile.gd runs.
func _world_shots() -> Array:
	var fh := FileAccess.open(SHOTS_MANIFEST, FileAccess.READ)
	if fh == null:
		return []
	var parsed: Variant = JSON.parse_string(fh.get_as_text())
	fh.close()
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("shots"):
		return []
	var out: Array = []
	for raw in (parsed as Dictionary)["shots"]:
		var shot: Dictionary = raw
		if String(shot.get("kind", "")) != "world":
			continue
		out.append({
			"name": String(shot["name"]),
			"pos": _vec(shot["pos"]),
			"look": _vec(shot["look"]),
			"fov": float(shot["fov"]),
		})
	return out


func _vec(a: Variant) -> Vector3:
	var arr: Array = a
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


# --- Traversal ---------------------------------------------------------------

func _walk(n: Node, meshes: Array[MeshInstance3D], multis: Array[MultiMeshInstance3D],
		lights: Array[Light3D]) -> void:
	if n is MeshInstance3D:
		meshes.append(n)
	elif n is MultiMeshInstance3D:
		multis.append(n)
	elif n is Light3D:
		lights.append(n)
	for c in n.get_children():
		_walk(c, meshes, multis, lights)


func _all(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out
