extends Node
## Stadium chapter probe: "O Tesouro do Dragão" played from kick-off to VICTORY.
##
##   godot --headless --path . scripts/levels/dragao/_dragao_probe.tscn
##
## Boots main.tscn on chapter "dragao", solo with the companion and Ajudas on,
## and plays the whole level driving hero 1 ONLY through InputManager's virtual
## channel. The level's place_hero_near() skips the walking between objectives,
## but every objective step is a real hit (jab swing -> Hurtbox -> take_hit, or
## a kicked football) or a real pickup (walking onto a dropped cup):
##
##   * the world: level scene, 4 stakes and 6 goblins in "targets", 6 balls,
##     objective 0/4 "Free the dragon!", heroes at their spawn points;
##   * budget: MeshInstance3D count and a draw-call estimate for the level, at
##     kick-off and at the busiest moment (stage 2), and the build time;
##   * stage 1: three jabs snap each stake, 4/4, the dragon stands and roars;
##   * stage 2: objective 0/6 "Win back the cups!", story beat d10; a football
##     kicked into a carrier bowls it over (PUMBA); carriers knocked down drop
##     their cups, the hero walks onto each one, it flies to the cabinet;
##   * finale: 6/6 sends the goblins to the van, the dragon fires, VICTORY
##     within the frame budget; never DEFEAT; no engine or script errors;
##   * PLAY AGAIN resets the level.
##
## Exit code is the verdict.

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const TICK := 90.0
const FRAME_BUDGET := int(300.0 * TICK)
const MESH_BUDGET := 260
const DRAW_BUDGET := 250
## Generous against a shared CI box; the number itself is printed.
const BUILD_MS_LIMIT := 4000.0


## Counts engine and script errors raised while the probe runs.
class ErrorTap extends Logger:
	var lines: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var text := "%s:%d %s %s %s" % [file, line, function, code, rationale]
		# The machine has no speech synthesiser; that is the environment, not us.
		if text.contains("tts_") or text.contains("synth"):
			return
		lines.append(text)

	func _log_message(message: String, error: bool) -> void:
		if error and (message.contains("SCRIPT ERROR") or message.begins_with("ERROR")):
			lines.append(message)


var _pass: int = 0
var _fail: int = 0
var _main: Node = null
var _saw_defeat: bool = false
var _beats: Array[String] = []
var _frames: int = 0
var _tap := ErrorTap.new()
var _presses: int = 0


