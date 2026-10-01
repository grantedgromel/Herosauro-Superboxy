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
## So this boots main.tscn for real and walks the storybook flow the way a
## child does: a key press on Toca para comecar, the bookshelf, the settings
## sheet and its credits, a book, "2 jogadores", Skip on the intro pages, the
## fight; back to the book (which must land on the shelf, not the title); then
## a solo run with the companion. Every single frame counts both, split by
## state. It also prints what the
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
	# The walk picks a book and a roster; keep that out of the real save.
	UIProgress.use_memory_only()


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
			# The title holds still; there is nothing to wait for beyond the
			# logo's entry tween.
			if _clock > 0.6:
				_note("menu settled")
				_ok(_frame().screen == "title", "a fresh session opens on Toca para comecar")
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
					_tap_key()
					_advance("any key on the title")
		3:
			if _clock > 0.4:
				_note("on the shelf")
				_ok(_frame().screen == "shelf", "any key leaves the title for the bookshelf")
				_frame().shelf._gear.pressed.emit()
				_advance("settings open")
		4:
			if _clock > 0.4:
				var settings: SettingsPanel = _frame().settings
				_ok(settings.is_open(), "the gear opens Settings")
				settings._open_credits()
				_advance("credits open")
		5:
			if _clock > 0.4:
				var settings: SettingsPanel = _frame().settings
				var credits: Node = settings._credits_modal
				_ok(credits.call("is_open"), "Credits are reachable from Settings")
				credits.call("close")
				settings.close()
				_advance("panels closed")
		6:
			if _clock > 0.4:
				_note("back on the shelf")
				var frame := _frame()
				frame.shelf.covers[0].pressed.emit()
				_ok(frame.screen == "who", "a book asks who is playing")
				frame.who._cards[1].pressed.emit()
				_ok(frame.screen == "reader" and frame.reader.is_open(),
					"2 jogadores opens the intro pages")
				_ok(GameManager.player_count == 2, "and sets a two-player roster")
				_fight_ms = Time.get_ticks_msec()
				frame.reader.skip()
				_advance("intro skipped")
		7:
			if _clock > 1.4:
				# Wall time, minus the 1.4 s this step deliberately waits and the
				# curtain fade inside it. What is left is main.gd's blocking arena
				# build.
				_fight_ms = Time.get_ticks_msec() - _fight_ms - 1400.0
				_note("fight running")
				_ok(GameManager.state == GameManager.State.PLAYING
					and GameManager.chapter_id == "adamastor", "Skip starts chapter 1")
				GameManager.go_to_menu()
				_advance("back to the book")
		8:
			if _clock > 0.8:
				_note("menu rebuilt")
				_ok(_frame().screen == "shelf", "back to the book lands on the shelf, not the title")
				var frame := _frame()
				frame.choose_chapter("adamastor")
				frame.choose_players(1, 1)
				frame.reader.skip()
				_advance("solo with the companion")
		9:
			if _clock > 1.4:
				_note("second fight running")
				_ok(GameManager.state == GameManager.State.PLAYING, "the solo run starts")
				_ok(GameManager.active_player_ids().size() == 2 and GameManager.is_ai(2),
					"solo brings Super Boxy along as the AI companion")
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
## to know the logo is not sitting on the tap prompt, or a book is not hanging
## off the screen, is to read the rects back and test them.
func _layout_report() -> void:
	var frame := _frame()
	if frame == null:
		return
	var view := Rect2(Vector2.ZERO, frame.size)
	_log.append("  layout at %d x %d:" % [int(frame.size.x), int(frame.size.y)])
	var logo := frame.title.find_child("TitleLogo", true, false) as Control
	var tap := frame.title.find_child("TapToStart", true, false) as Control
	var lr := Rect2(logo.global_position, logo.size)
	var tr := Rect2(tap.global_position, tap.size)
	_log.append("    TitleLogo    x %4d..%4d   y %4d..%4d" % [lr.position.x, lr.end.x, lr.position.y, lr.end.y])
	_log.append("    TapToStart   x %4d..%4d   y %4d..%4d" % [tr.position.x, tr.end.x, tr.position.y, tr.end.y])
	_ok(not lr.intersects(tr), "logo and tap prompt do not overlap at %s" % str(frame.size))
	_ok(view.encloses(tr) and tr.size.y >= 76.0, "tap prompt is in frame and big at %s" % str(frame.size))
	for c: BookCover in frame.shelf.covers:
		var r := Rect2(c.position + c.get_parent().position, c.size)
		_ok(view.encloses(r) and r.size.y >= 76.0,
			"book %s fits the shelf at %s %s" % [c.chapter_id, str(frame.size), str(r)])


## A real key press, through the input pipeline, the way a child taps a key.
func _tap_key() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.physical_keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)


func _frame() -> Control:
	return _menu() as Control


func _live_environment(node: Node) -> Environment:
	var we := node as WorldEnvironment
	if we != null and we.environment != null:
		return we.environment
	for c in node.get_children():
		var found := _live_environment(c)
		if found != null:
			return found
	return null


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
	_log.append("  title screen up in %.0f ms; Skip then stalls ~%.0f ms in main.gd's"
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
