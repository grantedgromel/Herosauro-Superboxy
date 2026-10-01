extends Node
## Per-frame cost of a chapter's world, from the gameplay camera. Not shipped.
##
##   LP_NUM_THREADS=1 xvfb-run -a -s "-screen 0 960x540x24" godot --path . \
##       --rendering-method gl_compatibility --resolution 960x540 --disable-vsync \
##       scripts/world/_perf/_bridge_perf.tscn -- --chapter=adamastor \
##       [--frames=120] [--ablate] [--out=/tmp/x.png] [--cam=x,y,z,lx,ly,lz]
##
## Boots main.tscn exactly as a child would reach the level (set_chapter, one
## human hero, start_game), lets it settle, then samples `--frames` frames from
## whatever camera gameplay made current. Reports, per frame and as medians:
##
##   wall   time between two process frames, measured here (this is a tool, not a
##          builder: rule 5 is about what reaches the screen, and nothing does)
##   cpu    RenderingServer's measured render CPU time for the root viewport
##   gpu    its measured GPU time (GL timer queries; on llvmpipe this is the
##          rasteriser's own cost, which is the closest thing this container has
##          to SwiftShader in a browser: both are CPU rasterisers)
##   dc / prim / obj   the RenderingServer frame counters
##
## --ablate then hides one world subtree at a time and re-samples, so the cost of
## each piece is MEASURED as the time it takes away, not guessed from triangles.
##
## Why this is believable: it prints the renderer it actually got, and quits 2 if
## no Camera3D is current (budget.gd shipped reporting zeros for exactly that).

const MainScene: PackedScene = preload("res://scenes/main.tscn")

var _chapter := "adamastor"
var _frames := 120
var _ablate := false
var _out := ""
var _cam := PackedFloat32Array()
var _abl_frames := 3
var _experiments := false
var _census := false
var _hide_list: Array[String] = ["BridgeArena", "SkyBackground", "Clouds", "River", "Terrain",
	"Ribeira", "PortoLandmarks", "Ironwork", "DeckDressing", "Lamps", "Rabelos", "RiverLife"]
var _skip_mats := false
var _far_test := false
var _levers := false
var _sky_variants := false
## Shot ids from tools/shots.json (prefix match, e.g. "06,07"): each is rendered
## from a fixed camera with the tree paused, timed, and saved next to --out.
var _views: Array[String] = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--chapter="):
			_chapter = a.substr(10)
		elif a.begins_with("--frames="):
			_frames = int(a.substr(9))
		elif a.begins_with("--abl-frames="):
			_abl_frames = int(a.substr(13))
		elif a == "--experiments":
			_experiments = true
		elif a.begins_with("--hide="):
			_hide_list.assign(a.substr(7).split(","))
		elif a.begins_with("--views="):
			_views.assign(a.substr(8).split(","))
		elif a == "--sky-variants":
			_sky_variants = true
		elif a == "--levers":
			_levers = true
		elif a == "--far-test":
			_far_test = true
		elif a == "--skip-mats":
			_skip_mats = true
		elif a == "--census":
			_census = true
		elif a == "--ablate":
			_ablate = true
		elif a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--cam="):
			for p in a.substr(6).split(","):
				_cam.append(float(p))
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	GameManager.assists = true
	GameManager.companion = true
	var main := MainScene.instantiate()
	add_child(main)
	await _wait(4)
	GameManager.set_chapter(_chapter)
	GameManager.set_player_count(1)
	GameManager.set_human_hero(1)
	GameManager.start_game()
	await _wait(40)
	if _cam.size() == 6:
		var c := Camera3D.new()
		c.fov = 62.0
		add_child(c)
		c.global_position = Vector3(_cam[0], _cam[1], _cam[2])
		c.look_at(Vector3(_cam[3], _cam[4], _cam[5]))
		c.make_current()
		await _wait(6)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		print("[perf] !! no current Camera3D — refusing to report")
		get_tree().quit(2)
		return
	print("[perf] renderer=%s adapter=%s chapter=%s cam=%s -> %s" % [
		RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(),
		_chapter, str(cam.global_position.snapped(Vector3.ONE * 0.1)),
		str((cam.global_position - cam.global_transform.basis.z * 10.0).snapped(Vector3.ONE * 0.1))])
	var base := await _sample(_frames)
	_print_row("TOTAL", base)
	if _out != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_out)
		print("[perf] saved %s" % _out)
	if _ablate:
		await _run_ablation(base)
	if not _views.is_empty():
		await _run_views()
	if _experiments:
		await _run_experiments()
	if _levers:
		await _run_levers()
	if _census:
		_print_census()
	print("[perf] === END ===")
	get_tree().quit(0)


