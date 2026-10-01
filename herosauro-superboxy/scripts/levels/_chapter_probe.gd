extends Node
## Chapter probe: the storybook spine end to end, on the sandbox level.
##
##   godot --headless --path . scripts/levels/_chapter_probe.tscn
##
## Boots main.tscn, picks chapter "sandbox", solo with the companion and Ajudas
## on, and plays it: hero 1 is driven ONLY through InputManager's virtual
## channel, to each dummy in turn, jabbing until all three are down. Then:
## objective 3/3 and VICTORY; PLAY AGAIN reuses the level and resets it; with
## Ajudas on nothing reaches DEFEAT (both heroes at zero bubble back at full
## health, a fall bubbles back with no penalty, damage is halved, health
## regenerates); the companion moved and kept to its share of the attacks; and
## switching back to "adamastor" rebuilds the bridge with its giant.
##
## Exit code is the verdict.

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const TICK := 90.0
const REACH := 2.8

var _pass: int = 0
var _fail: int = 0
var _main: Node = null
var _saw_defeat: bool = false
var _human_presses: int = 0


func _ready() -> void:
	await get_tree().process_frame
	# Assigned, not set through the setters: the setters persist to
	# user://settings.cfg, and a probe must not change the next run's defaults.
	GameManager.assists = true
	GameManager.companion = true
	GameManager.state_changed.connect(_on_state_changed)
	await _run()
	print("\nchapter probe: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _on_state_changed(s: int) -> void:
	if s == GameManager.State.DEFEAT:
		_saw_defeat = true


func _run() -> void:
	await _start("sandbox", 1, 1)
	await _check_world()
	await _check_play_through()
	await _check_play_again()
	await _check_never_defeat()
	await _check_back_to_bridge()
	_ok(not _saw_defeat, "Ajudas on: DEFEAT was never entered during the whole probe")


# --- The level loads in place of the bridge -------------------------------------

func _check_world() -> void:
	var level := LevelBase.current(get_tree())
	_ok(level != null, "a LevelBase is in group 'level'")
	if level == null:
		return
	_ok(level.scene_file_path == "res://scenes/levels/sandbox/sandbox_level.tscn",
		"it is the sandbox scene (%s)" % level.scene_file_path)
	_ok(get_tree().get_first_node_in_group("boss") == null, "no Adamastor in a level")
	_ok(_main.get_node_or_null("World/Props") == null, "no bridge PropSpawner in a level")
	_ok(_hero_ids() == [1, 2], "solo with the companion fields both heroes, got %s" % str(_hero_ids()))
	_ok(GameManager.is_ai(2) and not GameManager.is_ai(1), "hero 2 is the robot")
	_ok(_main.get_node_or_null("World/CompanionAI2") != null, "main.gd added the companion AI")
	var h1 := _hero(1)
	var gap := h1.global_position.distance_to(level.spawn_point(1)) if h1 else INF
	_ok(gap < 1.5, "hero 1 spawned at level.spawn_point(1) (%.2f m)" % gap)
	_ok(GameManager.objective_total() == 3 and GameManager.objective_done() == 0,
		"begin() set the objective 0/3 (got %d/%d)"
			% [GameManager.objective_done(), GameManager.objective_total()])
	_ok(str(GameManager.objective_label().get("en", "")) == "Hit the 3 targets!",
		"objective label %s" % str(GameManager.objective_label()))
	_ok(get_tree().get_nodes_in_group("targets").size() == 3, "three dummies in group 'targets'")

	# The co-op camera has no giant to look at, so it must look at the level's focus.
	await _settle(60)
	var cam := get_viewport().get_camera_3d()
	var rig := get_tree().get_first_node_in_group("camera_rig")
	_ok(rig != null and rig.is_group_framing(), "the camera group-frames the pair")
	if cam:
		var fwd := -cam.global_basis.z
		fwd.y = 0.0
		var centre := (_hero(1).global_position + _hero(2).global_position) * 0.5
		var want := level.camera_focus() - centre
		want.y = 0.0
		var dot := fwd.normalized().dot(want.normalized())
		_ok(dot > 0.9, "the camera looks toward level.camera_focus() (dot %.2f)" % dot)


# --- Play it with virtual input ---------------------------------------------------

func _check_play_through() -> void:
	var hero := _hero(1)
	var robot := _hero(2)
	var ai: Node = _main.get_node_or_null("World/CompanionAI2")
	if hero == null or robot == null:
		_ok(false, "both heroes exist for the play-through")
		return
	var robot_start := robot.global_position
	var robot_travel := 0.0
	var swing_gap := 0.0
	_human_presses = 0
	var frames := int(45.0 * TICK)
	for i in frames:
		if GameManager.state != GameManager.State.PLAYING:
			break
		robot_travel = maxf(robot_travel, _flat(robot.global_position - robot_start).length())
		var target := _nearest_target(hero.global_position)
		if target == null:
			InputManager.set_virtual_move(1, Vector2.ZERO)
		else:
			var to := _flat(target.global_position - hero.global_position)
			if to.length() > REACH:
				InputManager.set_virtual_move(1, _to_pad(to.normalized()))
			else:
				InputManager.set_virtual_move(1, Vector2.ZERO)
				swing_gap -= 1.0 / TICK
				if swing_gap <= 0.0:
					swing_gap = 0.4
					_human_presses += 1
					InputManager.press_virtual(1, &"attack")
		await get_tree().physics_frame
	InputManager.set_virtual_move(1, Vector2.ZERO)

	_ok(GameManager.objective_done() == 3,
		"all three dummies count: objective %d/%d" % [GameManager.objective_done(), GameManager.objective_total()])
	await _settle(4)
	_ok(GameManager.state == GameManager.State.VICTORY,
		"3/3 completes the chapter: VICTORY (state %d)" % GameManager.state)
	_ok(robot_travel > 1.5, "the companion moves (%.1f m from where it started)" % robot_travel)
	var robot_presses: int = int(ai.get("presses")) if ai else -1
	print("  -- the child pressed attack %d times, the robot %d" % [_human_presses, robot_presses])
	_ok(robot_presses >= 0 and robot_presses <= _human_presses / 3 + 2,
		"the companion keeps to about a third of the child's attacks (%d vs %d)"
			% [robot_presses, _human_presses])


func _check_play_again() -> void:
	var before := LevelBase.current(get_tree())
	GameManager.start_game()   # VICTORY -> PLAYING, the PLAY AGAIN path
	await _settle(10)
	var after := LevelBase.current(get_tree())
	_ok(before != null and after == before, "PLAY AGAIN on the same chapter reuses the level")
	_ok(GameManager.objective_done() == 0 and GameManager.objective_total() == 3,
		"...and begin() resets the objective (%d/%d)"
			% [GameManager.objective_done(), GameManager.objective_total()])
	_ok(get_tree().get_nodes_in_group("targets").size() == 3, "...and the dummies stand again")


# --- Ajudas: never fail -------------------------------------------------------------

func _check_never_defeat() -> void:
	var a := _hero(1)
	var b := _hero(2)
	await _settle(int(2.0 * TICK))   # out of any spawn i-frames
	GameManager.damage_player(1, GameManager.MAX_PLAYER_HEALTH)
	GameManager.damage_player(2, GameManager.MAX_PLAYER_HEALTH)
	await _settle(2)
	_ok(GameManager.state == GameManager.State.PLAYING,
		"both heroes at zero does NOT end the run with Ajudas on (state %d)" % GameManager.state)
	_ok(a.is_bubbled() and b.is_bubbled(), "both heroes float in bubbles")
	await _settle(int((PlayerBase.BUBBLE_TIME + 0.4) * TICK))
	_ok(not a.is_downed() and not b.is_downed(), "both bubbles pop after %.1f s" % PlayerBase.BUBBLE_TIME)
	_ok(int(GameManager.player_health[1]) == GameManager.MAX_PLAYER_HEALTH
		and int(GameManager.player_health[2]) == GameManager.MAX_PLAYER_HEALTH,
		"...back at FULL health (%d / %d)" % [GameManager.player_health[1], GameManager.player_health[2]])

	# Halved damage.
	await _settle(int((a.invuln_time + 0.2) * TICK))
	var hp0 := int(GameManager.player_health[1])
	a.take_hit(20, Vector3.ZERO)
	var hp1 := int(GameManager.player_health[1])
	_ok(hp0 - hp1 == 10, "a 20-damage hit costs 10 with Ajudas on (%d -> %d)" % [hp0, hp1])

	# Regeneration after REGEN_DELAY without a hit.
	await _settle(int((PlayerBase.REGEN_DELAY + 0.8) * TICK))
	var hp2 := int(GameManager.player_health[1])
	_ok(hp2 > hp1, "health regenerates after %.0f s untouched (%d -> %d)" % [PlayerBase.REGEN_DELAY, hp1, hp2])

	# Falling out of the level: bubble, no penalty, back beside the partner.
	var level := LevelBase.current(get_tree())
	await _settle(int(1.0 * TICK))
	var hp_before := int(GameManager.player_health[1])
	a.global_position = Vector3(0.0, level.kill_y() - 1.0, 30.0)
	a.velocity = Vector3(0.0, -5.0, 0.0)
	await _settle(3)
	_ok(a.is_bubbled(), "falling below kill_y() bubbles the hero")
	_ok(int(GameManager.player_health[1]) >= hp_before,
		"...with no fall penalty (%d -> %d)" % [hp_before, int(GameManager.player_health[1])])
	await _settle(int((PlayerBase.BUBBLE_TIME + 1.0) * TICK))
	_ok(not a.is_downed() and a.global_position.y > -1.0,
		"...and pops back on the ground (y %.2f)" % a.global_position.y)
	var apart := _flat(a.global_position - b.global_position).length()
	_ok(apart < 8.0, "...next to the partner (%.1f m)" % apart)
	_ok(int(GameManager.player_health[1]) == GameManager.MAX_PLAYER_HEALTH,
		"...at full health (%d)" % int(GameManager.player_health[1]))


## No trip through MENU: PLAY AGAIN after a chapter switch goes straight from
## one run to the next, and only _build_world's chapter comparison stops it
## reusing the sandbox.
func _check_back_to_bridge() -> void:
	GameManager.set_chapter("adamastor")
	GameManager.start_game()
	await _settle(10)
	_ok(LevelBase.current(get_tree()) == null, "chapter 'adamastor' has no LevelBase")
	_ok(get_tree().get_first_node_in_group("boss") != null, "...and Adamastor is back on the bridge")
	_ok(_main.get_node_or_null("World/Props") != null, "...with the bridge props")


# --- Harness ---------------------------------------------------------------------

func _start(chapter: String, count: int, hero: int) -> void:
	if _main == null:
		_main = MainScene.instantiate()
		add_child(_main)
		await _settle(4)
	GameManager.set_chapter(chapter)
	GameManager.set_player_count(count)
	GameManager.set_human_hero(hero)
	GameManager.start_game()
	await _settle(8)


func _nearest_target(from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("targets"):
		var d := _flat((n as Node3D).global_position - from).length()
		if d < best_d:
			best = n
			best_d = d
	return best


func _to_pad(world: Vector3) -> Vector2:
	var cam := get_viewport().get_camera_3d()
	var fwd := Vector3.FORWARD
	if cam:
		fwd = -cam.global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	return Vector2(world.dot(right), world.dot(fwd)).limit_length(1.0)


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


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
