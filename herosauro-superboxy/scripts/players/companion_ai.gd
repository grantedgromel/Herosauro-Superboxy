class_name CompanionAI
extends Node
## The robot brother: drives the hero nobody at the machine is playing
## (`GameManager.is_ai`), so a child alone still plays with their sibling.
##
## main.gd adds one of these per AI hero, beside the heroes under World. It
## touches its hero ONLY through InputManager's virtual channel
## (`set_virtual_move` / `press_virtual`), exactly like a pair of hands would, so
## every rule the hero obeys (cooldowns, i-frames, auto-aim, the leash) applies
## to it unchanged. The two exceptions are reads: it asks the hero whether its
## power is ready, and when it has strayed or fallen it asks the hero to
## bubble home (`PlayerBase.bubble_home`).
##
## What it does, re-decided every THINK_INTERVAL:
##   * FOLLOW: stays FOLLOW_MIN..FOLLOW_MAX from the human, a little behind them
##     (relative to the camera) and to one side.
##   * ENGAGE: the nearest "targets"/"boss" node within ENGAGE_RADIUS of the
##     human; walks up to it and jabs, or uses the power from POWER_MIN..POWER_MAX
##     when the hero's ability is ready.
##   * Jumps a beat after the human jumps, and when it is stuck against
##     something.
##
## It must be fun to have around and never steal every kill, so it may only
## attack with a token, and tokens are earned at HIT_SHARE per attack or power
## the HUMAN starts: roughly a third of the human's hit rate, never more, and
## nothing at all while the child just watches.
##
## Deterministic: one seeded RNG, every timer accumulated from delta.

@export var player_id: int = 2

const THINK_INTERVAL := 0.2
const FOLLOW_MIN := 2.5
const FOLLOW_MAX := 6.0
const FOLLOW_BEHIND := 3.0
const FOLLOW_SIDE := 1.6
## Close enough to the follow point to stop walking.
const FOLLOW_SLACK := 1.0
const ENGAGE_RADIUS := 9.0
const POWER_MIN := 3.0
const POWER_MAX := 12.0
const STRAY_LIMIT := 16.0
## Airborne this long and this far below the human = fallen.
const FALL_TIME := 0.6
const FALL_DROP := 5.0
const STUCK_TIME := 0.6
const STUCK_SPEED := 0.6
const JUMP_ECHO_DELAY := 0.15
const HIT_SHARE := 1.0 / 3.0
const TOKEN_CAP := 2.0
## Seconds between its own presses, plus up to ATTACK_JITTER of seeded jitter.
const ATTACK_SPACING := 0.55
const ATTACK_JITTER := 0.3
const POWER_SPACING := 1.2
const RNG_SEED := 0xB0B0

var _rng := RandomNumberGenerator.new()
var _hero: PlayerBase = null
var _human: PlayerBase = null
var _target: Node3D = null
var _think: float = 0.0
var _tokens: float = 0.0
var _press_gap: float = 0.0
var _stuck: float = 0.0
var _airborne: float = 0.0
var _jump_echo: float = -1.0
var _human_was_on_floor: bool = true
var _side: float = 1.0
## Read by probes: how many attacks/powers it has started this run.
var presses: int = 0


func _ready() -> void:
	# After InputManager promotes last frame's presses (-1000), before any hero
	# reads its input (0), so a move set here is seen this very tick.
	process_physics_priority = -500
	GameManager.game_started.connect(_reset)
	_reset()


func _exit_tree() -> void:
	InputManager.set_virtual_move(player_id, Vector2.ZERO)


func _reset() -> void:
	_rng.seed = RNG_SEED + player_id
	_side = 1.0 if _rng.randf() < 0.5 else -1.0
	_target = null
	_think = 0.0
	_tokens = 0.0
	_press_gap = 0.0
	_stuck = 0.0
	_airborne = 0.0
	_jump_echo = -1.0
	_human_was_on_floor = true
	presses = 0
	_hero = null
	_human = null
	InputManager.set_virtual_move(player_id, Vector2.ZERO)


func _physics_process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		InputManager.set_virtual_move(player_id, Vector2.ZERO)
		return
	if not _resolve():
		InputManager.set_virtual_move(player_id, Vector2.ZERO)
		return

	_count_human_presses()
	_press_gap = maxf(0.0, _press_gap - delta)

	if _hero.is_downed():
		InputManager.set_virtual_move(player_id, Vector2.ZERO)
		return

	# Strayed or fell: float home rather than fight the leash or the void.
	var to_human := _flat(_human.global_position - _hero.global_position)
	_airborne = 0.0 if _hero.is_on_floor() else _airborne + delta
	var fell := _airborne > FALL_TIME \
		and _hero.global_position.y < _human.global_position.y - FALL_DROP
	if not _human.is_downed() and (to_human.length() > STRAY_LIMIT or fell):
		InputManager.set_virtual_move(player_id, Vector2.ZERO)
		_hero.bubble_home()
		return

	_think -= delta
	if _think <= 0.0:
		_think = THINK_INTERVAL
		_target = _pick_target()

	var want := Vector3.ZERO   # world-space, length = stick deflection
	if _target != null and is_instance_valid(_target) and _target.is_inside_tree():
		want = _engage()
	else:
		_target = null
		want = _follow(to_human)
	InputManager.set_virtual_move(player_id, _to_pad(want))

	_handle_jumps(delta, want)


