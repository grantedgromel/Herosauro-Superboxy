class_name AdamastorStateMachine
extends RefCounted
## Attack + movement brain for Adamastor.
##
## Owned by the boss node, ticked every physics frame via update(delta) while the
## game is PLAYING. The boss FSM is the single source of horizontal velocity (the
## boss zeroes velocity.x/.z each frame, then we drive it here).
##
## State graph:
##   IDLE   -> brief reposition hub, immediately commits to CHASE
##   CHASE  -> stride toward the nearest hero (with a strafe weave), facing them;
##             slam when in melee range, lob a rock when held off at distance
##   SLAM   -> telegraphed wind-up + forward lunge + feet shockwave, then RETREAT
##   ROCK_THROW -> wind-up + arcing rock(s) at the heroes, then RETREAT
##   RETREAT -> back away from the hero briefly so it doesn't stand on them
##   PHASE_TWO -> one-shot entry that cranks speed/aggression, then back to CHASE
##
## Movement speed, aggression and decision cadence scale with GameManager
## difficulty and tighten again in phase two.

enum { IDLE, CHASE, SLAM, ROCK_THROW, RETREAT, PHASE_TWO }

const ShockwaveScene: PackedScene = preload("res://scenes/fx/shockwave.tscn")
const RockScene: PackedScene = preload("res://scenes/fx/rock_projectile.tscn")

var boss: Node3D
var state: int = IDLE

# Tunables (seeded from difficulty in reset(), tightened in phase two).
var _move_speed: float = 6.0
var _aggression: float = 0.6        # 0..1: bias toward closing/attacking
var _melee_range: float = 7.0       # within this -> slam
var _rock_range: float = 16.0       # beyond this -> prefer ranged rock
var _decide_interval: float = 3.0
var _decide_timer: float = 3.0
var _double_rocks: bool = false

# Busy flag: while an attack tween chain runs we don't pick a new action.
var _busy: bool = false
var _retreat_timer: float = 0.0
var _strafe: float = 0.0


func _init(p_boss: Node3D) -> void:
	boss = p_boss


func reset() -> void:
	state = IDLE
	var ds: float = GameManager.difficulty_scalar()
	_move_speed = 6.0 * ds
	_aggression = clampf(0.55 * ds, 0.3, 0.95)
	_melee_range = 7.0
	_rock_range = 16.0
	_decide_interval = clampf(3.0 / ds, 1.4, 4.0)
	_decide_timer = _decide_interval
	_double_rocks = false
	_busy = false
	_retreat_timer = 0.0
	_strafe = 0.0


## Called by the boss when GameManager.boss_phase_changed(2) fires.
func enter_phase_two() -> void:
	state = PHASE_TWO


func stop() -> void:
	# Used on death: park and stay quiet.
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
		CHASE:
			_update_chase(delta)
		RETREAT:
			_update_retreat(delta)
		SLAM, ROCK_THROW:
			# Attacks run as tween chains; the boss plants (velocity stays zeroed),
			# apart from the slam's nudge-driven lunge.
			pass


# --- PHASE_TWO -------------------------------------------------------------

func _enter_phase_two_now() -> void:
	_decide_interval = maxf(1.2, _decide_interval * 0.6)
	_decide_timer = minf(_decide_timer, _decide_interval)
	_move_speed *= 1.25
	_aggression = clampf(_aggression + 0.2, 0.3, 0.98)
	_double_rocks = true
	state = CHASE


# --- IDLE ------------------------------------------------------------------

func _update_idle(_delta: float) -> void:
	# Brief hub: commit to chasing the heroes.
	if _busy:
		return
	state = CHASE


# --- CHASE -----------------------------------------------------------------

func _update_chase(delta: float) -> void:
	if _busy:
		return
	var target: Node3D = boss.nearest_player()
	if target == null:
		return

	var to: Vector3 = target.global_position - boss.global_position
	to.y = 0.0
	var dist := to.length()
	var dir := to.normalized() if dist > 0.01 else Vector3.ZERO

	boss.face_toward(target.global_position)

	# Stride toward the hero with a sideways weave so it doesn't simply beeline.
	_strafe += delta
	var perp := Vector3(-dir.z, 0.0, dir.x)
	var weave := perp * sin(_strafe * 2.2) * 0.35
	boss.velocity.x = (dir.x + weave.x) * _move_speed
	boss.velocity.z = (dir.z + weave.z) * _move_speed

	# Commit to an attack.
	if dist <= _melee_range:
		_start_slam()
		return
	_decide_timer -= delta
	if _decide_timer <= 0.0:
		_decide_timer = _decide_interval
		# Held off at distance, or rolling aggression -> lob a rock.
		if dist >= _rock_range or randf() < _aggression * 0.5:
			_start_rock_throw()


# --- RETREAT ---------------------------------------------------------------

func _begin_retreat() -> void:
	_busy = false
	_retreat_timer = 0.45
	state = RETREAT


func _update_retreat(delta: float) -> void:
	var target: Node3D = boss.nearest_player()
	if target:
		var away: Vector3 = boss.global_position - target.global_position
		away.y = 0.0
		if away.length() > 0.01:
			away = away.normalized()
			boss.velocity.x = away.x * _move_speed * 0.8
			boss.velocity.z = away.z * _move_speed * 0.8
		boss.face_toward(target.global_position)
	_retreat_timer -= delta
	if _retreat_timer <= 0.0:
		state = CHASE


# --- SLAM ------------------------------------------------------------------

func _start_slam() -> void:
	state = SLAM
	_busy = true
	boss.velocity.x = 0.0
	boss.velocity.z = 0.0

	# Telegraphed forward lunge toward the target as the giant winds up.
	var target: Node3D = boss.nearest_player()
	if target:
		boss.face_toward(target.global_position, 1.0)
		var dir: Vector3 = target.global_position - boss.global_position
		dir.y = 0.0
		if dir.length() > 0.01:
			boss.nudge(dir.normalized(), 2.0)

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
	boss.velocity.x = 0.0
	boss.velocity.z = 0.0

	var target: Node3D = boss.nearest_player()
	if target:
		boss.face_toward(target.global_position, 1.0)

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
	# Back off after committing to an attack so the giant doesn't stand on the heroes.
	_begin_retreat()


func _spawn(node: Node3D, pos: Vector3) -> void:
	var root := boss.get_tree().get_first_node_in_group("spawn_root")
	if root == null:
		root = boss.get_tree().current_scene
	if root == null:
		node.queue_free()
		return
	root.add_child(node)
	node.global_position = pos