func _sample(n: int) -> Dictionary:
	var vp := get_viewport().get_viewport_rid()
	var walls: Array[float] = []
	var cpus: Array[float] = []
	var gpus: Array[float] = []
	var dcs: Array[float] = []
	var prims: Array[float] = []
	var objs: Array[float] = []
	await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	for i in n:
		await get_tree().process_frame
		var t1 := Time.get_ticks_usec()
		walls.append((t1 - t0) / 1000.0)
		t0 = t1
		cpus.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
		gpus.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		dcs.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		prims.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		objs.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
	return {"wall": _median(walls), "cpu": _median(cpus), "gpu": _median(gpus),
		"dc": _median(dcs), "prim": _median(prims), "obj": _median(objs)}


func _print_row(label: String, s: Dictionary, base: Dictionary = {}) -> void:
	var line := "[perf] %-34s wall %8.1f ms  cpu %7.1f  gpu %8.1f  dc %5d  prim %8d  obj %5d" % [
		label, s.wall, s.cpu, s.gpu, int(s.dc), int(s.prim), int(s.obj)]
	if not base.is_empty():
		line += "   | saves wall %7.1f  gpu %7.1f  dc %4d  prim %7d" % [
			base.wall - s.wall, base.gpu - s.gpu, int(base.dc - s.dc), int(base.prim - s.prim)]
	print(line)


## Every Node3D directly under the arena and under the sky background, hidden in
## turn, plus the sun's shadows and the omni/spot lights as a set.
func _run_ablation(base: Dictionary) -> void:
	var n := _abl_frames
	# Fragment- or vertex-bound? Half the pixels in each axis.
	get_viewport().scaling_3d_scale = 0.5
	await _wait(2)
	_print_row("(3d at half resolution)", await _sample(n), base)
	get_viewport().scaling_3d_scale = 1.0
	var env_node: WorldEnvironment = null
	for node in _all(get_tree().root):
		if node is WorldEnvironment:
			env_node = node
	if env_node != null:
		var env := env_node.environment
		env_node.environment = null
		await _wait(2)
		_print_row("(WorldEnvironment off)", await _sample(n), base)
		env_node.environment = env
	var targets: Array[Node3D] = []
	for root in _world_roots():
		for c in root.get_children():
			if c is Node3D and (c as Node3D).visible:
				targets.append(c)
			# One level deeper for the big containers, so "the city" splits.
			if c is Node3D and c.get_child_count() > 1 and c.get_child_count() < 40:
				for g in c.get_children():
					if g is Node3D and (g as Node3D).visible:
						targets.append(g)
	for t in targets:
		t.visible = false
		await _wait(2)
		var s := await _sample(n)
		t.visible = true
		_print_row(str(t.get_path()).replace("/root/BridgePerf/", "").right(34), s, base)
	var suns: Array[DirectionalLight3D] = []
	var lamps: Array[Light3D] = []
	for node in _all(get_tree().root):
		if node is DirectionalLight3D and (node as Light3D).shadow_enabled and (node as Light3D).visible:
			suns.append(node)
		elif (node is OmniLight3D or node is SpotLight3D) and (node as Light3D).visible:
			lamps.append(node)
	for s in suns:
		s.shadow_enabled = false
	await _wait(2)
	_print_row("(sun shadows off x%d)" % suns.size(), await _sample(n), base)
	for s in suns:
		s.shadow_enabled = true
	for l in lamps:
		l.visible = false
	await _wait(2)
	_print_row("(omni/spot lights off x%d)" % lamps.size(), await _sample(n), base)
	for l in lamps:
		l.visible = true


