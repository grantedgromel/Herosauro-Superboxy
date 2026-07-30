extends SceneTree
## TEMPORARY: render each world builder in isolation so the winding fix can be
## judged by eye per subsystem. Delete after the fix lands.
##
##   xvfb-run -a godot --path . --rendering-driver vulkan --resolution 800x600 \
##       --script scripts/world/landmarks/_render_tmp.gd -- --tag=pre

const OUT := "/tmp/claude-0/-home-user-Herosauro-Superboxy/fbbbd4f4-9001-5d1e-9852-168e00b42fee/scratchpad/"

var _frames := 0
var _stage := 0
var _tag := "x"
var _slots: Array = []
var _cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			_tag = a.substr(6)

	var root := get_root()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.35, 0.0, 0.45)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.7, 0.9)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.9, 0.0)
	sun.light_energy = 2.0
	root.add_child(sun)

	_cam = Camera3D.new()
	_cam.current = true
	root.add_child(_cam)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20250727
	var fbatch := FacadeBuilder.Batch.new()
	var x := -12.0
	for i in 5:
		var spec := FacadeBuilder.random_spec(rng, 11.0, 16.0)
		spec.detail = FacadeBuilder.Detail.FULL
		spec.position = Vector3(x + spec.width * 0.5, 0.0, 0.0)
		x += spec.width + 0.06
		FacadeBuilder.add_to_batch(fbatch, spec, rng)

	_slots = [
		["terrain", TerrainBuilder.build(), Vector3(0, 40, 52), Vector3(-0.5, 0, 0)],
		["facades", fbatch.commit("Row"), Vector3(0, 8, 22), Vector3(-0.15, 0, 0)],
		["skyline", LandmarksBuilder.porto_skyline(), Vector3(-20, 30, 60), Vector3(-0.25, -0.25, 0)],
		["ironwork", _ironwork(), Vector3(0, 14, 68), Vector3(-0.1, 0, 0)],
	]
	_show(0)


func _ironwork() -> Node3D:
	var holder := Node3D.new()
	get_root().add_child(holder)
	BridgeIronwork.attach(holder)
	get_root().remove_child(holder)
	return holder


func _show(i: int) -> void:
	for s in _slots.size():
		var n: Node3D = _slots[s][1]
		if s == i:
			if n.get_parent() == null:
				get_root().add_child(n)
		elif n.get_parent() != null:
			get_root().remove_child(n)
	_cam.position = _slots[i][2]
	_cam.rotation = _slots[i][3]


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false
	_frames = 0
	var img := get_root().get_texture().get_image()
	img.save_png("%s%s_%s.png" % [OUT, _slots[_stage][0], _tag])
	_stage += 1
	if _stage >= _slots.size():
		return true
	_show(_stage)
	return false