# --- Decisions ---------------------------------------------------------------

## Nearest-to-me "targets" / "boss" node that is within ENGAGE_RADIUS of the
## human, so it fights what the child is fighting rather than wandering off.
func _pick_target() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for group in [&"targets", &"boss"]:
		for n in get_tree().get_nodes_in_group(group):
			var node := n as Node3D
			if node == null or not is_instance_valid(node):
				continue
			if _flat(node.global_position - _human.global_position).length() > ENGAGE_RADIUS:
				continue
			var d := _flat(node.global_position - _hero.global_position).length()
			if d < best_d:
				best = node
				best_d = d
	return best


func _follow(to_human: Vector3) -> Vector3:
	var d_h := to_human.length()
	if d_h < FOLLOW_MIN and d_h > 0.01:
		return -to_human / d_h * 0.6          # give the child some room
	var fwd := _camera_forward()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var spot := _human.global_position - fwd * FOLLOW_BEHIND + right * FOLLOW_SIDE * _side
	var to_spot := _flat(spot - _hero.global_position)
	var d := to_spot.length()
	if d < FOLLOW_SLACK:
		return Vector3.ZERO
	var speed := 1.0 if d_h > FOLLOW_MAX else clampf(d / 3.0, 0.35, 1.0)
	return to_spot / d * speed


func _engage() -> Vector3:
	var to_t := _flat(_target.global_position - _hero.global_position)
	var d := to_t.length()
	var dir := to_t / d if d > 0.01 else _hero.facing_dir
	var reach: float = _hero.attack_range

	# The power first: it is the exciting one, and it is what makes the robot
	# worth watching from across the arena.
	if d >= POWER_MIN and d <= POWER_MAX and _hero.get_ability_fraction() >= 1.0 \
			and _can_press():
		_spend(POWER_SPACING)
		InputManager.press_virtual(player_id, &"ability")
		return dir   # the stick on the target is what aims it
	if d <= reach + 0.2 and _can_press():
		_spend(ATTACK_SPACING + _rng.randf() * ATTACK_JITTER)
		InputManager.press_virtual(player_id, &"attack")
		return dir * 0.3
	if d > reach - 0.8:
		return dir
	return Vector3.ZERO


func _can_press() -> bool:
	return _tokens >= 1.0 and _press_gap <= 0.0


func _spend(gap: float) -> void:
	_tokens -= 1.0
	_press_gap = gap
	presses += 1


## Tokens: HIT_SHARE for every attack or power the human starts.
func _count_human_presses() -> void:
	var hid := _human.player_id
	if InputManager.is_attack_just_pressed(hid) or InputManager.is_ability_just_pressed(hid):
		_tokens = minf(TOKEN_CAP, _tokens + HIT_SHARE)


func _handle_jumps(delta: float, want: Vector3) -> void:
	var human_floor := _human.is_on_floor()
	if _human_was_on_floor and not human_floor and _human.velocity.y > 4.0:
		_jump_echo = JUMP_ECHO_DELAY
	_human_was_on_floor = human_floor
	if _jump_echo >= 0.0:
		_jump_echo -= delta
		if _jump_echo < 0.0 and _hero.is_on_floor():
			InputManager.press_virtual(player_id, &"jump")

	# Stuck: pushing the stick, on the floor, going nowhere.
	var moving := _flat(_hero.velocity).length()
	if want.length() > 0.4 and _hero.is_on_floor() and moving < STUCK_SPEED:
		_stuck += delta
		if _stuck >= STUCK_TIME:
			_stuck = 0.0
			InputManager.press_virtual(player_id, &"jump")
	else:
		_stuck = 0.0


# --- Helpers -------------------------------------------------------------------

func _resolve() -> bool:
	if _hero != null and is_instance_valid(_hero) and _hero.is_inside_tree() \
			and _human != null and is_instance_valid(_human) and _human.is_inside_tree():
		return true
	_hero = null
	_human = null
	for p in get_tree().get_nodes_in_group("players"):
		if not p is PlayerBase:
			continue
		if int(p.player_id) == player_id:
			_hero = p
		elif _human == null:
			_human = p
	return _hero != null and _human != null


## World direction -> InputManager pad space (x = strafe right, y = forward),
## the inverse of PlayerBase._wish_direction.
func _to_pad(world: Vector3) -> Vector2:
	if world.length_squared() < 0.0001:
		return Vector2.ZERO
	var fwd := _camera_forward()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	return Vector2(world.dot(right), world.dot(fwd)).limit_length(1.0)


func _camera_forward() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.FORWARD
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		return Vector3.FORWARD
	return fwd.normalized()


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
