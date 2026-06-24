class_name AdamastorStateMachine
extends RefCounted
## Explicit attack brain for Adamastor.
##
## Owned by the boss node, ticked every physics frame via update(delta) while the
## game is PLAYING. Drives a small state graph: IDLE patrols the deck along Z and
## periodically commits to SLAM or ROCK_THROW. Animations use create_tween() on
## the boss's Model parts (NOT an AnimationPlayer). PHASE_TWO is a one-shot entry
## state that tightens timers and enables double rocks before returning to IDLE.

enum { IDLE, SLAM, ROCK_THROW, PHASE_TWO }

const ShockwaveScene: PackedScene = preload("res://scenes/fx/shockwave.tscn")
const RockScene: PackedScene = preload("res://scenes/fx/rock_projectile.tscn")

const PATROL_Z := 4.0
const PATROL_SPEED := 3.0

var boss: Node3D
var state: int = IDLE

# Tunable timers (phase 2 shortens the decision interval).
var _decide_interval: float = 3.0
var _decide_timer: float = 3.0
var _patrol_dir: float = 1.0
var _double_rocks: bool = false

# Busy flag: while an attack tween chain runs we don't pick a new action.
var _busy: bool = false
var _arm_bob: float = 0.0


func _init(p_boss: Node3D) -> void:
	boss = p_boss


func reset() -> void:
	state = IDLE
	_decide_interval = 3.0
	_decide_timer = _decide_interval
	_patrol_dir = 1.0
	_double_rocks = false
	_busy = false
	_arm_bob = 0.0


## Called by the boss when GameManager.boss_phase_changed(2) fires.
func enter_phase_two() -> void:
	state = PHASE_TWO


func stop() -> void:
	# Used on death: park in IDLE and stay quiet.
	_busy = true
	state = IDLE


func update(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return

	match state:
		PHASE_TWO:
			_enter_phase_two_now()
		IDLE:
			_update_idle(delta)
		SLAM, ROCK_THROW:
			# Attacks run as tween chains; nothing to drive per-frame here.
			pass


# --- PHASE_TWO -------------------------------------------------------------

func _enter_phase_two_now() -> void:
	_decide_interval = 1.8
	_decide_timer = minf(_decide_timer, _decide_interval)
	_double_rocks = true
	state = IDLE


# --- IDLE ------------------------------------------------------------------

func _update_idle(delta: float) -> void:
	# Patrol the bridge width along Z, bouncing at the edges.
	var z := boss.global_position.z
	if z > PATROL_Z:
		_patrol_dir = -1.0
	elif z < -PATROL_Z:
		_patrol_dir = 1.0
	boss.velocity.z = _patrol_dir * PATROL_SPEED

	# Gentle arm bob while pacing.
	_arm_bob += delta
	boss.bob_arms(sin(_arm_bob * 2.0) * 0.12)

	if _busy:
		return

	_decide_timer -= delta
	if _decide_timer <= 0.0:
		_decide_timer = _decide_interval
		if randf() < 0.5:
			_start_slam()
		else:
			_start_rock_throw()


# --- SLAM ------------------------------------------------------------------

func _start_slam() -> void:
	state = SLAM
	_busy = true
	boss.velocity.z = 0.0

	var tween := boss.create_tween()
	# Windup: raise both arms.
	tween.tween_callback(func() -> void: boss.raise_arms(true))
	tween.tween_interval(0.5)
	# Slam down.
	tween.tween_callback(_do_slam_impact)
	tween.tween_interval(0.45)   # recover
	tween.tween_callback(func() -> void: boss.raise_arms(false))
	tween.tween_interval(0.25)
	tween.tween_callback(_finish_attack)


func _do_slam_impact() -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	boss.slam_arms_down()
	var wave := ShockwaveScene.instantiate()
	if state == PHASE_TWO or _double_rocks:
		wave.damage = 20
	_spawn(wave, boss.global_position)
	GameManager.request_shake(0.5, 0.3)
	AudioManager.play_boss_slam()


# --- ROCK_THROW ------------------------------------------------------------

func _start_rock_throw() -> void:
	state = ROCK_THROW
	_busy = true
	boss.velocity.z = 0.0

	var tween := boss.create_tween()
	# Windup: cock one arm back.
	tween.tween_callback(func() -> void: boss.raise_arms(true))
	tween.tween_interval(0.4)
	tween.tween_callback(_do_rock_throw)
	tween.tween_interval(0.35)
	tween.tween_callback(func() -> void: boss.raise_arms(false))
	tween.tween_interval(0.2)
	tween.tween_callback(_finish_attack)


func _do_rock_throw() -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	var targets := _throw_targets()
	for t in targets:
		var rock := RockScene.instantiate()
		# Spawn up at the boss's hands, then arc toward the target.
		_spawn(rock, boss.global_position + Vector3(0.0, 6.0, 0.0))
		if rock.has_method("launch"):
			rock.launch(t)
	AudioManager.play_boss_slam()


func _throw_targets() -> Array:
	var out: Array = []
	var players := boss.get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return out
	var primary: Node3D = boss.nearest_player()
	if primary:
		out.append(primary.global_position)
	if _double_rocks:
		# Second rock at the other player if there is one, else a spread.
		for p in players:
			if p != primary:
				out.append((p as Node3D).global_position)
				break
		if out.size() < 2 and primary:
			out.append(primary.global_position + Vector3(0.0, 0.0, 3.0))
	return out


# --- Shared ----------------------------------------------------------------

func _finish_attack() -> void:
	_busy = false
	state = IDLE


func _spawn(node: Node3D, pos: Vector3) -> void:
	var root := boss.get_tree().get_first_node_in_group("spawn_root")
	if root == null:
		root = boss.get_tree().current_scene
	if root == null:
		node.queue_free()
		return
	root.add_child(node)
	node.global_position = pos
