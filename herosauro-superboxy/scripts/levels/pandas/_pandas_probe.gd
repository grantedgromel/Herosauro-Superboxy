extends Node
## Pandas probe: chapter "pandas" played end to end.
##
##   godot --headless --path . scripts/levels/pandas/_pandas_probe.tscn
##
## Boots main.tscn on chapter "pandas", solo with the companion and Ajudas on,
## and plays the WHOLE level: hero 1 is driven only through InputManager's
## virtual channel. The level's own place_heroes_near() teleports the pair next
## to each job (a test shortcut for the walking), but every objective step is a
## real hit or a real pickup: heaps are jabbed until they clear, door stars are
## jabbed (and once hit with Dino Energy, which must count as two) until the
## house transforms, suitcases are walked into (and jumped up to, on the
## balcony). Then: the stage-2 objective, the finale, VICTORY inside a frame
## budget, never DEFEAT, no engine or script errors from the moment the level
## is built, a mesh/draw-call budget, and PLAY AGAIN resetting the street.
##
## Exit code is the verdict.

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const LEVEL_SCENE := "res://scenes/levels/pandas/pandas_level.tscn"
const TICK := 90.0
const PILE_REACH := 2.4
const STAR_REACH := 2.1
const SWING_GAP := 0.45
## The whole run, stage 1 to VICTORY, must fit in this many physics frames.
const FRAME_BUDGET := int(240.0 * TICK)
const HOUSE_BUDGET := int(14.0 * TICK)
const MAX_MESH_INSTANCES := 175
const MAX_DRAW_ESTIMATE := 250
const MAX_BUILD_MS := 1500.0


class ErrorCounter extends Logger:
	var errors: int = 0
	var first: Array[String] = []
	var armed: bool = false

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if not armed or error_type == ERROR_TYPE_WARNING:
			return
		errors += 1
		if first.size() < 8:
			first.append("%s:%d %s %s %s" % [file, line, function, code, rationale])

	func _log_message(_message: String, _error: bool) -> void:
		pass


var _pass: int = 0
var _fail: int = 0
var _main: Node = null
var _level: Node3D = null
var _saw_defeat: bool = false
var _beats: Array[String] = []
var _objectives: Array[Dictionary] = []
var _frames: int = 0
var _log := ErrorCounter.new()
var _orb_steps: Array[int] = []


func _ready() -> void:
	OS.add_logger(_log)
	await get_tree().process_frame
	UIProgress.use_memory_only()
	# Assigned, not set through the setters: the setters persist to
	# user://settings.cfg, and a probe must not change the next run's defaults.
	GameManager.assists = true
	GameManager.companion = true
	GameManager.narration = false
	GameManager.state_changed.connect(func(s: int) -> void:
		if s == GameManager.State.DEFEAT:
			_saw_defeat = true)
	GameManager.story_beat.connect(func(id: String) -> void: _beats.append(id))
	GameManager.objective_changed.connect(func(label: Dictionary, done: int, total: int) -> void:
		_objectives.append({"label": label, "done": done, "total": total}))
	await _run()
	_ok(_log.errors == 0, "no engine or script errors from the level build to the end (%d)" % _log.errors)
	for e in _log.first:
		printerr("     ", e)
	print("\npandas probe: %d passed, %d failed" % [_pass, _fail])
	OS.remove_logger(_log)
	get_tree().quit(1 if _fail > 0 else 0)


func _run() -> void:
	_main = MainScene.instantiate()
	add_child(_main)
	await _settle(4)
	_log.armed = true
	GameManager.set_chapter("pandas")
	GameManager.set_player_count(1)
	GameManager.set_human_hero(1)
	GameManager.start_game()
	await _settle(8)
	if not await _check_world():
		return
	await _play_houses()
	await _play_cases()
	await _play_finale()
	_ok(_frames <= FRAME_BUDGET, "the whole level took %d physics frames (%.0f s), budget %d"
		% [_frames, float(_frames) / TICK, FRAME_BUDGET])
	_ok(not _saw_defeat, "DEFEAT was never entered")
	await _check_play_again()


# --- The level loads ------------------------------------------------------------------

