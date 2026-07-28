extends Node
## Captures the title screen (over several seconds, so the cinematic camera
## move is visible) and then the in-game HUD.
##
##   godot --path . tools/uishot.tscn --rendering-driver vulkan -- --out=/abs/dir

const MainScene: PackedScene = preload("res://scenes/main.tscn")

var _out: String = "/tmp/uishot"
var _shots: Array = []
var _i: int = 0
var _wait: int = 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	add_child(MainScene.instantiate())
	# label, frames to wait before the shot, action to run after it
	_shots = [
		["menu_a", 150, ""],
		["menu_b", 130, ""],
		["menu_c", 130, "start"],
		["hud_a", 150, ""],
		["hud_b", 130, "attack"],
		["hud_c", 90, ""],
	]
	_wait = _shots[0][1]
	print("uishot: renderer=", RenderingServer.get_video_adapter_name())


func _process(_d: float) -> void:
	if _i >= _shots.size():
		return
	if _wait > 0:
		_wait -= 1
		return
	var shot: Array = _shots[_i]
	get_viewport().get_texture().get_image().save_png("%s/%d_%s.png" % [_out, _i, shot[0]])
	print("shot: ", shot[0])
	match shot[2]:
		"start":
			var gm := get_node_or_null("/root/GameManager")
			if gm:
				gm.start_game()
		"attack":
			if InputMap.has_action("attack"):
				Input.action_press("attack")
				await get_tree().create_timer(0.2).timeout
				Input.action_release("attack")
	_i += 1
	if _i < _shots.size():
		_wait = _shots[_i][1]
	else:
		print("uishot: DONE")
		get_tree().quit()