func _world_roots() -> Array[Node]:
	var out: Array[Node] = []
	for node in _all(get_tree().root):
		var nm := String(node.name)
		if nm == "BridgeArena" or nm == "SkyBackground" or node is LevelBase:
			out.append(node)
	return out


func _all(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out


func _median(a: Array[float]) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return b[b.size() / 2]


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# --- Experiments --------------------------------------------------------------
## Feature switches rather than subtrees, with the tree PAUSED so the giant and the
## heroes hold still and every sample sees the same frame. Each switch is applied,
## sampled and reverted; the baseline is re-sampled at the end to show drift.

func _run_experiments() -> void:
	get_tree().paused = true
	var n := _abl_frames
	await _wait(2)
	var base := await _sample(n)
	_print_row("X baseline (paused)", base)
	var env: Environment = null
	for node in _all(get_tree().root):
		if node is WorldEnvironment:
			env = (node as WorldEnvironment).environment
	var sun: DirectionalLight3D = null
	for node in _all(get_tree().root):
		if node is DirectionalLight3D and (node as Light3D).shadow_enabled:
			sun = node
	var props := ["glow_enabled", "ssao_enabled", "fog_enabled", "adjustment_enabled"]
	for prop in props:
		if env != null and env.get(prop):
			env.set(prop, false)
			await _wait(1)
			_print_row("X env %s off" % prop, await _sample(n), base)
			env.set(prop, true)
	get_viewport().scaling_3d_scale = 0.5
	await _wait(1)
	_print_row("X 3d at half resolution", await _sample(n), base)
	get_viewport().scaling_3d_scale = 1.0
	for grp in ["boss", "players"]:
		var hidden: Array[Node3D] = []
		for g in get_tree().get_nodes_in_group(grp):
			if g is Node3D and g.visible:
				g.visible = false
				hidden.append(g)
		await _wait(1)
		_print_row("X hide group %s (%d)" % [grp, hidden.size()], await _sample(n), base)
		for g in hidden:
			g.visible = true
	for path in _hide_list:
		var node := _find(path)
		if node == null:
			print("[perf] X %s not found" % path)
			continue
		node.visible = false
		await _wait(1)
		_print_row("X hide %s" % path, await _sample(n), base)
		node.visible = true
	if sun != null:
		sun.shadow_enabled = false
		await _wait(1)
		_print_row("X sun shadow off", await _sample(n), base)
		sun.shadow_enabled = true
		var mode := sun.directional_shadow_mode
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		await _wait(1)
		_print_row("X sun orthogonal", await _sample(n), base)
		sun.directional_shadow_mode = mode
	if _sky_variants:
		var sky := _find("SkyBackground")
		for variant in ["far", "far+no_recv_shadow", "far+no_specular", "far+no_rim", "far+no_ambient", "unshaded"]:
			var orig := {}
			for node in _all(sky):
				var gi := node as GeometryInstance3D
				if gi == null or not (gi.material_override is BaseMaterial3D):
					continue
				orig[gi] = gi.material_override
				var m: BaseMaterial3D = (load("res://scripts/world/world_tier.gd") as Script).call(
						"far_material", gi.material_override).duplicate()
				match variant:
					"far+no_recv_shadow":
						m.disable_receive_shadows = true
					"far+no_specular":
						m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
						m.metallic_specular = 0.0
					"far+no_rim":
						m.rim_enabled = false
					"far+no_ambient":
						m.disable_ambient_light = true
					"unshaded":
						m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				gi.material_override = m
			await _wait(1)
			_print_row("S sky %s (%d)" % [variant, orig.size()], await _sample(n), base)
			for gi in orig:
				gi.material_override = orig[gi]
	if _far_test:
		var all_far := _swap_far_except([])
		await _wait(1)
		_print_row("X far_material on everything (%d)" % all_far.size(), await _sample(n), base)
		for mi in all_far:
			mi.material_override = all_far[mi]
		var flat := StandardMaterial3D.new()
		flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flat.albedo_color = Color(0.6, 0.6, 0.6)
		var unshaded := {}
		for node in _all(_find("BridgeArena")):
			var gi := node as GeometryInstance3D
			if gi != null and gi.material_override is BaseMaterial3D:
				unshaded[gi] = gi.material_override
				gi.material_override = flat
		await _wait(1)
		_print_row("X arena unshaded grey (%d)" % unshaded.size(), await _sample(n), base)
		for gi in unshaded:
			gi.material_override = unshaded[gi]
		var swapped := _swap_far_except(["Roadway", "Footways", "Tramway", "Bridge", "DeckDressing",
			"Lamps", "ParapetIron", "Fascia", "Abutments"])
		await _wait(1)
		_print_row("X far_material except deck (%d)" % swapped.size(), await _sample(n), base)
		for mi in swapped:
			mi.material_override = swapped[mi]
	if _skip_mats:
		_print_row("X baseline again", await _sample(n), base)
		get_tree().paused = false
		return
	for q in [0, 1]:
		RenderingServer.directional_soft_shadow_filter_set_quality(q)
		await _wait(1)
		_print_row("X soft shadow quality %d" % q, await _sample(n), base)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"))
	# Material variants over every StandardMaterial3D in the arena.
	for variant in ["no_detail_aniso", "no_maps", "per_vertex"]:
		var swapped := _swap_materials(variant)
		await _wait(1)
		_print_row("X mats %s (%d)" % [variant, swapped.size()], await _sample(n), base)
		for mi in swapped:
			mi.material_override = swapped[mi]
	var river := _find("River") as MeshInstance3D
	if river != null:
		var old := river.material_override
		var old_s := river.get_surface_override_material(0)
		var flat := StandardMaterial3D.new()
		flat.albedo_color = Color(0.1, 0.2, 0.22)
		flat.roughness = 0.2
		river.material_override = flat
		await _wait(1)
		_print_row("X river StandardMaterial", await _sample(n), base)
		river.material_override = old
		river.set_surface_override_material(0, old_s)
	_print_row("X baseline again", await _sample(n), base)
	get_tree().paused = false


var _mat_cache := {}

func _swap_materials(variant: String) -> Dictionary:
	var out := {}
	var arena := _find("BridgeArena")
	for node in _all(arena):
		var mi := node as MeshInstance3D
		if mi == null or not (mi.material_override is StandardMaterial3D):
			continue
		var src := mi.material_override as StandardMaterial3D
		var key := [src, variant]
		var m: StandardMaterial3D = _mat_cache.get(key)
		if m == null:
			m = src.duplicate()
			m.detail_enabled = false
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			if variant != "no_detail_aniso":
				m.normal_enabled = false
				m.albedo_texture = null
				m.roughness_texture = null
				m.metallic_texture = null
				m.ao_enabled = false
				m.rim_enabled = false
			if variant == "per_vertex":
				m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
			_mat_cache[key] = m
		out[mi] = src
		mi.material_override = m
	return out


func _find(nm: String) -> Node:
	if nm.contains("/"):
		var head := _find(nm.get_slice("/", 0))
		return head.get_node_or_null(nm.substr(nm.find("/") + 1)) if head != null else null
	for node in _all(get_tree().root):
		if String(node.name) == nm:
			return node
	return null


# --- Census -------------------------------------------------------------------
## Triangles per named subtree of the arena, as built on THIS tier, and how many of
## them cast shadows.

func _print_census() -> void:
	var arena := _find("BridgeArena")
	if arena == null:
		return
	for root in [arena, _find("SkyBackground")]:
		for c in root.get_children():
			var tris := 0
			var cast := 0
			var surfaces := 0
			for node in _all(c):
				var mi := node as MeshInstance3D
				if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
					continue
				for si in mi.mesh.get_surface_count():
					var t := _surface_tris(mi.mesh, si)
					tris += t
					surfaces += 1
					if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
						cast += t
			print("[perf] census %-28s tris %8d  casting %8d  surfaces %4d" % [c.name, tris, cast, surfaces])


func _surface_tris(mesh: Mesh, si: int) -> int:
	var arr := mesh.surface_get_arrays(si)
	var idx = arr[Mesh.ARRAY_INDEX]
	if idx != null and idx.size() > 0:
		return idx.size() / 3
	return (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3


# --- Fixed vantages -----------------------------------------------------------

func _run_views() -> void:
	var f := FileAccess.open("res://tools/shots.json", FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	var shots: Array = data["shots"] if data is Dictionary else data
	get_tree().paused = true
	var prev := get_viewport().get_camera_3d()
	var cam := Camera3D.new()
	add_child(cam)
	for v in _views:
		for s in shots:
			if not String(s.get("name", "")).begins_with(v):
				continue
			var pos: Array = s["pos"]
			var look: Array = s["look"]
			cam.fov = float(s.get("fov", 55))
			cam.global_position = Vector3(pos[0], pos[1], pos[2])
			cam.look_at(Vector3(look[0], look[1], look[2]))
			cam.make_current()
			await _wait(3)
			_print_row("V %s" % s["name"], await _sample(_abl_frames))
			if _out != "":
				await RenderingServer.frame_post_draw
				var path := _out.replace(".png", "_%s.png" % s["name"])
				get_viewport().get_texture().get_image().save_png(path)
				print("[perf] saved %s" % path)
	if prev != null:
		prev.make_current()
	cam.queue_free()
	get_tree().paused = false
	await _wait(2)


## Every arena MeshInstance3D outside the named subtrees, drawn with
## WorldTier.far_material. The question it answers: what would the rest of the
## near field save if it were lit like the backdrop.
func _swap_far_except(keep: Array) -> Dictionary:
	var out := {}
	var arena := _find("BridgeArena")
	for node in _all(arena):
		var mi := node as MeshInstance3D
		if mi == null or not (mi.material_override is BaseMaterial3D):
			continue
		var skip := false
		var p: Node = mi
		while p != null and p != arena:
			if String(p.name) in keep or (String(p.name) == "Ironwork" and p.get_parent() == arena):
				# The Ironwork NODE holds ParapetIron; only its arch meshes are fair game.
				if String(p.name) != "Ironwork" or String(mi.name) == "ParapetIron":
					skip = true
					break
			p = p.get_parent()
		if skip:
			continue
		out[mi] = mi.material_override
		# Called dynamically so this tool still parses against a WorldTier that
		# predates far_material (the before/after renders check out the old one).
		mi.material_override = (load("res://scripts/world/world_tier.gd") as Script).call(
				"far_material", mi.material_override)
	return out


# --- Renderer-wide levers -----------------------------------------------------
## Settings this directory does not own (project.godot, the lighting rig), measured
## here so whoever does own them has numbers rather than a suggestion. Each is
## applied, sampled and reverted; "combined" stacks the three that are tier-local.

func _run_levers() -> void:
	get_tree().paused = true
	var n := _abl_frames
	var vp := get_viewport()
	var env: Environment = null
	for node in _all(get_tree().root):
		if node is WorldEnvironment:
			env = (node as WorldEnvironment).environment
	var q0: int = ProjectSettings.get_setting(
		"rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality")
	await _wait(1)
	var base := await _sample(n)
	_print_row("L baseline (paused)", base)
	for sc in [0.75, 0.67]:
		vp.scaling_3d_scale = sc
		await _wait(1)
		_print_row("L scaling_3d_scale %.2f" % sc, await _sample(n), base)
	vp.scaling_3d_scale = 1.0
	for q in [1, 0]:
		RenderingServer.directional_soft_shadow_filter_set_quality(q)
		await _wait(1)
		_print_row("L soft shadow quality %d (from %d)" % [q, q0], await _sample(n), base)
	RenderingServer.directional_soft_shadow_filter_set_quality(q0)
	var had_ssao := env != null and env.ssao_enabled
	var had_glow := env != null and env.glow_enabled
	if env != null:
		env.ssao_enabled = false
		env.glow_enabled = false
		await _wait(1)
		_print_row("L ssao + glow off", await _sample(n), base)
	vp.scaling_3d_scale = 0.75
	RenderingServer.directional_soft_shadow_filter_set_quality(1)
	await _wait(1)
	_print_row("L combined: 0.75 + q1 + no ssao/glow", await _sample(n), base)
	vp.scaling_3d_scale = 1.0
	RenderingServer.directional_soft_shadow_filter_set_quality(q0)
	if env != null:
		env.ssao_enabled = had_ssao
		env.glow_enabled = had_glow
	_print_row("L baseline again", await _sample(n), base)
	get_tree().paused = false
