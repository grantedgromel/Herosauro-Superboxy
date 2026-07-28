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

## Off to the side and low, looking across the hero rather than down the deck.
## Down the deck is the one angle that hides a shadow running along it.
const CAM_POS := Vector3(6.0, 3.4, 11.0)
const HERO_POS := Vector3(0.0, 1.05, 0.0)

const SETTLE := 26   ## frames for the arena build + the renderer's temporal passes
const GAP := 8       ## frames between the two exposures

var _out: String = "/tmp/shadowshot"
var _hero: Node3D
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
	_hero.global_position = HERO_POS

	# Our own camera, marked current after the arena's so it wins.
	var cam := Camera3D.new()
	cam.name = "ProbeCamera"
	add_child(cam)
	cam.global_position = CAM_POS
	cam.look_at(HERO_POS + Vector3(0.0, -0.3, 0.0), Vector3.UP)
	cam.fov = 50.0
	cam.current = true

	print("shadowshot: adapter=", RenderingServer.get_video_adapter_name())


func _process(_d: float) -> void:
	_frame += 1
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
