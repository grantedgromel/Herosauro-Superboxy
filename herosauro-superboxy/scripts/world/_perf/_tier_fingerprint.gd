extends Node
## A fingerprint of everything the arena hands the renderer. Not shipped.
##
##   godot --headless --path . scripts/world/_perf/_tier_fingerprint.tscn
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##       scripts/world/_perf/_tier_fingerprint.tscn
##
## Builds bridge_arena.tscn exactly as main.tscn does, waits for every deferred
## build step, then hashes, per GeometryInstance3D in tree order: its path, its
## visibility, its shadow-casting setting, its transform, every vertex and index of
## its mesh, and every property of every material it draws with; plus the sun's
## shadow settings and the environment. Prints one line per subtree and a total.
##
## What it is for: proving a change is pixel-neutral on a tier without rendering
## that tier. Two builds whose fingerprints match hand the renderer the same
## geometry, the same materials and the same lights, so they draw the same frame
## — except through a SHADER SOURCE change, which this cannot see and which has to
## be argued from the shader itself.
##
## Headless reports forward_plus, so the first command above is the desktop tier.

const ArenaScene: PackedScene = preload("res://scenes/world/bridge_arena.tscn")


func _ready() -> void:
	var arena := ArenaScene.instantiate()
	add_child(arena)
	for i in 8:
		await get_tree().process_frame
	print("[fingerprint] renderer=%s" % RenderingServer.get_current_rendering_method())
	var total := PackedStringArray()
	var groups := {}
	for node in _all(arena):
		var line := _describe(node)
		if line == "":
			continue
		total.append(line)
		var top := String(arena.get_path_to(node)).get_slice("/", 0)
		if top == "SkyBackground":
			top = "SkyBackground/" + String(arena.get_path_to(node)).get_slice("/", 1)
		var g: PackedStringArray = groups.get(top, PackedStringArray())
		g.append(line)
		groups[top] = g     # PackedStringArray is a value type; write it back
	for k in groups:
		var g: PackedStringArray = groups[k]
		print("[fingerprint] %-34s items %5d  %s" % [k, g.size(), "".join(g).md5_text()])
	print("[fingerprint] TOTAL items %d  %s" % [total.size(), "".join(total).md5_text()])
	get_tree().quit(0)


func _describe(node: Node) -> String:
	var parts := PackedStringArray()
	if node is DirectionalLight3D:
		var l := node as DirectionalLight3D
		parts.append("sun %s %d %.3f %d %.3f" % [str(node.get_path()), int(l.shadow_enabled),
			l.directional_shadow_max_distance, l.directional_shadow_mode, l.light_energy])
	elif node is WorldEnvironment:
		parts.append("env " + _props((node as WorldEnvironment).environment))
	elif node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		parts.append("%s v%d s%d t%s" % [str(node.get_path()), int(gi.is_visible_in_tree()),
			gi.cast_shadow, var_to_str(gi.global_transform)])
		if gi.material_override != null:
			parts.append(_props(gi.material_override))
		var mi := node as MeshInstance3D
		if mi != null and mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(s)
				parts.append(var_to_str(arr[Mesh.ARRAY_VERTEX]).md5_text())
				if arr[Mesh.ARRAY_INDEX] != null:
					parts.append(var_to_str(arr[Mesh.ARRAY_INDEX]).md5_text())
				var m := mi.get_active_material(s)
				if m != null:
					parts.append(_props(m))
	else:
		return ""
	return "|".join(parts) + "\n"


## Every stored property of a resource, sub-resources by their own properties.
func _props(r: Resource) -> String:
	if r == null:
		return "null"
	var out := PackedStringArray([r.get_class()])
	for p in r.get_property_list():
		if not (p.usage & PROPERTY_USAGE_STORAGE):
			continue
		var v = r.get(p.name)
		if v is Shader:
			out.append("%s=%s" % [p.name, (v as Shader).code.md5_text()])
		elif v is Texture2D:
			out.append("%s=%s" % [p.name, (v as Texture2D).resource_path if (v as Texture2D).resource_path != "" else str((v as Texture2D).get_size())])
		elif v is Resource:
			out.append("%s=<%s>" % [p.name, (v as Resource).get_class()])
		else:
			out.append("%s=%s" % [p.name, var_to_str(v)])
	if r is ShaderMaterial:
		var sm := r as ShaderMaterial
		if sm.shader != null:
			for u in sm.shader.get_shader_uniform_list():
				out.append("%s=%s" % [u.name, var_to_str(sm.get_shader_parameter(u.name))])
	return ",".join(out)


func _all(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out
