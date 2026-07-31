extends Node
## Reproducible single-shot capture — the regression gate the whole review loop
## rests on.
##
## This replaces tools/shotrunner.gd, which captured every shot from ONE process.
## That is the difference that matters: a shared process leaks auto-exposure
## adaptation, particle age, tween phase and animation time forward, so shot 7
## depended on shot 6 and two runs of the same build never agreed. Here the
## orchestrator (tools/harness.py) spawns one Godot per shot and this script
## takes exactly one picture, so every capture starts from a cold engine.
##
## Three things make the picture identical across runs and machines:
##
##  1. ISOLATION      — one process, one shot. See above.
##  2. FIXED TIMESTEP — launched under --fixed-fps, so `delta` is exactly 1/fps
##                      every frame no matter how slow the software rasteriser
##                      actually is. `settle` frames is therefore an exact
##                      simulated duration, not "however far it got in a second".
##  3. SEEDED WORLD   — the global RNG is seeded here, before any builder runs,
##                      so procedural placement is the same placement.
##
## Usage (normally via tools/harness.py, which handles the Xvfb + lavapipe env):
##   godot --path . tools/baseline.tscn --rendering-driver vulkan \
##         --fixed-fps 60 --resolution 1280x720 -- --shot=01_deck_mid --out=/abs/dir

const MANIFEST := "res://tools/shots.json"

const WorldScene: PackedScene = preload("res://scenes/world/bridge_arena.tscn")
const MainScene: PackedScene = preload("res://scenes/main.tscn")

## Fixed for the life of the project. Changing it invalidates every baseline.
const WORLD_SEED := 1881

var _shot: Dictionary = {}
var _out_dir: String = "/tmp/shots"
var _frames_left: int = 0
var _script_beats: Array = []
var _beat_held: int = 0
var _held_action: String = ""
var _done: bool = false


func _ready() -> void:
	seed(WORLD_SEED)

	var name := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			name = arg.substr(7)
		elif arg.begins_with("--out="):
			_out_dir = arg.substr(6)

	_shot = _find_shot(name)
	if _shot.is_empty():
		push_error("baseline: no shot named '%s' in %s" % [name, MANIFEST])
		get_tree().quit(2)
		return

	DirAccess.make_dir_recursive_absolute(_out_dir)
	_script_beats = _shot.get("script", []).duplicate()
	_frames_left = int(_shot.get("settle", 24))

	print("baseline: shot=%s kind=%s renderer=%s"
			% [name, _shot.get("kind", "?"), RenderingServer.get_video_adapter_name()])

	match String(_shot.get("kind", "world")):
		"world":
			_setup_world()
		"game":
			_setup_game()
		"menu":
			_setup_menu()
		_:
			push_error("baseline: unknown kind " + String(_shot.get("kind", "")))
			get_tree().quit(2)


func _find_shot(name: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(MANIFEST)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("baseline: could not parse " + MANIFEST)
		return {}
	for s in parsed.get("shots", []):
		if String(s.get("name", "")) == name:
			return s
	return {}


# --- Scene setup -------------------------------------------------------------

func _setup_world() -> void:
	add_child(WorldScene.instantiate())
	var cam := Camera3D.new()
	cam.current = true
	add_child(cam)
	cam.global_position = _vec(_shot["pos"])
	cam.look_at(_vec(_shot["look"]), Vector3.UP)
	cam.fov = float(_shot.get("fov", 55.0))


func _setup_game() -> void:
	add_child(MainScene.instantiate())
	# Start the match the same way a player would, rather than reaching into
	# main.gd — the contract says cross-stream traffic goes through GameManager.
	await get_tree().process_frame
	var gm := get_node_or_null("/root/GameManager")
	if gm == null:
		push_error("baseline: GameManager autoload missing")
		get_tree().quit(2)
		return
	gm.start_game()


func _setup_menu() -> void:
	add_child(MainScene.instantiate())


func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


# --- Frame pump --------------------------------------------------------------

func _process(_delta: float) -> void:
	if _done:
		return

	# Scripted input beats run to completion before the settle countdown starts,
	# so "settle" always means the same thing: frames of quiet before the shutter.
	if not _script_beats.is_empty():
		_advance_script()
		return

	if _frames_left > 0:
		_frames_left -= 1
		return

	_done = true
	_capture()


func _advance_script() -> void:
	var beat: Array = _script_beats[0]
	var action := String(beat[0])
	var hold := int(beat[1])

	if _beat_held == 0 and action != "":
		if InputMap.has_action(action):
			Input.action_press(action)
			_held_action = action
		else:
			push_warning("baseline: no input action '%s'" % action)

	_beat_held += 1
	if _beat_held >= hold:
		if _held_action != "":
			Input.action_release(_held_action)
			_held_action = ""
		_beat_held = 0
		_script_beats.pop_front()


func _capture() -> void:
	# Grab AFTER the frame is on the GPU, not before. Reading the viewport
	# texture inside _process returns the previous frame, which quietly shifts
	# every capture one frame earlier than the settle count claims.
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out_dir, String(_shot["name"])]
	var err := img.save_png(path)
	if err != OK:
		push_error("baseline: could not write %s (err %d)" % [path, err])
		get_tree().quit(1)
		return
	print("baseline: wrote %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	get_tree().quit(0)
