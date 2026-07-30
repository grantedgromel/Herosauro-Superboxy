extends SceneTree
## TEMPORARY: render real world geometry so culling can be observed rather than
## reasoned about. Delete after the fix lands.

var _frames := 0


func _initialize() -> void:
	var root := get_root()

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.0, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0.0)
	root.add_child(sun)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 40, 46)
	cam.rotation = Vector3(-0.55, 0.0, 0.0)
	cam.current = true
	root.add_child(cam)

	root.add_child(TerrainBuilder.build())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 8:
		return false
	var img := get_root().get_texture().get_image()
	img.save_png("/tmp/claude-0/-home-user-Herosauro-Superboxy/fbbbd4f4-9001-5d1e-9852-168e00b42fee/scratchpad/terrain.png")
	return true
