class_name PlayerBase
extends CharacterBody3D
## Shared movement / combat behaviour for both heroes.
##
## Subclasses (Herosauro, Super Boxy) override _build_visuals() to assemble
## their toon model into the "Model" node and _perform_ability() for their
## signature move. Everything else - movement feel, jumping, i-frames,
## knockback, fall respawn, ability cooldown - lives here.

@export var player_id: int = 1
@export var move_speed: float = 8.0
@export var jump_velocity: float = 13.0
@export var gravity: float = 30.0
@export var coyote_time: float = 0.12        # 120 ms grace after leaving ground
@export var jump_buffer_time: float = 0.10   # 100 ms pre-jump queue
@export var low_jump_gravity_mult: float = 2.2  # extra gravity for short hops
@export var ability_cooldown: float = 2.0
@export var attack_cooldown: float = 0.45   # basic-attack rate (fast, spammable)
@export var attack_damage: int = 8          # basic-attack damage (low vs the special)
@export var attack_range: float = 3.0       # forward reach of the basic melee
@export var attack_hold: float = 0.32       # how long the swing anim freezes locomotion
@export var knockback_decay: float = 14.0
@export var invuln_time: float = 1.5

var spawn_position: Vector3 = Vector3.ZERO
var facing_dir: Vector3 = Vector3(1, 0, 0)

## Optional AI brain (an object exposing get_move_vector / wants_jump / is_jump_held /
## wants_ability / wants_attack). null => human-controlled, reads InputManager.
var ai_controller = null

var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _invuln: float = 0.0
var _flicker: float = 0.0
var _ability_timer: float = 0.0
var _attack_timer: float = 0.0
var _attack_swing: float = 0.0    # active-frames window during which the swing can connect
var _attack_landed: bool = false
var _knockback: Vector3 = Vector3.ZERO
var _model_root: Node3D

# Skeletal animation driver (for rigged glTF models). Subclasses call
# bind_animations() in _build_visuals() with a {key: clip_hint} map and
# play_action_anim() for their ability.
var _anim: AnimationPlayer = null
var _anim_clips: Dictionary = {}
var _action_timer: float = 0.0
var _cur_anim: String = ""


func _ready() -> void:
	add_to_group("players")
	collision_layer = 1 << 1   # "players"
	collision_mask = 1 << 0    # collide with "world"
	_model_root = get_node_or_null("Model")
	if _model_root == null:
		_model_root = Node3D.new()
		_model_root.name = "Model"
		add_child(_model_root)
	_build_visuals()
	reset_state()


func _physics_process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	if ai_controller:
		ai_controller.update(delta)
	_update_timers(delta)
	_handle_jump(delta)
	# A subclass move (e.g. Boxy Dash) can take over locomotion for its duration.
	if not _custom_locomotion(delta):
		_handle_gravity(delta)
		_handle_movement()
	_handle_ability()
	_handle_attack()
	move_and_slide()
	_face_movement(delta)
	_process_attack_hit()
	_handle_fall()
	_handle_flicker(delta)
	_drive_anim()


# --- Input source (human via InputManager, or the AI controller) -----------

func _input_move() -> Vector2:
	return ai_controller.get_move_vector() if ai_controller else InputManager.get_move_vector(player_id)

func _input_jump_pressed() -> bool:
	return ai_controller.wants_jump() if ai_controller else InputManager.is_jump_just_pressed(player_id)

func _input_jump_held() -> bool:
	return ai_controller.is_jump_held() if ai_controller else InputManager.is_jump_held(player_id)

func _input_ability_pressed() -> bool:
	return ai_controller.wants_ability() if ai_controller else InputManager.is_ability_just_pressed(player_id)

func _input_attack_pressed() -> bool:
	return ai_controller.wants_attack() if ai_controller else InputManager.is_attack_just_pressed(player_id)


# --- Movement --------------------------------------------------------------

func _handle_movement() -> void:
	var input := _input_move()
	var target := Vector3(input.x, 0.0, input.y) * move_speed
	velocity.x = target.x + _knockback.x
	velocity.z = target.z + _knockback.z