func _check_world() -> bool:
	_level = LevelBase.current(get_tree()) as Node3D
	_ok(_level != null and _level.scene_file_path == LEVEL_SCENE, "the pandas level is loaded (%s)"
		% (_level.scene_file_path if _level else "none"))
	if _level == null:
		return false
	_ok(get_tree().get_first_node_in_group("boss") == null, "no boss in the pandas street")
	_ok(_hero_ids() == [1, 2] and GameManager.is_ai(2), "solo with the companion: heroes %s, hero 2 is the robot"
		% str(_hero_ids()))
	_ok(GameManager.objective_total() == 8 and GameManager.objective_done() == 0,
		"begin() set the objective 0/8 (got %d/%d)" % [GameManager.objective_done(), GameManager.objective_total()])
	_ok(str(GameManager.objective_label().get("en", "")) == "Fix up the houses!"
		and str(GameManager.objective_label().get("pt", "")) == "Repara as casas!",
		"stage 1 label %s" % str(GameManager.objective_label()))
	_ok((_level as LevelBase).music_track() == "title", "music is the calm title theme")
	_ok((_level as LevelBase).ground_surface() == ToonFactory.Surface.COBBLE, "the ground is cobble")
	var houses: Array = _level.get("houses")
	_ok(houses.size() == 8, "eight houses (%d)" % houses.size())
	var lit := 0
	for h in houses:
		if h.star.is_lit() or h.star.is_in_group("targets"):
			lit += 1
	_ok(lit == 0, "no door star is lit while its rubbish is in the way (%d lit)" % lit)
	_ok(get_tree().get_nodes_in_group("targets").size() == 9,
		"targets are the 8 heaps and the last rubbish (%d)" % get_tree().get_nodes_in_group("targets").size())
	var build_ms: float = _level.get("build_ms")
	_ok(build_ms > 0.0 and build_ms < MAX_BUILD_MS, "the level builds in %.0f ms (< %.0f)" % [build_ms, MAX_BUILD_MS])
	var census: Dictionary = _level.render_census()
	print("  -- census ", census)
	_ok(int(census["mesh_instances"]) <= MAX_MESH_INSTANCES,
		"MeshInstance3D count %d <= %d" % [census["mesh_instances"], MAX_MESH_INSTANCES])
	_ok(int(census["draw_estimate"]) <= MAX_DRAW_ESTIMATE,
		"draw-call estimate %d <= %d (%d surfaces + %d casters x splits)"
			% [census["draw_estimate"], MAX_DRAW_ESTIMATE, census["surfaces"], census["casters"]])
	# The co-op camera looks where the level says, from the open square.
	await _settle(60)
	var cam := get_viewport().get_camera_3d()
	if cam:
		var fwd := _flat(-cam.global_basis.z).normalized()
		var want := _flat((_level as LevelBase).camera_focus() - _centroid()).normalized()
		_ok(fwd.dot(want) > 0.85, "the camera looks toward camera_focus() (dot %.2f)" % fwd.dot(want))
		_ok(_camera_in_open(cam.global_position), "the camera stands in the open (%s)" % str(cam.global_position))
	var hint := (_level as LevelBase).hint_target()
	_ok(hint.is_finite(), "hint_target points somewhere (%s)" % str(hint))
	return true


# --- Stage 1: eight houses -------------------------------------------------------------

func _play_houses() -> void:
	var houses: Array = _level.get("houses")
	var order := _house_order(houses)
	var fixed := 0
	for n in order.size():
		var h: Node3D = houses[order[n]]
		if h.is_repaired():
			fixed += 1
			continue
		var before := GameManager.objective_done()
		_level.place_heroes_near(h.pile.global_position, 3.0)
		await _settle(3)
		# Clear the heap with jabs.
		var layers0: int = h.pile.layers_left()
		var frames := 0
		while not h.pile.is_cleared() and frames < HOUSE_BUDGET:
			_drive(h.pile.global_position, PILE_REACH, frames)
			await _tick()
			frames += 1
		_ok(h.pile.is_cleared(), "house %d: the heap (%d layers) is cleared by real hits" % [order[n], layers0])
		if n == 0:
			_ok(layers0 == 1, "the first house's heap is tiny (%d layer)" % layers0)
		await _tick()
		_ok(h.star.is_lit() and h.star.is_in_group("targets"), "house %d: clearing the heap lights its door star" % order[n])
		if n == 1:
			await _dino_test(h)
		# Fix it with jabs on the star.
		while not h.is_repaired() and frames < HOUSE_BUDGET:
			_drive(h.star.global_position, STAR_REACH, frames)
			await _tick()
			frames += 1
		InputManager.set_virtual_move(1, Vector2.ZERO)
		_ok(h.is_repaired(), "house %d is repaired by hits on its door star (%d frames)" % [order[n], frames])
		fixed += 1
		_ok(GameManager.objective_done() == fixed and GameManager.objective_done() > before,
			"...objective %d/%d" % [GameManager.objective_done(), GameManager.objective_total()])
		_ok(not h.star.is_in_group("targets"), "...and its star leaves group 'targets'")
		if fixed == 4:
			await _settle(2)
			_ok(_beats.has("p08"), "at 4/8 the level asks for story beat p08 (beats %s)" % str(_beats))
		await _settle(20)
	_ok(GameManager.objective_done() == 8, "all eight houses fixed: %d/8" % GameManager.objective_done())
	var mood: float = _level.get("_mood_target")
	_ok(mood >= 0.99, "the light has warmed to evening (mood target %.2f)" % mood)


