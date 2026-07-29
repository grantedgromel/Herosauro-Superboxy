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

## Window sizes the composition is checked at. The dummy display server ignores
## --resolution, so the sweep drives root.size directly: 16:9 at the design size,
## 16:10, a 21:9 letterbox, and 4:3, which is the aspect the project's `expand`
## stretch inflates hardest and therefore the one most likely to run the
## character art into the menu column.
const SWEEP: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1920, 1200), Vector2i(2560, 1080), Vector2i(1024, 768),
]

var _clock: float = 0.0
var _last: float = 0.0
var _step: int = 0
var _sweep_at: int = -1
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
				_advance("resize sweep")
		2:
			# One window size per pass, with a settling gap, so the stretch
			# machinery has pushed the new logical size through before the rects
			# are read back.
			if _clock > 0.25:
				if _sweep_at >= 0:
					_layout_report()
				_sweep_at += 1
				_clock = 0.0
				if _sweep_at < SWEEP.size():
					root.size = SWEEP[_sweep_at]
				else:
					root.size = SWEEP[0]
					_press(&"controls")
					_advance("controls open")
		3:
			# Both panels get opened and closed for real, so the modal's tween,
			# its focus hand-off and the InputMap-derived binding list are all
			# exercised inside a live tree rather than only as static builders.
			if _clock > 0.4:
				_note("controls open")
				_close_modal()
				_press(&"credits")
				_advance("credits open")
		4:
			if _clock > 0.4:
				_note("credits open")
				_close_modal()
				_advance("panels closed")
		5:
			if _clock > 0.4:
				_note("back on the menu")
				_press(&"start")
				_advance("start pressed")
		6:
			if _clock > 1.4:
				_note("fight running")
				_gm().call("go_to_menu")
				_advance("back to menu")
		7:
			if _clock > 1.6:
				_note("menu rebuilt")
				_press(&"start")
				_advance("start pressed again")
		8:
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
	var arena := root.find_child("BridgeArena", true, false)
	var env := _live_environment(root)
	# The menu is 2D now, so on a menu row every one of these should read zero /
	# no. A live arena, WorldEnvironment or camera while the title screen is up
	# means main.gd's teardown leaked one, which is the bug this row catches.
	_log.append("  %-22s arena_in_tree=%s  state=%d  envs=%d  cams=%d  env#%s amb=%s"
			% [what,
			"yes" if arena != null else "no", int(_gm().get("state")),
			_count(root, "WorldEnvironment"), _count_current_cameras(root),
			str(env.get_instance_id() % 100000) if env != null else "-",
			("%.3f" % env.ambient_light_energy) if env != null else "-"])


## The composition, as actually laid out. There is no GPU here, so the only way
## to know the logo is not sitting on Adamastor's head is to read the rects back
## and test them. Anything reported as OVERLAP is a bug.
func _layout_report() -> void:
	var menu := root.find_child("MainMenu", true, false) as Control
	if menu == null:
		return
	_log.append("  layout at %d x %d:" % [int(menu.size.x), int(menu.size.y)])

	var ui: Array[Array] = []
	for id in ["TitleLogo", "MenuList", "Hints"]:
		var c := menu.find_child(id, true, false) as Control
		if c != null:
			ui.append([id, Rect2(c.global_position, c.size)])

	var art: Array[Array] = []
	var stage := menu.find_child("HeroStage", true, false)
	if stage != null:
		for fig in stage.get_children():
			var c := fig as Control
			if c != null:
				art.append([c.name, Rect2(c.global_position, c.size)])

	for entry in ui + art:
		var r: Rect2 = entry[1]
		_log.append("    %-12s x %4d..%4d   y %4d..%4d"
				% [entry[0], int(r.position.x), int(r.end.x),
				int(r.position.y), int(r.end.y)])

	for u in ui:
		for a in art:
			var ur: Rect2 = u[1]
			var ar: Rect2 = a[1]
			if ur.intersects(ar):
				var cut := ur.intersection(ar)
				_log.append("    OVERLAP %s / %s  (%d x %d px)"
						% [u[0], a[0], int(cut.size.x), int(cut.size.y)])


func _live_environment(node: Node) -> Environment:
	var we := node as WorldEnvironment
	if we != null and we.environment != null:
		return we.environment
	for c in node.get_children():
		var found := _live_environment(c)
		if found != null:
			return found
	return null


## Reaches into the screen's own handler rather than calling GameManager
## directly, so the fade-out, the world release and the ordering between them all
## get exercised exactly as a player would drive them.
func _press(id: StringName) -> void:
	var menu := root.find_child("MainMenu", true, false)
	if menu != null and menu.has_method("_on_activated"):
		menu.call("_on_activated", id)
	else:
		_log.append("  !! could not reach MainMenu._on_activated")


func _close_modal() -> void:
	var menu := root.find_child("MainMenu", true, false)
	var modal := menu.find_child("Modal", false, false) if menu != null else null
	if modal != null:
		modal.call("close")


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
