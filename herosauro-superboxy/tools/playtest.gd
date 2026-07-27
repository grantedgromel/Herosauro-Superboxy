extends Node
## Headless gameplay harness — drives a real match so the review loop exercises
## the player controller, camera, physics and boss, not just static scenery.
##
## Boots the real main scene, starts a match, then feeds synthetic input for a
## scripted route (walk to each bridge end, jump, attack) while watching for
## runtime errors and clipping. Captures screenshots along the way.
##
## Usage:
##   godot --path . tools/playtest.tscn -- --out=/abs/dir [--frames=1800]

const MainScene: PackedScene = preload("res://scenes/main.tscn")

## Scripted beats: [label, action_or_empty, frames_to_hold]
const ROUTE: Array = [
	["spawn", "", 60],
	["walk_left", "move_left", 220],
	["at_porto_end", "", 30],
	["jump", "jump", 20],
	["after_jump", "", 60],
	["walk_right", "move_right", 380],
	["mid_bridge", "", 30],
	["attack", "attack", 40],
	["walk_right2", "move_right", 300],
	["at_gaia_end", "", 40],
]

var _out_dir: String = "/tmp/playtest"
var _step: int = 0
var _held: int = 0
var _errors: Array[String] = []
var _min_y: float = 1e9
var _started: bool = false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	add_child(MainScene.instantiate())
	print("playtest: renderer=", RenderingServer.get_video_adapter_name())
	# Let the menu build, then start a match the same way the player would.
	await get_tree().create_timer(1.0).timeout
	if Engine.has_singleton("GameManager") or get_node_or_null("/root/GameManager"):
		var gm := get_node_or_null("/root/GameManager")
		if gm and gm.has_method("start_game"):
			gm.start_game()
			_started = true
			print("playtest: match started")
	if not _started:
		push_error("playtest: could not start match")


func _physics_process(_delta: float) -> void:
	if not _started:
		return
	if _step >= ROUTE.size():
		_finish()
		return

	var beat: Array = ROUTE[_step]
	var action: String = beat[1]
	var hold: int = beat[2]

	if _held == 0 and action != "":
		if InputMap.has_action(action):
			Input.action_press(action)
		else:
			_errors.append("missing input action: " + action)

	_held += 1

	# Track the player's lowest Y so we can detect falling through the deck.
	var players := get_tree().get_nodes_in_group("players")
	for p in players:
		_min_y = minf(_min_y, (p as Node3D).global_position.y)

	if _held >= hold:
		if action != "" and InputMap.has_action(action):
			Input.action_release(action)
		_shoot(str(beat[0]))
		_step += 1
		_held = 0


func _shoot(label: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%02d_%s.png" % [_out_dir, _step, label])
	var players := get_tree().get_nodes_in_group("players")
	var pos := "none"
	if not players.is_empty():
		pos = str((players[0] as Node3D).global_position.round())
	print("beat: ", label, "  player=", pos)


func _finish() -> void:
	print("playtest: lowest player Y = ", _min_y)
	if _min_y < -4.0:
		print("playtest: WARNING player fell below deck (possible clipping)")
	for e in _errors:
		print("playtest: ERROR ", e)
	print("playtest: DONE")
	get_tree().quit()