## Dino Energy on a lit star counts as two hits.
func _dino_test(h: Node3D) -> void:
	_orb_steps.clear()
	var on_struck := func(steps: int) -> void: _orb_steps.append(steps)
	h.star.struck.connect(on_struck)
	_level.place_heroes_near(h.star.global_position, 4.2)
	await _settle(30)   # let the companion's own swings settle before the orb
	_orb_steps.clear()
	var hero := _hero(1)
	var to := _flat(h.star.global_position - hero.global_position)
	InputManager.set_virtual_move(1, _to_pad(to.normalized() * 0.3))
	await _tick()
	InputManager.press_virtual(1, &"ability")
	for i in int(1.2 * TICK):
		InputManager.set_virtual_move(1, Vector2.ZERO)
		await _tick()
		if _orb_steps.has(2):
			break
	h.star.struck.disconnect(on_struck)
	_ok(_orb_steps.has(2), "Dino Energy on a door star counts as two hits (steps seen %s)" % str(_orb_steps))


# --- Stage 2: four suitcases -------------------------------------------------------------

func _play_cases() -> void:
	var frames := 0
	while GameManager.objective_total() != 4 and frames < int(8.0 * TICK):
		await _tick()
		frames += 1
	_ok(GameManager.objective_total() == 4 and GameManager.objective_done() == 0,
		"stage 2 starts: objective 0/4 (got %d/%d)" % [GameManager.objective_done(), GameManager.objective_total()])
	_ok(str(GameManager.objective_label().get("en", "")) == "Find the pandas' suitcases!",
		"stage 2 label %s" % str(GameManager.objective_label()))
	var cases: Array = _level.get("suitcases")
	var waiting := 0
	await _settle(int(2.5 * TICK))
	for s in cases:
		if s.is_waiting():
			waiting += 1
	_ok(waiting == 4, "four suitcases have appeared (%d)" % waiting)
	for i in cases.size():
		var s: Node3D = cases[i]
		var before := GameManager.objective_done()
		var spot: Vector3 = s.global_position
		_level.place_heroes_near(spot, 2.6)
		await _settle(3)
		var f := 0
		var hero := _hero(1)
		while not s.is_collected() and f < int(10.0 * TICK):
			var to := _flat(spot - hero.global_position)
			InputManager.set_virtual_move(1, _to_pad(to.normalized()))
			# The balcony one is up high: jump to it.
			if spot.y > 1.0 and to.length() < 2.2 and f % int(0.9 * TICK) == 0:
				InputManager.press_virtual(1, &"jump")
			await _tick()
			f += 1
		InputManager.set_virtual_move(1, Vector2.ZERO)
		_ok(s.is_collected(), "suitcase %d (%s) is collected by touching it (%d frames)" % [i, _where(i), f])
		_ok(GameManager.objective_done() == before + 1, "...objective %d/4" % GameManager.objective_done())
		if i < cases.size() - 1:
			await _settle(int(1.4 * TICK))
			var panda: Node3D = s.get("panda")
			_ok(s.get_parent() == panda.get("carry_anchor"), "...it flew to its panda, who now holds it")


func _where(i: int) -> String:
	return ["behind the fountain", "on the low balcony", "on the bench", "by the last rubbish"][i]


# --- Finale ---------------------------------------------------------------------------------

