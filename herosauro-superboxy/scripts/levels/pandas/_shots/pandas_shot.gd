extends Node
## Screenshot helper for chapter "pandas". Not shipped, not a probe.
##
##   xvfb-run -a -s "-screen 0 960x540x24" godot --path . --rendering-method gl_compatibility \
##       scripts/levels/pandas/_shots/pandas_shot.tscn -- --out=/tmp/p.png \
##       [--frames=90] [--fixed=N] [--cases] [--finale=SECONDS] [--cam=px,py,pz,tx,ty,tz] [--hero=x,z]
##
## --fixed=N repairs the first N houses on the spot (shots only: it calls the
## house's own transformation, which a probe must never do), --cases jumps to
## stage 2, --finale runs the finale for that many seconds before the shot.

const MainScene := preload("res://scenes/main.tscn")

var _out := "/tmp/pandas_shot.png"
var _frames := 90
var _fixed := 0
var _cases := false
var _finale := -1.0
var _cam := PackedFloat32Array()
var _hero := Vector2.INF
var _nohud := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--frames="):
			_frames = int(a.substr(9))
		elif a.begins_with("--fixed="):
			_fixed = int(a.substr(8))
		elif a == "--cases":
			_cases = true
		elif a.begins_with("--finale="):
			_finale = float(a.substr(9))
		elif a.begins_with("--cam="):
			for v in a.substr(6).split(","):
				_cam.append(float(v))
		elif a == "--nohud":
			_nohud = true
		elif a.begins_with("--hero="):
			var p := a.substr(7).split(",")
			_hero = Vector2(float(p[0]), float(p[1]))
	UIProgress.use_memory_only()
	GameManager.assists = true
	GameManager.companion = true
	GameManager.narration = false
	GameManager.set_player_count(1)
	GameManager.set_human_hero(1)
	GameManager.chapter_id = "pandas"
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	GameManager.start_game()
	await get_tree().process_frame
	await get_tree().process_frame
	var level := LevelBase.current(get_tree())
	if level == null:
		printerr("[pandas shot] no level")
		get_tree().quit(1)
		return
	print("[pandas shot] build %.0f ms" % float(level.get("build_ms")))
	var houses: Array = level.get("houses")
	for i in mini(_fixed, houses.size()):
		var h: Node3D = houses[i]
		h.pile.take_hit(100.0, Vector3.BACK)
		h.star.take_hit(100.0, Vector3.BACK)
		h.star.set("_since_hit", 10.0)
		h.star.take_hit(100.0, Vector3.BACK)
	if _hero.is_finite():
		level.place_heroes_near(Vector3(_hero.x, 0.0, _hero.y), 0.0)
	if _cases or _finale >= 0.0:
		for h in houses:
			if not h.is_repaired():
				h.pile.take_hit(100.0, Vector3.BACK)
				h.star.take_hit(100.0, Vector3.BACK)
				h.star.set("_since_hit", 10.0)
				h.star.take_hit(100.0, Vector3.BACK)
		for i in 200:
			await get_tree().physics_frame
	if _finale >= 0.0:
		for s in level.get("suitcases"):
			s.call("_on_body_entered", level.get("_human"))
			for i in 30:
				await get_tree().physics_frame
		for i in int(_finale * 60.0):
			await get_tree().physics_frame
	if _cam.size() == 6:
		var cam := Camera3D.new()
		cam.fov = 62.0
		add_child(cam)
		cam.global_position = Vector3(_cam[0], _cam[1], _cam[2])
		cam.look_at(Vector3(_cam[3], _cam[4], _cam[5]), Vector3.UP)
		cam.current = true
	if _nohud and main.get_node_or_null("UI") != null:
		(main.get_node("UI") as CanvasLayer).visible = false
	for i in _frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out)
	var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var obj := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var prim := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	print("[pandas shot] saved %s  draw calls %d  objects %d  primitives %d  stage %s  done %d/%d" % [
		_out, dc, obj, prim, level.stage_name(), GameManager.objective_done(), GameManager.objective_total()])
	print("[pandas shot] census %s" % str(level.render_census()))
	get_tree().quit()
