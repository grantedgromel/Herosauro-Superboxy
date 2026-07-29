extends SceneTree
## Proves the input seam end to end: that a hero driven by something other than
## a human keyboard moves, jumps and attacks exactly as one driven by a human.
##
## This is the claim the whole arrangement rests on. If an AgentInput can drive
## a PlayerBase, then an AI ally is a roster entry rather than a second
## implementation of locomotion — which is what the deleted AllyController was,
## and why removing co-op meant deleting a class. A green run here is what makes
## "co-op is a config change" true rather than aspirational.
##
## Run:
##   godot --headless --script res://scripts/players/_input_seam_probe.gd --path .

const MAX_STEPS := 900
const DRIVE_STEPS := 45     ## physics frames to hold the stick for
const MIN_TRAVEL := 1.0     ## metres; well under what 45 frames at 8 m/s covers

var _steps: int = 0
var _started: bool = false
var _hero: Node = null   # typed Node, see _find_player
var _brain: AgentInput = null
var _phase: int = 0
var _drove: int = 0
var _from: Vector3
var _peak_rise: float = 0.0
var _fails: Array[String] = []


func _initialize() -> void:
	process_frame.connect(_tick)


func _tick() -> void:
	_steps += 1
	if _steps == 2:
		change_scene_to_file("res://scenes/main.tscn")
		return
	if _steps < 3:
		return

	if not _started:
		var menu := root.find_child("MainMenu", true, false)
		if menu == null or not menu.has_method("_on_activated"):
			if _steps > MAX_STEPS:
				_fail("MainMenu never appeared")
				_report()
			return
		menu.call("_on_activated", &"start")
		_started = true
		return

	if _hero == null:
		_hero = _find_player(root)
		if _hero == null:
			if _steps > MAX_STEPS:
				_fail("no hero spawned")
				_report()
			return
		# The roster hands every hero a DeviceInput; swapping it for an
		# AgentInput is the entire integration surface an AI ally would need.
		_check("roster gave the hero a DeviceInput",
				_hero.input is DeviceInput, str(_hero.input))
		_brain = AgentInput.new()
		_hero.input = _brain
		return

	match _phase:
		0:
			# Let him land before measuring: he spawns 2 m up and a fall would
			# be counted as travel.
			if _hero.is_on_floor():
				_from = _hero.global_position as Vector3
				_phase = 1
			elif _steps > MAX_STEPS:
				_fail("hero never landed")
				_report()
		1:
			# Full stick forward. PlayerBase rotates this through the camera
			# yaw, so the direction is whatever "away from camera" is — only the
			# distance covered matters here.
			_brain.move = Vector2(0.0, 1.0)
			_drove += 1
			if _drove >= DRIVE_STEPS:
				# Explicit types throughout: _hero is a Node, so its members come back
				# untyped and := cannot infer from them.
				var here: Vector3 = _hero.global_position
				var travelled: float = here.distance_to(_from)
				_check("AgentInput.move drove the hero %.2f m (>= %.1f)"
						% [travelled, MIN_TRAVEL], travelled >= MIN_TRAVEL, "")
				_brain.move = Vector2.ZERO
				_phase = 2
		2:
			if not _hero.is_on_floor():
				return   # settle before testing the jump
			_brain.press_jump()
			_phase = 3
		3:
			var vel: Vector3 = _hero.velocity
			_peak_rise = maxf(_peak_rise, vel.y)
			if _drove < DRIVE_STEPS + 20:
				_drove += 1
				return
			_check("AgentInput.press_jump produced upward velocity (peak %.1f)"
					% _peak_rise, _peak_rise > 1.0, "")
			# Edges are consumed on read, so a second read in the same frame is
			# false by design. Verify that, because a controller that polls
			# twice would silently lose inputs.
			_brain.press_attack()
			var first := _brain.is_attack_just_pressed()
			var second := _brain.is_attack_just_pressed()
			_check("attack edge fires once then clears", first and not second, "")
			# An unsubclassed InputSource is the neutral one; a hero handed it
			# should be inert.
			var neutral := InputSource.new()
			_check("bare InputSource is neutral",
					neutral.get_move_vector() == Vector2.ZERO
					and not neutral.is_jump_held(), "")
			# The p2_ set does not exist yet: this must degrade, not throw.
			var p2 := DeviceInput.new("p2_")
			_check("unbound DeviceInput reports itself unbound and stays neutral",
					not p2.is_bound() and p2.get_move_vector() == Vector2.ZERO, "")
			_report()


func _check(what: String, ok: bool, detail: String) -> void:
	print("[seam] %s %s%s" % ["PASS" if ok else "FAIL", what,
			("  (%s)" % detail) if detail != "" and not ok else ""])
	if not ok:
		_fails.append(what)


func _fail(what: String) -> void:
	print("[seam] FAIL %s" % what)
	_fails.append(what)


func _report() -> void:
	if _fails.is_empty():
		print("[seam] ALL PASS")
	else:
		print("[seam] %d FAILURE(S)" % _fails.size())
	quit()


## Deliberately returns Node, and matches on the group rather than on the
## PlayerBase type. Naming PlayerBase here compiles it — and everything it
## depends on — while this probe is being parsed, which is before the autoloads
## are registered, so GameManager fails to resolve and the hero's _ready never
## runs. The symptom is a hero that spawns and then never lands.
func _find_player(node: Node) -> Node:
	if node.is_in_group("players"):
		return node
	for c in node.get_children():
		var found := _find_player(c)
		if found != null:
			return found
	return null