func _play_finale() -> void:
	var f := 0
	var saw_finale := false
	var lights := 0
	var water := false
	while GameManager.state == GameManager.State.PLAYING and f < int(25.0 * TICK):
		if _level.stage_name() == "finale":
			saw_finale = true
			var bulbs: MultiMeshInstance3D = _level.get("_bulbs")
			lights = maxi(lights, bulbs.multimesh.visible_instance_count)
			water = water or (_level.get("_water") as Node3D).visible
		await _tick()
		f += 1
	_ok(saw_finale, "4/4 starts the finale")
	_ok(lights > 0, "string lights unfurl across the street (%d bulbs)" % lights)
	_ok(water, "the fountain sprays")
	_ok(GameManager.state == GameManager.State.VICTORY, "the finale ends in VICTORY (state %d, %.1f s)"
		% [GameManager.state, float(f) / TICK])
	var inside := 0
	for p in _level.get("pandas"):
		if not (p as Node3D).visible:
			inside += 1
	_ok(inside == 4, "the four pandas walked into their new house (%d inside)" % inside)


func _check_play_again() -> void:
	var before := LevelBase.current(get_tree())
	GameManager.start_game()
	await _settle(10)
	_ok(LevelBase.current(get_tree()) == before, "PLAY AGAIN reuses the level")
	_ok(GameManager.objective_done() == 0 and GameManager.objective_total() == 8, "...objective back to 0/8")
	var broken := 0
	for h in _level.get("houses"):
		if not h.is_repaired() and not h.pile.is_cleared():
			broken += 1
	_ok(broken == 8, "...every house is broken again with its heap (%d)" % broken)
	var home := 0
	for s in _level.get("suitcases"):
		if s.get_parent() == _level and not s.visible:
			home += 1
	_ok(home == 4, "...the suitcases are back in hiding (%d)" % home)
	var out := 0
	for p in _level.get("pandas"):
		if (p as Node3D).visible:
			out += 1
	_ok(out == 4, "...and the pandas are back outside (%d)" % out)


# --- Driving ---------------------------------------------------------------------------------

## Walk hero 1 to within `reach` of `target`, then jab on a steady rhythm.
func _drive(target: Vector3, reach: float, frame: int) -> void:
	var hero := _hero(1)
	if hero == null:
		return
	var to := _flat(target - hero.global_position)
	if to.length() > reach:
		InputManager.set_virtual_move(1, _to_pad(to.normalized()))
	else:
		InputManager.set_virtual_move(1, _to_pad(to.normalized() * 0.15))
		if frame % int(SWING_GAP * TICK) == 0:
			InputManager.press_virtual(1, &"attack")


func _house_order(houses: Array) -> Array[int]:
	# The first house (tiny heap) first, then nearest-next, like a child would.
	var left: Array[int] = []
	for i in houses.size():
		left.append(i)
	var order: Array[int] = []
	var first: int = _level.get("FIRST_HOUSE")
	order.append(first)
	left.erase(first)
	var at: Vector3 = houses[first].global_position
	while not left.is_empty():
		var best := left[0]
		for i in left:
			if houses[i].global_position.distance_to(at) < houses[best].global_position.distance_to(at):
				best = i
		order.append(best)
		left.erase(best)
		at = houses[best].global_position
	return order


func _camera_in_open(p: Vector3) -> bool:
	return p.x > -17.0 and (absf(p.z) < 12.5 or p.x > 8.5)


func _centroid() -> Vector3:
	var s := Vector3.ZERO
	var n := 0
	for h in get_tree().get_nodes_in_group("players"):
		s += (h as Node3D).global_position
		n += 1
	return s / float(maxi(1, n))


func _to_pad(world: Vector3) -> Vector2:
	var cam := get_viewport().get_camera_3d()
	var fwd := Vector3.FORWARD
	if cam:
		fwd = _flat(-cam.global_basis.z).normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	return Vector2(world.dot(right), world.dot(fwd)).limit_length(1.0)


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _tick() -> void:
	_frames += 1
	await get_tree().physics_frame


func _settle(frames: int) -> void:
	for i in frames:
		await _tick()


func _hero_ids() -> Array[int]:
	var out: Array[int] = []
	for p in get_tree().get_nodes_in_group("players"):
		out.append(int(p.player_id))
	out.sort()
	return out


func _hero(id: int) -> PlayerBase:
	for p in get_tree().get_nodes_in_group("players"):
		if p is PlayerBase and int(p.player_id) == id:
			return p as PlayerBase
	return null


func _ok(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  ok   ", label)
	else:
		_fail += 1
		printerr("  FAIL ", label)
