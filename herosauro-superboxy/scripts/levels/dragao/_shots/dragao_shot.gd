extends Node
## Screenshot helper for the stadium chapter. Not shipped, not a probe.
##
##   xvfb-run -a -s "-screen 0 960x540x24" godot --path . --rendering-method \
##       gl_compatibility scripts/levels/dragao/_shots/dragao_shot.tscn -- \
##       --out=/tmp/dragao.png [--frames=90] [--stage=1|2|3] [--cam=x,y,z,lx,ly,lz]
##
## --stage=2 snaps the stakes first (through their own take_hit) and waits for
## the cups; --stage=3 also brings every cup home and waits for the fire.
## Prints the frame's real draw-call count from the RenderingServer.

const MainScene: PackedScene = preload("res://scenes/main.tscn")

var _out := "/tmp/dragao.png"
var _frames := 90
var _stage := 1
var _cams: Array[PackedFloat32Array] = []
var _named: Array[String] = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--frames="):
			_frames = int(a.substr(9))
		elif a.begins_with("--stage="):
			_stage = int(a.substr(8))
		elif a.begins_with("--cams="):
			for c in a.substr(7).split(";"):
				if c.is_valid_float() or c.contains(","):
					var v := PackedFloat32Array()
					for p in c.split(","):
						v.append(float(p))
					_cams.append(v)
				else:
					_named.append(c)
	GameManager.assists = true
	GameManager.companion = true
	var main := MainScene.instantiate()
	add_child(main)
	await _wait(4)
	GameManager.set_chapter("dragao")
	GameManager.set_player_count(1)
	GameManager.set_human_hero(1)
	GameManager.start_game()
	await _wait(10)
	var level := LevelBase.current(get_tree())
	if _stage >= 2 and level != null:
		for s in level.stakes:
			for k in 3:
				s.take_hit(10.0, Vector3.RIGHT)
		await _wait(int(6.5 * 90))
	if _stage >= 3 and level != null:
		for c in level.cups:
			var g = level.carrier_of(c)
			if g != null:
				g.take_hit(10.0, Vector3.RIGHT)
		await _wait(150)
		for c in level.cups:
			if c.is_loose():
				c.collect(level.cabinet.slot_global(c.slot))
				GameManager.advance_objective(1)
		await _wait(200)
	await _wait(_frames)
	print("[dragao shot] frames done, objective %d/%d" % [GameManager.objective_done(), GameManager.objective_total()])
	if DisplayServer.get_name() == "headless":
		get_tree().quit()
		return
	await _save(_out)
	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	for i in _cams.size():
		var c := _cams[i]
		cam.global_position = Vector3(c[0], c[1], c[2])
		cam.look_at(Vector3(c[3], c[4], c[5]))
		cam.make_current()
		await _wait(3)
		await _save(_out.replace(".png", "_c%d.png" % i))
	# Named close-ups: a camera placed in front of a live object.
	for n in _named:
		var target: Node3D = null
		var dist := 3.0
		var h := 1.2
		if n == "goblin":
			for g in level.goblins:
				if g.is_active() and g.state == g.S.DANCE:
					target = g
					break
			dist = 2.4
			h = 0.75
		elif n == "dragon":
			target = level.dragon
			dist = 8.0
			h = 1.8
		elif n == "cabinet":
			target = level.cabinet
			dist = 6.0
			h = 1.6
		elif n == "van":
			target = level.van
			dist = 9.0
			h = 1.5
		if target == null:
			continue
		var fwd := target.global_transform.basis.z
		if n == "goblin":
			fwd = Vector3(sin(target.get("_yaw")), 0, cos(target.get("_yaw")))
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.BACK
		var at := target.global_position + Vector3.UP * h
		cam.global_position = at + fwd * dist + Vector3.UP * dist * 0.25
		cam.look_at(at)
		cam.make_current()
		await _wait(2)
		await _save(_out.replace(".png", "_%s.png" % n))
	get_tree().quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	var vp := get_viewport()
	print("[dragao shot] %s draw_calls=%d (visible %d, shadow %d, canvas %d) objects=%d primitives=%d" % [path,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		vp.get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
