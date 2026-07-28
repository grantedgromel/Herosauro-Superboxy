extends Node
## Does the hero cast a shadow, or is his shadow simply landing on the near-black
## tramway strip where nothing could read it?
##
## Captured frames show him with no shadow at all. But the sun sits at 11.5
## degrees and runs almost along the bridge's own axis, so his shadow is a long,
## foreshortened streak on whatever is directly beside him — which is the
## darkest material on the deck. Staring at the frame cannot separate "casts
## nothing" from "casts onto black".
##
## So: render the same fixed frame twice from one process, once with the hero
## visible and once with him hidden, and subtract. Everything that differs is
## him: his body, and his shadow if he has one. If the difference is his
## silhouette and nothing else, he is not casting.
##
##   godot --path . tools/shadowshot.tscn --rendering-driver vulkan -- --out=/abs/dir

const ArenaScene: PackedScene = preload("res://scenes/world/bridge_arena.tscn")
const HeroScene: PackedScene = preload("res://scenes/players/herosauro.tscn")

## Where the hero is dropped. High enough to be above the deck whatever its
## datum is; gravity puts him on it and the camera is then placed off his
## SETTLED position rather than off a guessed one. The first attempt hardcoded
## both and put the camera out over the water, looking along the parapet.
const HERO_DROP := Vector3(0.0, 6.0, 0.0)

## Camera offset from the settled hero: high and behind, looking down. From
## above, an 8 m shadow at an 11.5 degree sun lies flat across the deck in full
## view — the gameplay camera is nearly along the sun's own axis, which is the
## one angle that foreshortens that shadow into nothing.
const CAM_OFFSET := Vector3(1.0, 9.0, 7.0)

const SETTLE := 26   ## frames for the arena build + the renderer's temporal passes
const GAP := 8       ## frames between the two exposures

var _out: String = "/tmp/shadowshot"
var _hero: Node3D
var _cam: Camera3D
var _frame: int = 0
var _stage: int = 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)

	add_child(ArenaScene.instantiate())

	_hero = HeroScene.instantiate()
	add_child(_hero)
	_hero.global_position = HERO_DROP

	# Our own camera, marked current after the arena's so it wins. Aimed in
	# _aim(), once the hero has actually landed.
	_cam = Camera3D.new()
	_cam.name = "ProbeCamera"
	add_child(_cam)
	_cam.fov = 50.0
	_cam.current = true

	print("shadowshot: adapter=", RenderingServer.get_video_adapter_name())


## Frame the hero where he ended up, not where he was dropped.
func _aim() -> void:
	var at := _hero.global_position
	_cam.global_position = at + CAM_OFFSET
	_cam.look_at(at, Vector3.UP)
	_cam.current = true
	print("shadowshot: hero settled at ", at, "  camera ", _cam.global_position)


func _process(_d: float) -> void:
	_frame += 1
	# Re-aim every frame until the exposure: the hero is still falling, and the
	# arena's own camera may become current partway through its build.
	if _stage == 0:
		_aim()
	match _stage:
		0:
			if _frame >= SETTLE:
				_save("a_hero_visible")
				_hero.visible = false
				_frame = 0
				_stage = 1
		1:
			if _frame >= GAP:
				_save("b_hero_hidden")
				print("shadowshot: DONE")
				get_tree().quit()


func _save(label: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, label])
	print("shot: ", label)
