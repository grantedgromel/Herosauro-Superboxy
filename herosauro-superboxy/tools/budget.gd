extends Node
## Measures the rendering budget for the assembled world.
##
## This container has no GPU, so a framerate here would be meaningless. What IS
## meaningful is hardware-independent: how much work the scene asks the GPU to
## do. Draw calls, primitives, texture and buffer memory and the shadow-caster
## count are the numbers that actually decide whether a mid-range card holds 60,
## so those are what we report — measured, not estimated.
##
##   godot --path . tools/budget.tscn --rendering-driver vulkan

const WorldScene: PackedScene = preload("res://scenes/world/bridge_arena.tscn")

var _settle: int = 0


func _ready() -> void:
	add_child(WorldScene.instantiate())
	_settle = 30


func _process(_d: float) -> void:
	if _settle > 0:
		_settle -= 1
		return
	set_process(false)
	_report()
	get_tree().quit()


func _report() -> void:
	var root := get_tree().current_scene if get_tree().current_scene else self
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
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			if arr.is_empty():
				continue
			var idx = arr[Mesh.ARRAY_INDEX]
			var vtx = arr[Mesh.ARRAY_VERTEX]
			if idx != null and idx.size() > 0:
				mesh_tris += idx.size() / 3
			elif vtx != null:
				mesh_tris += vtx.size() / 3

	var mm_instances := 0
	for mm in multis:
		if mm.multimesh:
			mm_instances += mm.multimesh.instance_count

	print("=== RENDER BUDGET (measured, %s) ===" % RenderingServer.get_current_rendering_method())
	print("  MeshInstance3D          : %d" % meshes.size())
	print("  ... surfaces (draw calls): %d" % surfaces)
	print("  ... of which cast shadow : %d" % shadow_casters)
	print("  MultiMeshInstance3D     : %d  (%d instances)" % [multis.size(), mm_instances])
	print("  Lights                  : %d" % lights.size())
	print("  Collision bodies        : %d" % bodies)
	print("  Triangles (mesh arrays) : %d" % mesh_tris)
	print("--- RenderingServer counters ---")
	print("  objects in frame        : %d" % RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
	print("  draw calls in frame     : %d" % RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	print("  primitives in frame     : %d" % RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	print("  texture memory (MiB)    : %.1f" % (float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)) / 1048576.0))
	print("  buffer memory  (MiB)    : %.1f" % (float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED)) / 1048576.0))
	print("  video memory   (MiB)    : %.1f" % (float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)) / 1048576.0))
	print("=== END BUDGET ===")


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
