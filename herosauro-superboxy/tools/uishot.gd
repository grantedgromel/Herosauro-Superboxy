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
	#
	# The frame counts are small on purpose. Everything that has to settle before
	# a shot — entry tweens, the cinematic camera move, the HUD's reveal — is
	# driven by wall-clock delta, and under lavapipe a frame is seconds, not
	# milliseconds. Waiting 150 frames does not buy a later moment in the
	# animation, it just costs 20 minutes; the tweens are long finished by frame
	# ten. What the counts still buy is a couple of frames for the renderer's
	# temporal passes to converge before the buffer is read back.
	# The first wait is the long one. The menu's reveal is gated on the arena
	# actually finishing its build, not on a timer, and that build is where all
	# the terrain, facades and landmarks are generated — under a software
	# rasteriser it is not done at frame twelve, and the shot came back as the
	# logo over near-black.
	_shots = [
		["menu_a", 26, ""],
		["menu_b", 10, ""],
		["menu_c", 10, "start"],
		["hud_a", 14, ""],
		["hud_b", 10, "attack"],
		["hud_c", 8, ""],
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
