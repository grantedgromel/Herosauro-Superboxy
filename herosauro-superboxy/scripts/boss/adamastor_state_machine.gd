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
##
## SOLO TUNING. This brain was written for two simultaneous targets, where every
## attack the giant threw was aimed at one of two heroes and the other got a
## free window. With a lone hero, every attack is aimed at YOU, so the same
## numbers read as twice the pressure. Three things were retuned rather than
## simply softened:
##
##   * cadence — the decision interval is longer, and SLAM_COOLDOWN forces a gap
##     between slams. Without it the giant slammed, retreated 0.45 s, closed and
##     slammed again, and the hero never had a punish window.
##   * volley — phase two threw a second rock at "the other player", falling
##     back to a fixed +3 z offset that only made sense on a narrow deck. It now
##     throws one rock at where you are and one at where you are GOING, so
##     changing direction beats it.
##   * escalation — phase two shortens the wind-up and the retreat instead of
##     just adding a projectile, which reads as the giant getting angry rather
##     than the screen getting busier.

enum { IDLE, CHASE, SLAM, ROCK_THROW, RETREAT, PHASE_TWO }

const ShockwaveScene: PackedScene = preload("res://scenes/fx/shockwave.tscn")
const RockScene: PackedScene = preload("res://scenes/fx/rock_projectile.tscn")

## Seconds the slam's active-frames window stays open.
const SLAM_WINDOW := 0.16
## Minimum gap between slams — the hero's punish window.
const SLAM_COOLDOWN := 1.3
const SLAM_COOLDOWN_P2 := 0.85
const WINDUP := 0.55
const WINDUP_P2 := 0.4
const RETREAT_TIME := 0.55
const RETREAT_TIME_P2 := 0.42
const SHOCKWAVE_DAMAGE := 14
const SHOCKWAVE_DAMAGE_P2 := 20
const ROCK_DAMAGE := 15
const ROCK_DAMAGE_P2 := 18
## How far ahead of a moving hero the second phase-two rock is aimed.
const ROCK_LEAD := 0.55

var boss: Node3D
var state: int = IDLE

# Tunables (seeded from difficulty in reset(), tightened in phase two).
var _move_speed: float = 6.0
var _aggression: float = 0.6        # 0..1: bias toward closing/attacking
var _melee_range: float = 7.0       # within this -> slam
var _rock_range: float = 16.0       # beyond this -> prefer ranged rock
var _decide_interval: float = 3.4
var _decide_timer: float = 3.4
var _escalated: bool = false        # phase two: faster, angrier, two rocks

# Busy flag: while an attack tween chain runs we don't pick a new action.
var _busy: bool = false
var _retreat_timer: float = 0.0
var _slam_cd: float = 0.0
var _strafe: float = 0.0
var _attack_tween: Tween = null


func _init(p_boss: Node3D) -> void:
	boss = p_boss


func reset() -> void:
	state = IDLE
	var ds: float = GameManager.difficulty_scalar()
	_move_speed = 5.8 * ds
	_aggression = clampf(0.5 * ds, 0.3, 0.9)
	_melee_range = 7.0
	_rock_range = 16.0
	_decide_interval = clampf(3.4 / ds, 1.9, 4.4)
	_decide_timer = _decide_interval
	_escalated = false
	_busy = false
	_retreat_timer = 0.0
	_slam_cd = 0.0
	_strafe = 0.0
	_kill_attack_tween()


## Called by the boss when GameManager.boss_phase_changed(2) fires.
func enter_phase_two() -> void:
	state = PHASE_TWO


func stop() -> void:
	# Used on death: park and stay quiet.
	_busy = true
	state = IDLE
	_kill_attack_tween()


func _kill_attack_tween() -> void:
	if _attack_tween and _attack_tween.is_valid():
		_attack_tween.kill()
	_attack_tween = null