func _ready() -> void:
	OS.add_logger(_tap)
	await get_tree().process_frame
	GameManager.assists = true
	GameManager.companion = true
	GameManager.state_changed.connect(func(s: int) -> void:
		if s == GameManager.State.DEFEAT:
			_saw_defeat = true)
	GameManager.story_beat.connect(func(id: String) -> void: _beats.append(id))
	await _run()
	_ok(not _saw_defeat, "DEFEAT was never entered")
	_ok(_tap.lines.is_empty(), "no errors in the log (%d)%s" % [_tap.lines.size(),
		("\n      " + "\n      ".join(_tap.lines.slice(0, 6))) if not _tap.lines.is_empty() else ""])
	OS.remove_logger(_tap)
	print("\ndragao probe: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _run() -> void:
	_main = MainScene.instantiate()
	add_child(_main)
	await _settle(4)
	GameManager.set_chapter("dragao")
	GameManager.set_player_count(1)
	GameManager.set_human_hero(1)
	var t0 := Time.get_ticks_usec()
	GameManager.start_game()
	var build_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("  -- start_game (world + level build) took %.0f ms" % build_ms)
	_ok(build_ms < BUILD_MS_LIMIT, "the level builds in %.0f ms (< %.0f)" % [build_ms, BUILD_MS_LIMIT])
	await _settle(8)
	var level := LevelBase.current(get_tree())
	_ok(level != null and level.scene_file_path == "res://scenes/levels/dragao/dragao_level.tscn",
		"the dragao level is loaded")
	if level == null:
		return
	_check_world(level)
	_check_budget(level, "kick-off")
	await _stage_ropes(level)
	await _stage_cups(level)
	await _finale(level)
	await _play_again(level)


# --- World --------------------------------------------------------------------------

func _check_world(level) -> void:
	_ok(get_tree().get_first_node_in_group("boss") == null, "no Adamastor in the stadium")
	_ok(_hero(1) != null and _hero(2) != null and GameManager.is_ai(2), "both heroes, hero 2 is the companion")
	var gap := _hero(1).global_position.distance_to(level.spawn_point(1))
	_ok(gap < 1.5, "hero 1 starts at spawn_point(1) by the tunnel (%.2f m)" % gap)
	_ok(GameManager.objective_total() == 4 and GameManager.objective_done() == 0,
		"stage 1 objective 0/4 (got %d/%d)" % [GameManager.objective_done(), GameManager.objective_total()])
	_ok(str(GameManager.objective_label().get("en", "")) == "Free the dragon!", "label 'Free the dragon!'")
	var stakes := 0
	var goblins := 0
	var stake_script: Script = level.stakes[0].get_script()
	var goblin_script: Script = level.goblins[0].get_script()
	for t in get_tree().get_nodes_in_group("targets"):
		if t.get_script() == stake_script:
			stakes += 1
		elif t.get_script() == goblin_script:
			goblins += 1
	_ok(stakes == 4, "4 stakes in group 'targets' (%d)" % stakes)
	_ok(goblins == 6, "6 dancing goblins in group 'targets' (%d)" % goblins)
	_ok(level.balls.size() == 6, "6 footballs")
	_ok(level.dragon.is_tied(), "the dragon starts tied")
	_ok(level.hint_target().is_finite(), "hint_target points at a stake")


## MeshInstance3D count and an estimate of the level's draw calls: one per
## visible surface, plus one per shadow-casting surface per directional split.
func _check_budget(level, when: String) -> void:
	var meshes := 0
	var draws := 0
	var spawn := get_tree().get_first_node_in_group("spawn_root")
	for root in [level, spawn]:
		if root == null:
			continue
		for n in (root as Node).find_children("*", "GeometryInstance3D", true, false):
			if n is MeshInstance3D:
				meshes += 1
			var gi := n as GeometryInstance3D
			if not gi.is_visible_in_tree():
				continue
			var surfaces := 1
			if gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null:
				surfaces = maxi(1, (gi as MeshInstance3D).mesh.get_surface_count())
			draws += surfaces
			if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				draws += surfaces * 2
	print("  -- %s: %d MeshInstance3D in the level, ~%d draw calls" % [when, meshes, draws])
	_ok(meshes <= MESH_BUDGET, "%s: MeshInstance3D count %d <= %d" % [when, meshes, MESH_BUDGET])
	_ok(draws <= DRAW_BUDGET, "%s: estimated draw calls %d <= %d" % [when, draws, DRAW_BUDGET])


# --- Stage 1: the ropes -----------------------------------------------------------------

func _stage_ropes(level) -> void:
	var hero := _hero(1)
	var robot := _hero(2)
	var robot_start := robot.global_position
	# One goblin first: two jabs, dizzy, and a pterodactyl carries it away.
	var gob = level.goblins[0]
	await _jab_goblin(level, hero, gob)
	await _settle(int(0.9 * TICK))
	await _jab_goblin(level, hero, gob)
	var w := 0
	while level.goblins_carried == 0 and w < int(8.0 * TICK):
		await _step()
		w += 1
	_ok(gob.hits >= 2 and level.goblins_carried >= 1,
		"a goblin bowled over twice is carried off by a pterodactyl (%.1f s, hits %d)" % [float(w) / TICK, gob.hits])
	_ok(not gob.is_active() and not gob.is_hittable(), "...and it has left the pitch and the 'targets' group")
	var snapped := 0
	for stake in level.stakes:
		if stake.is_done():
			snapped += 1
			continue
		level.place_hero_near(hero, stake.position, 1.4)
		var waited := 0
		while not stake.is_done() and waited < int(25.0 * TICK):
			# Re-plant if a goblin's poke shoved us off.
			if _flat(hero.global_position - stake.global_position).length() > 2.6:
				level.place_hero_near(hero, stake.position, 1.4)
			hero.face_toward(stake.global_position)
			if waited % 40 == 0:
				InputManager.press_virtual(1, &"attack")
				_presses += 1
			await _step()
			waited += 1
		if stake.is_done():
			snapped += 1
		_ok(stake.is_done(), "%s snaps after three hits (%d hits)" % [stake.name, stake.hits])
	_ok(GameManager.objective_done() == 4, "all four ropes: objective %d/4" % GameManager.objective_done())
	# The dragon stands up, roars; stage 2 follows.
	var waited2 := 0
	while level.stage != level.Stage.CUPS and waited2 < int(12.0 * TICK):
		await _step()
		waited2 += 1
	_ok(not level.dragon.is_tied(), "the freed dragon stands up")
	_ok(level.stage == level.Stage.CUPS, "stage 2 starts after the roar (%.1f s)" % (float(waited2) / TICK))
	_ok(_flat(robot.global_position - robot_start).length() > 1.5, "the companion moved during stage 1")


# --- Stage 2: the cups --------------------------------------------------------------------

func _stage_cups(level) -> void:
	_ok(GameManager.objective_total() == 6 and GameManager.objective_done() == 0,
		"stage 2 objective 0/6 (got %d/%d)" % [GameManager.objective_done(), GameManager.objective_total()])
	_ok(str(GameManager.objective_label().get("en", "")) == "Win back the cups!", "label 'Win back the cups!'")
	_ok("d10" in _beats, "story beat d10 was requested")
	await _settle(int(2.0 * TICK))   # the carriers run out of the van
	var carriers := 0
	for g in level.goblins:
		if g.carrying != null:
			carriers += 1
	_ok(carriers == 6, "six goblins carry a cup each (%d)" % carriers)
	_check_budget(level, "stage 2")

	var hero := _hero(1)
	# A football first: PUMBA.
	await _kick_ball_at_carrier(level, hero)
	_ok(level.ball_knockdowns >= 1, "a kicked football bowls a carrier over (%d)" % level.ball_knockdowns)

	var guard := 0
	while GameManager.objective_done() < 6 and guard < int(150.0 * TICK):
		var cup = _nearest_loose_cup(level, hero.global_position)
		if cup != null:
			await _walk_to_cup(level, hero, cup)
		else:
			var g = level.nearest_carrier(hero.global_position)
			if g == null:
				await _step()
				guard += 1
				continue
			await _jab_goblin(level, hero, g)
		guard += 1
	_ok(GameManager.objective_done() == 6, "all six cups won back: %d/6" % GameManager.objective_done())


func _kick_ball_at_carrier(level, hero: PlayerBase) -> void:
	for attempt in 3:
		var g = level.nearest_carrier(hero.global_position)
		var ball = level.balls[attempt]
		if g == null:
			return
		var gp: Vector3 = g.global_position
		var dir := _flat(gp - level.dragon.position)
		dir = dir.normalized() if dir.length() > 0.5 else Vector3.RIGHT
		# Ball 1.4 m short of the goblin, hero behind the ball, all in a line.
		var ball_at: Vector3 = gp - dir * 1.4 + Vector3.UP * 0.3
		ball.reset_ball()
		ball.global_position = ball_at
		level.place_hero_near(hero, ball_at - Vector3.UP * 0.3, 1.1, -dir)
		hero.face_toward(gp)
		InputManager.press_virtual(1, &"attack")
		_presses += 1
		var before: int = level.ball_knockdowns
		for i in int(1.5 * TICK):
			await _step()
			if level.ball_knockdowns > before:
				return


func _jab_goblin(level, hero: PlayerBase, g: Node) -> void:
	var hits_before: int = g.hits
	level.place_hero_near(hero, g.global_position, 1.3, hero.global_position - g.global_position)
	for i in int(1.2 * TICK):
		hero.face_toward(g.global_position)
		if i % 30 == 0:
			if _flat(hero.global_position - g.global_position).length() > 2.4:
				level.place_hero_near(hero, g.global_position, 1.3, hero.global_position - g.global_position)
			InputManager.press_virtual(1, &"attack")
			_presses += 1
		await _step()
		if g.hits > hits_before:
			return


func _walk_to_cup(level, hero: PlayerBase, cup: Node) -> void:
	var done_before := GameManager.objective_done()
	if _flat(hero.global_position - cup.global_position).length() > 4.0:
		level.place_hero_near(hero, cup.global_position, 3.0, hero.global_position - cup.global_position)
	for i in int(6.0 * TICK):
		if GameManager.objective_done() > done_before or not cup.is_loose():
			break
		var to := _flat(cup.global_position - hero.global_position)
		InputManager.set_virtual_move(1, _to_pad(to.normalized()) if to.length() > 0.3 else Vector2.ZERO)
		await _step()
	InputManager.set_virtual_move(1, Vector2.ZERO)


func _nearest_loose_cup(level, from: Vector3) -> Node:
	var best: Node = null
	var best_d := INF
	for c in level.cups:
		if c.is_loose():
			var d := _flat(c.global_position - from).length()
			if d < best_d:
				best_d = d
				best = c
	return best


# --- Finale -------------------------------------------------------------------------------

func _finale(level) -> void:
	var waited := 0
	while GameManager.state == GameManager.State.PLAYING and waited < int(30.0 * TICK):
		await _step()
		waited += 1
	_ok(level.stage == level.Stage.FINALE, "6/6 starts the finale")
	_ok(level.dragon.has_fired(), "the dragon puffed fire at the van")
	_ok(level.van.sooty, "the van is sooty")
	_ok(GameManager.state == GameManager.State.VICTORY,
		"VICTORY %.1f s after the last cup (state %d)" % [float(waited) / TICK, GameManager.state])
	_ok(_frames < FRAME_BUDGET, "won within the frame budget (%d frames = %.0f s simulated)" % [_frames, float(_frames) / TICK])
	var ai: Node = _main.get_node_or_null("World/CompanionAI2")
	print("  -- hero 1 pressed attack %d times, the companion %d" % [_presses, int(ai.get("presses")) if ai else -1])


func _play_again(level) -> void:
	GameManager.start_game()
	await _settle(10)
	_ok(LevelBase.current(get_tree()) == level, "PLAY AGAIN reuses the stadium")
	_ok(GameManager.objective_done() == 0 and GameManager.objective_total() == 4,
		"...back to 0/4 (%d/%d)" % [GameManager.objective_done(), GameManager.objective_total()])
	var stakes_up := 0
	for s in level.stakes:
		if not s.is_done():
			stakes_up += 1
	_ok(stakes_up == 4 and level.dragon.is_tied(), "...the dragon is tied to four fresh stakes")
	var shelved := 0
	for c in level.cups:
		if c.is_shelved():
			shelved += 1
	_ok(shelved == 0 and not level.van.sooty, "...the cabinet is empty and the van clean again")


# --- Harness ----------------------------------------------------------------------------

func _step() -> void:
	await get_tree().physics_frame
	_frames += 1


func _settle(frames: int) -> void:
	for i in frames:
		await _step()


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
