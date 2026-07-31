extends Node
## Headless gameplay harness — drives a real match so the review loop exercises
## the player controllers, camera, physics and boss, not just static scenery.
##
## This EXITS NON-ZERO when the fight does not function, because CI gates on it.
## The previous version only printed warnings for a human to read, and once co-op
## landed every one of them was a false negative:
##
##   * it drove slot 1 only, so hero 2 never moved and never attacked;
##   * `_start_pos` was captured from hero 1 while `_last_pos` was overwritten by
##     whichever hero came last in the group, so "travelled" compared one hero's
##     start against the other's end and reported nonsense;
##   * `_finish` read `player_health[1]` and ignored the rest of the roster;
##   * and each attack beat HELD the action for its whole duration. Attacks fire
##     on `just_pressed`, so a 45-frame hold is exactly one swing. A run that
##     looked like six attacks was testing two.
##
## The last one mattered most: it made "boss took no damage" fire on a build where
## every attack does in fact land — the worst failure mode a gate has, because it
## trains people to ignore it.
##
## RUNS HEADLESS BY DEFAULT, and that is what makes it usable as a gate. What this
## harness proves — that the boss takes damage, that both heroes move, that nobody
## falls through the deck — is SIMULATION, not rendering. Rendering it on software
## Vulkan cost 4.8 seconds per frame in CI: the first 60-frame beat took four
## minutes fifty, and the full route would have needed about eighty minutes against
## a fifteen-minute timeout. Headless, the same route is seconds, because physics
## and scripts run either way and only the frame does not.
##
## Screenshots therefore only happen when there is a display to draw into. Pass
## --shots to force them on for a human looking at a run locally.
##
## Usage:
##   godot --headless --path . tools/playtest.tscn --fixed-fps 60 -- --out=/abs/dir
##   VK_ICD_FILENAMES=... xvfb-run -a godot --path . tools/playtest.tscn \
##       --rendering-driver vulkan --fixed-fps 60 -- --out=/abs/dir --shots

const MainScene: PackedScene = preload("res://scenes/main.tscn")

## Scripted beats: [label, action, frames_to_hold, pulse].
##
## Movement is CAMERA-RELATIVE, so `move_up` is "forward, wherever the camera is
## pointing", not +X. An early version drove move_left/move_right expecting world
## axes and simply pinned the hero against a parapet for 300 frames without ever
## traversing the bridge. Forward is the only direction that reliably makes
## progress without steering.
##
## `pulse` = tap the action once per PULSE_PERIOD frames instead of holding it.
## Required for anything read with `is_action_just_pressed`.
const ROUTE: Array = [
	["spawn", "", 60, false],
	["approach", "move_up", 240, false],
	["attack_1", "attack", 90, true],
	["settle_1", "", 30, false],
	["special", "ability", 60, true],
	["settle_2", "", 40, false],
	["close", "move_up", 150, false],
	["attack_2", "attack", 90, true],
	["jump", "jump", 24, true],
	["settle_3", "", 60, false],
	["back_off", "move_down", 150, false],
	["final", "", 40, false],
]

## Frames between taps of a pulsed action. 12 at 60 fps is a tap every 200 ms —
## comfortably slower than the fastest attack cooldown in the game (Boxy's jab at
## 0.38 s), so no tap is swallowed by cooldown and each one is a real swing.
const PULSE_PERIOD := 12
const PULSE_HOLD := 3

var _out_dir: String = "/tmp/playtest"
var _step: int = 0
var _held: int = 0
var _held_action: String = ""
var _started: bool = false
var _failures: Array[String] = []

## Per hero, keyed by player id, so nothing ever compares one hero against another.
var _start_pos: Dictionary = {}
var _last_pos: Dictionary = {}
var _min_y: Dictionary = {}
var _boss_start_health: int = 0
## Screenshots need a real display. Under --headless the viewport texture is not
## drawable, so asking for its image is both meaningless and, on some drivers, a
## crash. Default off when headless, on otherwise, and --shots overrides.
var _shots: bool = false


func _ready() -> void:
	seed(1881)
	_shots = DisplayServer.get_name() != "headless"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.substr(6)
		elif arg == "--shots":
			_shots = true
		elif arg == "--no-shots":
			_shots = false
	if _shots:
		DirAccess.make_dir_recursive_absolute(_out_dir)
	add_child(MainScene.instantiate())
	print("playtest: renderer=", RenderingServer.get_video_adapter_name())

	await get_tree().process_frame
	var gm := get_node_or_null("/root/GameManager")
	if gm == null:
		_fail("GameManager autoload missing")
		_finish()
		return
	gm.start_game()
	_started = true
	_boss_start_health = int(gm.boss_health)
	print("playtest: match started, roster=", _slots())


