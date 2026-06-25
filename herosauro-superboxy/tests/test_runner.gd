extends SceneTree
## Headless test + smoke harness for "Herosauro & Super Boxy: Legends of Porto".
##
## Run from the project dir:
##   godot --headless --script res://tests/test_runner.gd
##
## Exits 0 if every check passes, 1 otherwise, so CI can gate on it.
##
## Two layers of coverage, both safe to run without a display:
##   1. Compile gate  - load() every .gd in scripts/ + autoloads/ + tests/, which
##      (via their preloads) also pulls in every scene/material/shader they touch.
##      A parse error anywhere fails the run. Broad, cheap regression net.
##   2. Logic tests   - exercise GameManager's score/combo/phase/win-loss rules on a
##      fresh instance (no reliance on the autoload singleton).
##
## Deliberately no scene instantiation yet (that needs the autoload graph + a
## rendering server); the compile gate already catches parse breakage in those.
## A GUT/GdUnit4 migration can layer on top of this without changing the CI shape.

var _checks: int = 0
var _failures: int = 0
var _ran: bool = false


# Run on the first processed frame rather than in _initialize(): by then the
# SceneTree root is fully wired, so nodes we add are genuinely in-tree and their
# get_tree() calls (e.g. GameManager.change_state -> get_tree().paused) resolve
# cleanly instead of erroring against a null tree.
func _initialize() -> void:
	process_frame.connect(_run)


func _run() -> void:
	if _ran:
		return
	_ran = true
	print("== headless test run ==")
	_test_all_scripts_compile()
	_test_game_manager_logic()
	print("\n%d checks, %d failure(s)." % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- tiny assert helpers ---------------------------------------------------

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("  ok   - %s" % msg)
	else:
		_failures += 1
		printerr("  FAIL - %s" % msg)


func _eq(actual, expected, msg: String) -> void:
	_check(actual == expected, "%s (expected %s, got %s)" % [msg, str(expected), str(actual)])


# --- 1. compile gate -------------------------------------------------------

func _test_all_scripts_compile() -> void:
	print("\n[scripts compile]")
	var paths: Array = []
	_gather_gd("res://scripts", paths)
	_gather_gd("res://autoloads", paths)
	_gather_gd("res://tests", paths)
	paths.sort()
	for p in paths:
		_check(load(p) is GDScript, "loads: %s" % p)


func _gather_gd(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		var full := "%s/%s" % [dir_path, fname]
		if d.current_is_dir():
			if not fname.begins_with("."):
				_gather_gd(full, out)
		elif fname.ends_with(".gd"):
			out.append(full)
		fname = d.get_next()
	d.list_dir_end()


# --- 2. GameManager logic --------------------------------------------------

func _test_game_manager_logic() -> void:
	print("\n[GameManager logic]")
	var GM: GDScript = load("res://autoloads/game_manager.gd")
	if GM == null:
		_check(false, "could not load game_manager.gd")
		return

	var gm: Node = GM.new()
	get_root().add_child(gm)   # needs to be in the tree for get_tree() calls
	# Guard: if this is false, change_state()'s get_tree() would error against a
	# null tree and spam the log — keep the gate's output trustworthy.
	_check(gm.is_inside_tree(), "GameManager test instance is in-tree")

	# start_game() resets the session.
	gm.start_game()
	_eq(gm.state, GM.State.PLAYING, "start_game -> PLAYING")
	_eq(gm.boss_health, GM.MAX_BOSS_HEALTH, "boss starts at full health")
	_eq(gm.score, 0, "score starts at 0")
	_eq(gm.boss_phase, 1, "boss starts in phase 1")

	# A P1 hit deals damage and awards flat score (no combo for P1).
	gm.damage_boss(50, 1)
	_eq(gm.boss_health, GM.MAX_BOSS_HEALTH - 50, "P1 hit reduces boss health")
	_eq(gm.score, GM.SCORE_PER_HIT, "P1 hit awards flat score")

	# P2 hits build a combo that scales score (hit n -> SCORE_PER_HIT * n).
	var before: int = gm.score
	gm.damage_boss(10, 2)   # combo 1 -> +SCORE_PER_HIT
	gm.damage_boss(10, 2)   # combo 2 -> +SCORE_PER_HIT*2
	_eq(gm.p2_combo, 2, "P2 combo increments per hit")
	_eq(gm.score, before + GM.SCORE_PER_HIT * 3, "P2 combo scales score")

	# Crossing 50% boss health flips to phase 2.
	gm.damage_boss(200, 1)  # ~430 -> ~230, below half of 500
	_check(gm.boss_health <= GM.MAX_BOSS_HEALTH / 2, "boss is below half health")
	_eq(gm.boss_phase, 2, "crossing 50% -> phase 2")

	# Overkill floors health at 0 and triggers victory.
	gm.damage_boss(GM.MAX_BOSS_HEALTH, 1)
	_eq(gm.boss_health, 0, "boss health floors at 0")
	_eq(gm.state, GM.State.VICTORY, "boss death -> VICTORY")

	# Defeat path: the game only ends when BOTH heroes are down.
	gm.start_game()
	gm.damage_player(1, GM.MAX_PLAYER_HEALTH)
	_eq(gm.state, GM.State.PLAYING, "one hero down is not a defeat")
	gm.damage_player(2, GM.MAX_PLAYER_HEALTH)
	_eq(gm.state, GM.State.DEFEAT, "both heroes down -> DEFEAT")

	# Difficulty scalar ordering: EASY < NORMAL(1.0) < HARD.
	gm.set_difficulty(GM.Difficulty.EASY)
	_check(gm.difficulty_scalar() < 1.0, "EASY scalar < 1.0")
	gm.set_difficulty(GM.Difficulty.HARD)
	_check(gm.difficulty_scalar() > 1.0, "HARD scalar > 1.0")

	gm.queue_free()