func update(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return

	_slam_cd = maxf(0.0, _slam_cd - delta)

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
	_decide_interval = maxf(1.6, _decide_interval * 0.65)
	_decide_timer = minf(_decide_timer, _decide_interval)
	_move_speed *= 1.2
	_aggression = clampf(_aggression + 0.2, 0.3, 0.95)
	_escalated = true
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

	# Commit to an attack. The cooldown is what gives a solo hero a window to
	# actually swing back instead of being slammed the instant they close.
	if dist <= _melee_range and _slam_cd <= 0.0:
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
	_retreat_timer = RETREAT_TIME_P2 if _escalated else RETREAT_TIME
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
	_slam_cd = SLAM_COOLDOWN_P2 if _escalated else SLAM_COOLDOWN
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

	_attack_tween = boss.create_tween()
	# Windup: raise both arms.
	_attack_tween.tween_callback(func() -> void: boss.raise_arms(true))
	_attack_tween.tween_interval(WINDUP_P2 if _escalated else WINDUP)
	# Slam down.
	_attack_tween.tween_callback(_do_slam_impact)
	_attack_tween.tween_interval(0.45)   # recover
	_attack_tween.tween_callback(func() -> void: boss.raise_arms(false))
	_attack_tween.tween_interval(0.25)
	_attack_tween.tween_callback(_finish_attack)


## Two layers, and they cannot double-dip because the hero's i-frames swallow
## whichever lands second: the boss's slam hitbox is the heavy close hit, the
## shockwave is the wide, weaker ring that punishes a slow retreat.
func _do_slam_impact() -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	boss.slam_arms_down()
	boss.arm_slam(SLAM_WINDOW)
	var wave := ShockwaveScene.instantiate()
	wave.damage = SHOCKWAVE_DAMAGE_P2 if _escalated else SHOCKWAVE_DAMAGE
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

	_attack_tween = boss.create_tween()
	# Windup: cock one arm back.
	_attack_tween.tween_callback(func() -> void: boss.raise_arms(true))
	_attack_tween.tween_interval(0.5 if not _escalated else 0.4)
	_attack_tween.tween_callback(_do_rock_throw)
	_attack_tween.tween_interval(0.35)
	_attack_tween.tween_callback(func() -> void: boss.raise_arms(false))
	_attack_tween.tween_interval(0.2)
	_attack_tween.tween_callback(_finish_attack)


func _do_rock_throw() -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	var damage: int = ROCK_DAMAGE_P2 if _escalated else ROCK_DAMAGE
	var volley := _rock_volley()
	for t in volley:
		var rock := RockScene.instantiate()
		rock.damage = damage
		# Spawn up at the boss's hands, then arc toward the target.
		_spawn(rock, boss.global_position + Vector3(0.0, 6.0, 0.0))
		if rock.has_method("launch"):
			rock.launch(t)
	# One throw gesture, one sound - a phase-two double volley is still one heave.
	# Skipped on an empty volley (no target), so there is no heave without a rock.
	if not volley.is_empty():
		AudioManager.play_rock_throw()


## Where this volley lands. One rock at the hero's feet in phase one; in phase
## two a second at where they are heading, so the answer is to change direction
## rather than to keep running in a straight line.
func _rock_volley() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var target: Node3D = boss.nearest_player()
	if target == null:
		return out

	var here: Vector3 = target.global_position
	out.append(here)
	if not _escalated:
		return out

	var drift := Vector3.ZERO
	if target is CharacterBody3D:
		drift = (target as CharacterBody3D).velocity
	drift.y = 0.0
	if drift.length() < 1.0:
		# Standing still: put the second rock beside them instead, across the
		# deck rather than along it, so there is still somewhere to dodge to.
		var side := (here - boss.global_position)
		side.y = 0.0
		drift = Vector3(-side.z, 0.0, side.x).normalized() * 4.0
		if drift.length() < 0.01:
			drift = Vector3(0.0, 0.0, 3.0)
	else:
		drift *= ROCK_LEAD

	out.append(here + drift)
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