func _handle_gravity(delta: float) -> void:
	if not is_on_floor():
		var g := gravity
		# Variable jump height: cut the rise short if jump is released early.
		if velocity.y > 0.0 and not _input_jump_held():
			g *= low_jump_gravity_mult
		velocity.y -= g * delta


func _handle_jump(delta: float) -> void:
	if is_on_floor():
		_coyote = coyote_time
	else:
		_coyote = max(0.0, _coyote - delta)

	if _input_jump_pressed():
		_jump_buffer = jump_buffer_time
	else:
		_jump_buffer = max(0.0, _jump_buffer - delta)

	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = jump_velocity
		_jump_buffer = 0.0
		_coyote = 0.0
		AudioManager.play_jump()


func _face_movement(delta: float) -> void:
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if horiz.length() > 0.6:
		facing_dir = horiz.normalized()
		var target_angle := atan2(-facing_dir.z, facing_dir.x)
		rotation.y = lerp_angle(rotation.y, target_angle, clamp(12.0 * delta, 0.0, 1.0))


func _handle_fall() -> void:
	if global_position.y < -5.0:
		_respawn()


func _respawn() -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	GameManager.damage_player(player_id, GameManager.FALL_PENALTY)
	_start_iframes()
	GameManager.notify_player_respawned(player_id)


# --- Combat ----------------------------------------------------------------

## Returns true if the hit landed (false if the player was invulnerable).
func take_hit(amount: int, knockback: Vector3 = Vector3.ZERO) -> bool:
	if _invuln > 0.0 or GameManager.state != GameManager.State.PLAYING:
		return false
	GameManager.damage_player(player_id, amount)
	apply_knockback(knockback)
	_start_iframes()
	AudioManager.play_hurt()
	return true


func apply_knockback(impulse: Vector3) -> void:
	_knockback.x += impulse.x
	_knockback.z += impulse.z
	if impulse.y != 0.0:
		velocity.y = impulse.y


func is_invulnerable() -> bool:
	return _invuln > 0.0


func _start_iframes() -> void:
	_invuln = invuln_time
	_flicker = 0.0


# --- Ability ---------------------------------------------------------------

func _handle_ability() -> void:
	if _ability_timer > 0.0:
		return
	if _input_ability_pressed():
		_ability_timer = ability_cooldown
		_perform_ability()


# --- Basic attack ----------------------------------------------------------

## Quick, low-damage, spammable melee. Plays the hero's punch/jab clip and opens
## a brief active-frames window during which a forward-cone check hits the boss.
## Distinct from the special: low damage, short cooldown, no projectile/dash.
func _handle_attack() -> void:
	if _attack_timer > 0.0 or _action_timer > 0.0:
		return   # gated by its own cooldown and by any in-progress action anim (incl. specials/dash)
	if _input_attack_pressed():
		_attack_timer = attack_cooldown
		_attack_swing = 0.14
		_attack_landed = false
		play_action_anim("attack", attack_hold)
		AudioManager.play_attack()


func _process_attack_hit() -> void:
	if _attack_swing <= 0.0 or _attack_landed:
		return
	var boss := get_tree().get_first_node_in_group("boss")
	if boss == null:
		return
	var to: Vector3 = (boss as Node3D).global_position - global_position
	to.y = 0.0
	var dist := to.length()
	if dist > attack_range:
		return
	# Must be roughly facing the boss (forward cone), so it reads as a directed swing.
	if dist > 0.1 and facing_dir.dot(to.normalized()) < 0.3:
		return
	GameManager.damage_boss(attack_damage, player_id)
	AudioManager.play_boss_hit()
	if boss.has_method("nudge"):
		boss.nudge(facing_dir, 0.4)
	GameManager.hit_stop(0.03)
	_attack_landed = true


## Snap to face a world point (used by the AI ally so its swings/abilities aim true
## even when standing still; human facing stays movement-driven via _face_movement).
func face_toward(world_pos: Vector3) -> void:
	var to := world_pos - global_position
	to.y = 0.0
	if to.length() < 0.1:
		return
	facing_dir = to.normalized()
	rotation.y = atan2(-facing_dir.z, facing_dir.x)