func _physics_process(_delta: float) -> void:
	if not _started:
		return
	if _step >= ROUTE.size():
		_finish()
		return

	_track_players()

	var beat: Array = ROUTE[_step]
	var action := String(beat[1])
	var hold := int(beat[2])
	var pulse: bool = beat[3]

	if action != "":
		if pulse:
			_pulse(action)
		elif _held == 0:
			_press(action)

	_held += 1
	if _held >= hold:
		_release()
		_shoot(String(beat[0]))
		_step += 1
		_held = 0


# --- Input -------------------------------------------------------------------
#
# Every action is driven for EVERY active hero, so co-op actually exercises both
# controllers rather than leaving hero 2 standing still for the whole run.

func _slots() -> Array:
	var gm := get_node_or_null("/root/GameManager")
	if gm and gm.has_method("active_player_ids"):
		return gm.active_player_ids()
	return [1]


## Resolve the per-slot action names. InputManager owns the spelling; asking it
## rather than formatting a prefix here keeps this harness from hard-coding a
## naming scheme that can drift out from under it.
func _actions_for(action: String) -> Array[String]:
	var out: Array[String] = []
	var im := get_node_or_null("/root/InputManager")
	for slot in _slots():
		var resolved := action
		if im and im.has_method("action_name"):
			resolved = String(im.action_name(slot, action))
		if InputMap.has_action(resolved) and not out.has(resolved):
			out.append(resolved)
	if out.is_empty() and InputMap.has_action(action):
		out.append(action)   # pre-co-op single action set
	if out.is_empty():
		_fail("no input action resolves for '%s'" % action)
	return out


func _press(action: String) -> void:
	for name in _actions_for(action):
		Input.action_press(name)
	_held_action = action


func _release() -> void:
	if _held_action == "":
		return
	for name in _actions_for(_held_action):
		Input.action_release(name)
	_held_action = ""


## Tap rather than hold. Attacks and jumps are read with `is_action_just_pressed`,
## so holding for a whole beat produces exactly one of them.
func _pulse(action: String) -> void:
	var phase := _held % PULSE_PERIOD
	if phase == 0:
		_press(action)
	elif phase == PULSE_HOLD:
		_release()


# --- Observation -------------------------------------------------------------

func _track_players() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		var node := p as Node3D
		if node == null:
			continue
		var pid := 1
		if "player_id" in p:
			pid = int(p.player_id)
		var pos := node.global_position
		if not _start_pos.has(pid):
			_start_pos[pid] = pos
			_min_y[pid] = pos.y
		_last_pos[pid] = pos
		_min_y[pid] = minf(float(_min_y[pid]), pos.y)


func _shoot(label: String) -> void:
	if _shots:
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%02d_%s.png" % [_out_dir, _step, label])
	var where := ""
	for pid in _last_pos.keys():
		where += " p%d=%s" % [pid, str((_last_pos[pid] as Vector3).round())]
	print("beat: ", label, where)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	set_physics_process(false)
	var gm := get_node_or_null("/root/GameManager")

	# The point of the run: did the fight actually function? Health moving in
	# both directions is the difference between "it rendered" and "it played".
	if gm:
		var dealt := _boss_start_health - int(gm.boss_health)
		print("playtest: boss %d -> %d (dealt %d)" % [_boss_start_health, gm.boss_health, dealt])
		if dealt <= 0:
			_fail("boss took no damage across the whole route — no attack connects")
		for pid in _slots():
			var combo = gm.combo_for(pid) if gm.has_method("combo_for") else "?"
			print("playtest: hero %d health %s, combo %s"
					% [pid, gm.player_health.get(pid, "?"), combo])
		print("playtest: score %s   state %s" % [gm.score, gm.state])

	if _start_pos.is_empty():
		_fail("no hero ever appeared in the 'players' group")

	for pid in _start_pos.keys():
		var a: Vector3 = _start_pos[pid]
		var b: Vector3 = _last_pos[pid]
		print("playtest: hero %d travelled %.1f m (x %.1f -> %.1f, z %.1f -> %.1f), lowest y %.1f"
				% [pid, a.distance_to(b), a.x, b.x, a.z, b.z, _min_y[pid]])
		if a.distance_to(b) < 5.0:
			_fail("hero %d barely moved — stuck, or input is not reaching its controller" % pid)
		if float(_min_y[pid]) < -4.0:
			_fail("hero %d fell below the deck — possible clipping" % pid)

	for f in _failures:
		print("playtest: FAIL ", f)
	print("playtest: %s" % ("PASS" if _failures.is_empty() else "FAILED"))
	get_tree().quit(0 if _failures.is_empty() else 1)
