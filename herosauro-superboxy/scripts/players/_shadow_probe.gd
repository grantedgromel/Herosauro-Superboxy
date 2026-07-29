extends SceneTree
## Why the hero throws no shadow.
##
## Captured frames show Adamastor and the parapets laying long shadows down the
## deck and the hero laying none. Nothing in the project turns shadows off on
## him, so the suspicion is the classic skinned-mesh one: shadow culling tests
## the mesh's own AABB, and an imported rigged glTF carries the AABB of its REST
## pose. Get far enough from the origin of that box, or pose outside it, and the
## renderer drops the mesh from the shadow pass while still drawing it in the
## colour pass — which looks exactly like "no shadow".
##
## Run:
##   godot --headless --script res://scripts/players/_shadow_probe.gd --path .

## Loaded at run time, not preloaded: preload compiles the hero's whole script
## graph while the probe itself is being parsed, which is before the autoloads
## exist, and every reference to GameManager or AudioManager fails to resolve.
func _initialize() -> void:
	var scene := load("res://scenes/players/herosauro.tscn") as PackedScene
	var hero := scene.instantiate()
	root.add_child(hero)
	await process_frame
	await process_frame

	print("[shadow] hero: ", hero.name, "  pos ", hero.global_position)
	var found := 0
	for mi in _meshes(hero):
		found += 1
		var aabb := mi.get_aabb()
		var skel := mi.skeleton != NodePath() and mi.get_node_or_null(mi.skeleton) != null
		print("  %-28s cast_shadow=%d  cull_margin=%.2f  skinned=%s"
				% [mi.name, mi.cast_shadow, mi.extra_cull_margin, skel])
		print("      aabb pos %s size %s" % [aabb.position, aabb.size])
		if mi.mesh != null:
			print("      mesh custom_aabb size %s" % [mi.mesh.get_custom_aabb().size])
	if found == 0:
		print("  !! no MeshInstance3D under the hero at all")
	quit()


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var mi := node as MeshInstance3D
	if mi != null:
		out.append(mi)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out