## 0.0 = just used, 1.0 = ready. Drives the HUD cooldown bar.
func get_ability_fraction() -> float:
	if ability_cooldown <= 0.0:
		return 1.0
	return clamp(1.0 - _ability_timer / ability_cooldown, 0.0, 1.0)


func is_ability_ready() -> bool:
	return _ability_timer <= 0.0


# --- Timers / visuals ------------------------------------------------------

func _update_timers(delta: float) -> void:
	_ability_timer = max(0.0, _ability_timer - delta)
	_attack_timer = max(0.0, _attack_timer - delta)
	_attack_swing = max(0.0, _attack_swing - delta)
	_action_timer = max(0.0, _action_timer - delta)
	_knockback = _knockback.move_toward(Vector3.ZERO, knockback_decay * delta)


func _handle_flicker(delta: float) -> void:
	if _invuln > 0.0:
		_invuln = max(0.0, _invuln - delta)
		_flicker -= delta
		if _flicker <= 0.0:
			_flicker = 0.1
			if _model_root:
				_model_root.visible = not _model_root.visible
		if _invuln <= 0.0 and _model_root:
			_model_root.visible = true
	elif _model_root and not _model_root.visible:
		_model_root.visible = true


func reset_state() -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	_invuln = 0.0
	_flicker = 0.0
	_ability_timer = 0.0
	_attack_timer = 0.0
	_attack_swing = 0.0
	_attack_landed = false
	facing_dir = Vector3(1, 0, 0)
	rotation = Vector3.ZERO
	if _model_root:
		_model_root.visible = true


# --- Skeletal animation ----------------------------------------------------

## Find the model's AnimationPlayer and resolve a {logical_key: clip_hint} map
## to actual clip names. Loops walk/run; leaves the model in an idle pose.
func bind_animations(root: Node3D, mapping: Dictionary) -> void:
	_anim = _find_anim_player(root)
	if _anim == null:
		return
	for key in mapping:
		for clip in _anim.get_animation_list():
			if String(mapping[key]).to_lower() in String(clip).to_lower():
				_anim_clips[key] = clip
				break
	for k in ["walk", "run"]:
		if _anim_clips.has(k):
			var an := _anim.get_animation(_anim_clips[k])
			if an:
				an.loop_mode = Animation.LOOP_LINEAR
	_play_idle()


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r := _find_anim_player(c)
		if r:
			return r
	return null


## Play a one-shot action clip (e.g. an ability), holding off locomotion for `hold` seconds.
func play_action_anim(key: String, hold: float = 0.5) -> void:
	# Set the busy window up front so it gates other actions (e.g. a basic attack
	# during a special/dash) even if the clip can't be resolved on this model.
	_action_timer = hold
	if _anim == null or not _anim_clips.has(key):
		return
	_cur_anim = _anim_clips[key]
	_anim.play(_cur_anim)


func _drive_anim() -> void:
	if _anim == null or _action_timer > 0.0:
		return
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if hspeed > 4.0 and _anim_clips.has("run"):
		_play_loop(_anim_clips["run"])
	elif hspeed > 0.6 and _anim_clips.has("walk"):
		_play_loop(_anim_clips["walk"])
	else:
		_play_idle()


func _play_loop(clip: String) -> void:
	if clip == _cur_anim and _anim.is_playing():
		return
	_cur_anim = clip
	_anim.play(clip)


func _play_idle() -> void:
	var clip: String = _anim_clips.get("idle", _anim_clips.get("walk", ""))
	if clip == "" or clip == _cur_anim:
		return
	_cur_anim = clip
	_anim.play(clip)
	_anim.seek(0.0, true)
	_anim.pause()


# --- Virtual hooks (override in subclasses) --------------------------------

func _build_visuals() -> void:
	pass


func _perform_ability() -> void:
	pass


## Return true to bypass standard gravity + movement this frame (used by dash).
func _custom_locomotion(_delta: float) -> bool:
	return false
