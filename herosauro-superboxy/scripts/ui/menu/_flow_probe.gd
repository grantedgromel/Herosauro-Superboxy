extends Node
## Headless walk through the whole menu -> fight -> menu -> fight loop, asserting
## the one thing the title screen can get catastrophically wrong without anyone
## noticing until they see it.
##
## THAT THING USED TO BE "two arenas at once". The menu owned a copy of
## `bridge_arena.tscn` for its backdrop and main.gd owned another, and if the two
## were ever alive in the same viewport there were two WorldEnvironments and two
## Camera3Ds marked current and the frame became a coin toss.
##
## IT IS NOW "the menu built an arena at all". The backdrop is a static image, so
## the correct count of WorldEnvironments, current Camera3Ds and 3D nodes on the
## title screen is not one, it is ZERO — and that is the property most worth
## locking down, because the way it regresses is somebody adding "just a little"
## 3D behind the type and paying the whole arena build again.
##
## So this boots main.tscn for real, walks MENU -> PLAYING -> MENU -> PLAYING,
## and every single frame counts both, split by state. It also prints what the
## title screen costs to stand up next to what the fight costs, which is the
## comparison the change was made for.
##
## It runs as a SCENE rather than with --script, like the other two probes:
## autoloads are only instantiated on the normal startup path, and every screen
## here talks to GameManager and InputManager.
##
## Run:
##   godot --headless --path . scripts/ui/menu/_flow_probe.tscn

const MainScene: PackedScene = preload("res://scenes/main.tscn")

## Wall time, not accumulated delta, and deliberately so. The engine-wide ban on
## `Time.get_ticks_msec()` is about ANIMATION: a subsystem that reads the wall
## clock makes every screenshot a different screenshot. This is a test harness's
## step clock, it drives nothing that is drawn, and headless runs uncapped — so
## frame counts are meaningless as a duration and eased tweens would never be
## given time to land if this waited on frames instead.
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
## The same two counts, but only sampled while the game is sitting in MENU. These
## are the ones that must be zero.
var _menu_envs: int = 0
var _menu_cams: int = 0
var _menu_3d: int = 0
var _boot_ms: float = 0.0
var _fight_ms: float = 0.0
var _ambients: Array[float] = []
var _log: Array[String] = []
var _fails: int = 0
var _main: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _last == 0.0:
		_last = now
	_clock += minf(now - _last, TICK)
	_last = now

	if _step > 0:
		var envs := _count(get_tree().root, "WorldEnvironment")
		var cams := _count_current_cameras(get_tree().root)
		_max_envs = maxi(_max_envs, envs)
		_max_cams = maxi(_max_cams, cams)
		if GameManager.state == GameManager.State.MENU:
			_menu_envs = maxi(_menu_envs, envs)
			_menu_cams = maxi(_menu_cams, cams)
			_menu_3d = maxi(_menu_3d, _menu_3d_nodes())

	match _step:
		0:
			if _clock > 0.05:
				_boot()
				_advance("boot")
		1:
			# Was 1.6 s, because the menu used to spend most of a second and a half
			# building an arena and then hold a title card over it. There is
			# nothing to wait for now beyond the entry tween.
			if _clock > 0.6:
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
					get_tree().root.size = SWEEP[_sweep_at]
				else:
					get_tree().root.size = SWEEP[0]
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
				_fight_ms = Time.get_ticks_msec()
				_press(&"start")
				_advance("start pressed")
		6:
			if _clock > 1.4:
				# Wall time, minus the 1.4 s this step deliberately waits and the
				# curtain fade inside it. What is left is main.gd's blocking arena
				# build — the cost the title screen used to pay a second copy of.
				_fight_ms = Time.get_ticks_msec() - _fight_ms - 1400.0
				_note("fight running")
				GameManager.go_to_menu()
				_advance("back to menu")
		7:
			if _clock > 0.8:
				_note("menu rebuilt")
				_press(&"start")
				_advance("start pressed again")
		8:
			if _clock > 1.4:
				_note("second fight running")
				_report()
				get_tree().quit(0 if _fails == 0 else 1)


## main.tscn is added under the root rather than swapped in with
## `change_scene_to_file()`, because this probe IS the current scene and swapping
## it out would free the node driving the walk.
func _boot() -> void:
	var t0 := Time.get_ticks_usec()
	_main = MainScene.instantiate()
	get_tree().root.add_child(_main)
	_boot_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_log.append("  main.tscn up in %.1f ms — menu, HUD and results card, no world"
			% _boot_ms)


func _ok(cond: bool, what: String) -> void:
	if cond:
		_log.append("  ok   %s" % what)
	else:
		_fails += 1
		_log.append("  FAIL %s" % what)


