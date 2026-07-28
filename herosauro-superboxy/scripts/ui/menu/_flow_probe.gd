extends SceneTree
## Headless check on the one thing the title screen can get catastrophically
## wrong without anyone noticing until they see it: the menu now owns a copy of
## bridge_arena.tscn, and main.gd owns another. If the two are ever alive in the
## same viewport at the same time there are two WorldEnvironments and two
## Camera3Ds marked current, and the frame becomes a coin toss.
##
## So this boots main.tscn for real, walks MENU -> PLAYING -> MENU -> PLAYING,
## and every single frame counts both. Anything above one at any point is a bug.
##
## Run:
##   godot --headless --script res://scripts/ui/menu/_flow_probe.gd --path .

const TICK := 0.05

var _clock: float = 0.0
var _last: float = 0.0
var _step: int = 0
var _max_envs: int = 0
var _max_cams: int = 0
var _log: Array[String] = []


func _initialize() -> void:
	process_frame.connect(_tick)


func _tick() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _last == 0.0:
		_last = now
	_clock += minf(now - _last, TICK)
	_last = now

	if _step > 0:
		var envs := _count(root, "WorldEnvironment")
		var cams := _count_current_cameras(root)
		_max_envs = maxi(_max_envs, envs)
		_max_cams = maxi(_max_cams, cams)

	match _step:
		0:
			if _clock > 0.05:
				change_scene_to_file("res://scenes/main.tscn")
				_advance("boot")
		1:
			if _clock > 1.6:
				_note("menu settled")
				_press(&"start")
				_advance("start pressed")
		2:
			if _clock > 1.4:
				_note("fight running")
				_gm().call("go_to_menu")
				_advance("back to menu")
		3:
			if _clock > 1.6:
				_note("menu rebuilt")
				_press(&"start")
				_advance("start pressed again")
		4:
			if _clock > 1.4:
				_note("second fight running")
				_report()
				quit()


## Autoloads are not registered as compile-time globals when Godot is started
## with --script, so GameManager has to be reached by path here.
func _gm() -> Node:
	return root.get_node_or_null("/root/GameManager")


func _advance(what: String) -> void:
	_step += 1
	_clock = 0.0
	_log.append("  step %d: %s" % [_step, what])


func _note(what: String) -> void:
	var menu := root.find_child("MainMenu", true, false)
	var world := menu.find_child("MenuWorld", false, false) if menu != null else null
	var arena := root.find_child("BridgeArena", true, false)
	_log.append("  %-22s menu_world=%s  arena_in_tree=%s  state=%d  envs=%d  current_cams=%d"
			% [what, "yes" if world != null else "no",
			"yes" if arena != null else "no", int(_gm().get("state")),
			_count(root, "WorldEnvironment"), _count_current_cameras(root)])


## Reaches into the screen's own handler rather than calling GameManager
## directly, so the fade-out, the world release and the ordering between them all
## get exercised exactly as a player would drive them.
func _press(id: StringName) -> void:
	var menu := root.find_child("MainMenu", true, false)
	if menu != null and menu.has_method("_on_activated"):
		menu.call("_on_activated", id)
	else:
		_log.append("  !! could not reach MainMenu._on_activated")


func _count(node: Node, type_name: String) -> int:
	var n := 1 if node.is_class(type_name) else 0
	for c in node.get_children():
		n += _count(c, type_name)
	return n


func _count_current_cameras(node: Node) -> int:
	var n := 0
	var cam := node as Camera3D
	if cam != null and cam.current:
		n += 1
	for c in node.get_children():
		n += _count_current_cameras(c)
	return n


func _report() -> void:
	print("[flow] timeline:")
	for line in _log:
		print(line)
	print("[flow] peak WorldEnvironments: %d (must be 1)" % _max_envs)
	print("[flow] peak current Camera3Ds: %d (must be 1)" % _max_cams)