func _advance(what: String) -> void:
	_step += 1
	_clock = 0.0
	_log.append("  step %d: %s" % [_step, what])


func _note(what: String) -> void:
	var menu := _menu()
	var arena := get_tree().root.find_child("BridgeArena", true, false)
	var env := _live_environment(get_tree().root)
	if env != null and GameManager.state == GameManager.State.PLAYING:
		_ambients.append(env.ambient_light_energy)
	# `menu_3d` is the count that replaced the old `menu_world=yes/no` column. The
	# menu having ANY VisualInstance3D or Camera3D under it is the regression this
	# whole probe is pointed at.
	_log.append("  %-22s menu_3d=%d  arena_in_tree=%s  state=%d  envs=%d  cams=%d  env#%s amb=%s"
			% [what, _menu_3d_nodes(),
			"yes" if arena != null else "no", GameManager.state,
			_count(get_tree().root, "WorldEnvironment"),
			_count_current_cameras(get_tree().root),
			str(env.get_instance_id() % 100000) if env != null else "-",
			("%.3f" % env.ambient_light_energy) if env != null else "-"])
	if menu == null:
		_log.append("  !! MainMenu is not in the tree")


func _menu() -> Node:
	return get_tree().root.find_child("MainMenu", true, false)


## 3D nodes under the title screen. Zero, always — the backdrop is a TextureRect.
func _menu_3d_nodes() -> int:
	var menu := _menu()
	if menu == null:
		return 0
	return _count(menu, "VisualInstance3D") + _count(menu, "Camera3D") \
			+ _count(menu, "WorldEnvironment")


## The composition, as actually laid out. There is no GPU here, so the only way
## to know the logo is not sitting on Adamastor's head is to read the rects back
## and test them. Anything reported as OVERLAP is a bug.
func _layout_report() -> void:
	var menu := _menu() as Control
	if menu == null:
		return
	_log.append("  layout at %d x %d:" % [int(menu.size.x), int(menu.size.y)])

	var ui: Array[Array] = []
	for id in ["TitleLogo", "MenuList"]:
		var c := menu.find_child(id, true, false) as Control
		if c != null:
			ui.append([id, Rect2(c.global_position, c.size)])

	# The cast is only staged as cut-outs when there is no key art; the cinematic
	# already has all three in it. Said out loud rather than left as an empty
	# section, because "no OVERLAP reported" means nothing if there was nothing to
	# overlap and the reader cannot tell which case they are in.
	var art: Array[Array] = []
	var stage := menu.find_child("HeroStage", true, false)
	if stage == null:
		_log.append("    (key art is in — no cut-outs staged, nothing to collide)")
	else:
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
## directly, so the fade-out and the hand-off to main.gd get exercised exactly as
## a player would drive them.
func _press(id: StringName) -> void:
	var menu := _menu()
	if menu != null and menu.has_method("_on_activated"):
		menu.call("_on_activated", id)
	else:
		_log.append("  !! could not reach MainMenu._on_activated")


func _close_modal() -> void:
	var menu := _menu()
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
	_log.append("")
	_log.append("  title screen up in %.0f ms; START then stalls ~%.0f ms in main.gd's"
			% [_boot_ms, maxf(_fight_ms, 0.0)])
	_log.append("  own arena build, which is the stall the menu used to pay TWICE.")
	# The title screen is a picture. Not "one environment, carefully isolated" —
	# none at all.
	_ok(_menu_envs == 0, "no WorldEnvironment exists while the menu is up (peak %d)" % _menu_envs)
	_ok(_menu_cams == 0, "no current Camera3D exists while the menu is up (peak %d)" % _menu_cams)
	_ok(_menu_3d == 0, "the title screen holds no 3D nodes at all (peak %d)" % _menu_3d)
	_ok(_max_envs <= 1, "never more than one WorldEnvironment anywhere (peak %d)" % _max_envs)
	_ok(_max_cams <= 1, "never more than one current Camera3D anywhere (peak %d)" % _max_cams)
	# LightingRig's renderer tiering multiplies INTO the environment resource, and
	# that resource is shared by path across arena instances. Two fights in a row
	# reading the same ambient is what proves it is not compounding — the menu
	# used to duplicate the Environment to defend against exactly this, and now
	# that it builds no arena the defence has to hold on its own.
	if _ambients.size() >= 2:
		_ok(is_equal_approx(_ambients[0], _ambients[-1]),
			"ambient does not compound across runs (%.3f then %.3f)"
			% [_ambients[0], _ambients[-1]])

	print("[flow] timeline:")
	for line in _log:
		print(line)
	print("")
	print("[flow] %s" % ("PASS" if _fails == 0 else "%d FAILURE(S)" % _fails))
