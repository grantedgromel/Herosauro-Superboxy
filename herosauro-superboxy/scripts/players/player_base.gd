class_name PlayerBase
extends CharacterBody3D
## Shared movement / combat behaviour for the playable hero.
##
## Subclasses (Herosauro, Super Boxy) override _build_visuals() to assemble their
## toon model into the "Model" node and _perform_ability() for their signature
## move. Everything else - camera-relative locomotion, jumping, i-frames,
## knockback, fall respawn, cooldowns and the AnimationTree - lives here.
##
## Movement is third-person camera-relative: the pad vector from this hero's
## `input` is rotated through the active camera's yaw, so "forward" always means
## "away from the camera" no matter where the orbit rig has been swung.

@export var player_id: int = 1

## Who is driving this hero. Defaults to a human on the unprefixed action set,
## which is what a solo game wants and what the InputManager autoload used to
## provide globally; main.gd overrides it per roster slot before _ready() runs.
##
## It lives on the hero rather than in an autoload so that two heroes in one
## scene can be driven by different things — two humans, or a human and an
## AgentInput some AI writes into. Every read below goes through here, so
## nothing in this class knows or cares which it is.
var input: InputSource = DeviceInput.new()
@export var move_speed: float = 8.0
@export var sprint_multiplier: float = 1.3
@export var jump_velocity: float = 13.0
@export var gravity: float = 30.0
@export var coyote_time: float = 0.12        # 120 ms grace after leaving ground
@export var jump_buffer_time: float = 0.10   # 100 ms pre-jump queue
@export var low_jump_gravity_mult: float = 2.2  # extra gravity for short hops
@export var ability_cooldown: float = 2.0
@export var attack_cooldown: float = 0.45   # basic-attack rate (fast, spammable)
@export var attack_damage: int = 8          # basic-attack damage (low vs the special)
## Forward reach of the basic melee, measured from the hero's centre to the far
## face of the swing volume. 3.9 rather than 3.0 because the giant shoves the
## hero out to ~3.65 m; see _build_swing_box().
@export var attack_range: float = 3.9
@export var attack_hold: float = 0.32       # how long the swing anim freezes locomotion
@export var knockback_decay: float = 14.0
@export var invuln_time: float = 1.5

# --- Locomotion feel -------------------------------------------------------
# Velocity used to snap to the input, which read as robotic. These ramps take
# ~0.15 s to reach top speed and ~0.11 s to stop, so the hero has weight without
# feeling floaty. Air control is deliberately much weaker than ground control.
@export var ground_accel: float = 55.0
@export var ground_decel: float = 72.0
@export var air_accel: float = 22.0
@export var air_decel: float = 7.0
@export var turn_speed: float = 14.0         # how fast the model swings to face the move direction
@export var face_min_speed: float = 0.6      # below this we keep the current facing

# --- Animation blending ----------------------------------------------------
@export var walk_blend_speed: float = 2.6   # speed at which the walk clip is at full weight
@export var anim_blend_lambda: float = 12.0 # smoothing on the blend position (kills hitch jitter)
@export var action_speed_max: float = 2.2   # cap on how far an action clip is sped up to fit its hold

# --- Fall / respawn --------------------------------------------------------
## Falling this far below the last ground we stood on *and* having nothing left
## to land on counts as going over the side. Both halves matter: the depth alone
## would punish any tall drop, and the probe alone would fire the instant you
## stepped off a kerb. Neither hard-codes a deck height, so the check survives
## the arena being re-laid out.
@export var fall_kill_depth: float = 6.0
@export var fall_probe_length: float = 80.0   # how far down we look for anything to land on
const ABSOLUTE_KILL_Y := -60.0   # backstop if we somehow never touch a floor

# --- Physics body tuning ---------------------------------------------------
const FLOOR_MAX_ANGLE_DEG := 50.0   # forgiving enough for the deck lip and any ramp geometry
const FLOOR_SNAP_LENGTH := 0.5      # stay glued going down slopes / off small steps
const SAFE_MARGIN := 0.02           # the 0.001 default lets thin walls read inconsistently

# --- Aim / animation constants ---------------------------------------------
const ABILITY_AIM_HOLD := 0.45   # how long a special pins the facing to the camera line

const IDLE_LIB := "synth"
const IDLE_CLIP := "synth/idle"
const IDLE_LENGTH := 2.6    # one breathing cycle, seconds
const IDLE_KEYS := 13       # samples per cycle
const IDLE_SWAY := 0.05     # how far the held pose drifts between the two passing poses

const BLEND_PARAM := "parameters/locomotion/blend_position"
const ACTION_SPEED_PARAM := "parameters/action_speed/scale"
const ACTION_REQUEST_PARAM := "parameters/action/request"

## How fast we have to be falling for a touchdown to be worth a sound. Below
## this, the hero is walking off a kerb or being nudged down a step, and a thud
## every time would be constant.
const LAND_SFX_SPEED := 6.0

var spawn_position: Vector3 = Vector3.ZERO
var facing_dir: Vector3 = Vector3(1, 0, 0)

## The one-shot played when this hero's melee connects. Subclasses override it;
## AudioManager falls back to a synth thud for any name it has no file for.
var melee_hit_sfx: String = "boss_hit"

var _airborne_speed: float = 0.0   # downward speed on the last airborne frame
var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _invuln: float = 0.0
var _flicker: float = 0.0
var _ability_timer: float = 0.0
var _attack_timer: float = 0.0
var _attack_swing: float = 0.0    # active-frames window during which the swing can connect
var _swing: Hitbox = null
var _knockback: Vector3 = Vector3.ZERO
var _model_root: Node3D
var _wish_dir: Vector3 = Vector3.ZERO   # world-space move intent this tick
var _aim_lock: float = 0.0              # while > 0 facing is camera-driven, not movement-driven
var _ground_y: float = 0.0              # Y of the last floor we stood on

# Skeletal animation. Subclasses call bind_animations() in _build_visuals() with
# a {key: clip_hint} map; this builds an AnimationTree over the model's clips and
# play_action_anim() fires the one-shot layer for attacks / abilities.
var _anim: AnimationPlayer = null
var _anim_clips: Dictionary = {}
var _tree: AnimationTree = null
var _action_node: AnimationNodeAnimation = null
var _action_timer: float = 0.0
var _blend_speed: float = 0.0


func _ready() -> void:
	add_to_group("players")
	collision_layer = 1 << 1              # "players"
	# World AND boss: without the giant in the mask the hero walks straight
	# through his legs, which reads as a bug the moment you get close.
	collision_mask = (1 << 0) | (1 << 2)

	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	up_direction = Vector3.UP
	floor_max_angle = deg_to_rad(FLOOR_MAX_ANGLE_DEG)
	floor_snap_length = FLOOR_SNAP_LENGTH
	floor_stop_on_slope = true
	slide_on_ceiling = false              # bonking a ceiling drops you, it doesn't shunt you sideways
	safe_margin = SAFE_MARGIN

	_model_root = get_node_or_null("Model")
	if _model_root == null:
		_model_root = Node3D.new()
		_model_root.name = "Model"
		add_child(_model_root)
	_build_visuals()
	_fix_model_shadow_bounds()
	_build_contact_shadow()
	_build_swing_box()
	reset_state()


func _physics_process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	_update_timers(delta)
	_handle_jump(delta)
	# A subclass move (e.g. Boxy Dash) can take over locomotion for its duration.
	if not _custom_locomotion(delta):
		_handle_gravity(delta)
		_handle_movement(delta)
	else:
		_wish_dir = Vector3.ZERO   # the subclass owns velocity; don't steer against it
	_handle_ability()
	_handle_attack()
	move_and_slide()
	_face_movement(delta)
	_process_attack_hit()
	_handle_fall()
	_handle_flicker(delta)
	# After move_and_slide, so the blob is placed against the height he actually
	# ended the frame at rather than the one he started it at.
	_update_contact_shadow()
	_drive_anim(delta)


# --- Movement --------------------------------------------------------------

## World-space move intent, built from the pad vector and the camera's yaw.
func _wish_direction() -> Vector3:
	var pad := input.get_move_vector()
	if pad.length_squared() < 0.0001:
		return Vector3.ZERO
	var fwd := _camera_forward()
	var right := Vector3(-fwd.z, 0.0, fwd.x)   # fwd turned 90 deg clockwise about Y
	return (right * pad.x + fwd * pad.y).limit_length(1.0)


## The active camera's heading, flattened onto the ground plane. Falls back to
## world -Z when there is no camera yet (headless boots, the frame before the rig
## exists) so movement never silently dies.
func _camera_forward() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.FORWARD
	var b := cam.global_basis
	var fwd := -b.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = b.y     # camera aimed straight down: its up vector is the heading
		fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		return Vector3.FORWARD
	return fwd.normalized()


func _handle_movement(delta: float) -> void:
	_wish_dir = _wish_direction()
	var speed := move_speed * (sprint_multiplier if input.is_sprinting() else 1.0)
	var target := _wish_dir * speed

	# Accelerate only the *controlled* part of the velocity; knockback rides on
	# top and decays on its own, so a hit can't simply be walked off.
	var ctrl := Vector3(velocity.x - _knockback.x, 0.0, velocity.z - _knockback.z)
	var grounded := is_on_floor()
	var rate: float
	if _wish_dir == Vector3.ZERO:
		rate = ground_decel if grounded else air_decel
	else:
		rate = ground_accel if grounded else air_accel
	ctrl = ctrl.move_toward(target, rate * delta)

	velocity.x = ctrl.x + _knockback.x
	velocity.z = ctrl.z + _knockback.z


func _handle_gravity(delta: float) -> void:
	if not is_on_floor():
		var g := gravity
		# Variable jump height: cut the rise short if jump is released early.
		if velocity.y > 0.0 and not input.is_jump_held():
			g *= low_jump_gravity_mult
		velocity.y -= g * delta


func _handle_jump(delta: float) -> void:
	if is_on_floor():
		# Touchdown. _airborne_speed still holds the last airborne frame's fall
		# speed, because is_on_floor() only flips after the move that landed us.
		if _airborne_speed >= LAND_SFX_SPEED:
			AudioManager.play_land()
		_airborne_speed = 0.0
		_coyote = coyote_time
	else:
		_airborne_speed = maxf(0.0, -velocity.y)
		_coyote = max(0.0, _coyote - delta)

	if input.is_jump_just_pressed():
		_jump_buffer = jump_buffer_time
	else:
		_jump_buffer = max(0.0, _jump_buffer - delta)

	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = jump_velocity
		_jump_buffer = 0.0
		_coyote = 0.0
		AudioManager.play_jump()


## Face the way we are trying to go. While an attack or ability is committed the
## facing is instead pinned to where the camera was aiming, so swings and the
## Dino Energy bolt go where the player is looking.
func _face_movement(delta: float) -> void:
	if _aim_lock <= 0.0:
		var dir := _wish_dir
		if dir == Vector3.ZERO:
			var horiz := Vector3(velocity.x, 0.0, velocity.z)
			if horiz.length() > face_min_speed:
				dir = horiz.normalized()
		if dir != Vector3.ZERO:
			facing_dir = dir
	# Yaw 0 means "facing +X" here; the models carry a MODEL_YAW offset to match.
	var target_angle := atan2(-facing_dir.z, facing_dir.x)
	rotation.y = lerp_angle(rotation.y, target_angle, clampf(turn_speed * delta, 0.0, 1.0))


## Point the hero down the camera's line and hold it there for `hold` seconds.
## Called before an attack/ability resolves so facing_dir is already correct when
## the hit test runs or the projectile spawns.
func _aim_at_camera(hold: float) -> void:
	var fwd := _camera_forward()
	if fwd != Vector3.ZERO:
		facing_dir = fwd
	_aim_lock = maxf(_aim_lock, hold)


func _handle_fall() -> void:
	if is_on_floor():
		_ground_y = global_position.y
		return
	if global_position.y < ABSOLUTE_KILL_Y:
		_respawn()
		return
	if velocity.y > 0.0 or global_position.y > _ground_y - fall_kill_depth:
		return   # still rising, or this is just a drop we will survive
	if not _ground_below():
		_respawn()


## Anything on the world layer within fall_probe_length straight down? The river
## has no collider, so over the Douro this comes back empty.
func _ground_below() -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3.DOWN * fall_probe_length,
		1 << 0,
		[get_rid()])
	return not space.intersect_ray(query).is_empty()


func _respawn() -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	_ground_y = spawn_position.y
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
	if input.is_ability_just_pressed():
		_ability_timer = ability_cooldown
		_aim_at_camera(ABILITY_AIM_HOLD)
		_perform_ability()


# --- Basic attack ----------------------------------------------------------

## Quick, low-damage, spammable melee. Plays the hero's punch/jab clip and opens
## a brief active-frames window during which a forward-cone check hits the boss.
## Distinct from the special: low damage, short cooldown, no projectile/dash.
func _handle_attack() -> void:
	if _attack_timer > 0.0 or _action_timer > 0.0:
		return   # gated by its own cooldown and by any in-progress action anim (incl. specials/dash)
	if input.is_attack_just_pressed():
		_attack_timer = attack_cooldown
		_attack_swing = 0.14
		_aim_at_camera(attack_hold)
		play_action_anim("attack", attack_hold)


## Build the swing volume once. Armed for the active frames of an attack.
##
## This replaces a distance + dot-product cone that measured to the BOSS'S
## ORIGIN, which is at his feet — so the reach had to cover his half-extent as
## well as the gap. His collider is 5 x 9 x 4, so his surface stands 2.0-2.5 m
## out; add the hero's 0.45 m capsule and the closest legal approach is ~2.95 m
## against an attack_range of 3.0. Five centimetres of margin head-on, and from
## a diagonal the corner sits ~3.65 m away, which is simply unreachable. The
## basic melee could not reliably land a hit on a stationary target.
##
## A volume in front of the hero has no such problem: it overlaps the giant's
## collider rather than trying to out-reach it, and it catches props too.
func _build_swing_box() -> void:
	# Sized so the volume's far face lands at attack_range. That has to clear the
	# giant's PUSH-OUT, not just his collider: his body box is 5 x 9 x 4 and the
	# shove volume is that +1.4 on X and Z, so with the hero's 0.45 m capsule he
	# can be held 3.65 m from the giant's centre. A 3.0 m reach measured to the
	# giant's origin never stood a chance.
	#
	# Offset along local +X, NOT -Z: _face_movement sets
	# rotation.y = atan2(-facing_dir.z, facing_dir.x), so yaw 0 means facing +X and
	# the body's forward axis is local +X. (The models carry MODEL_YAW = +-PI/2 to
	# reconcile their own -Z forward with that; the hitbox hangs off the body, so
	# it follows the body's convention, not the model's.) Verified by probe: the
	# volume sits on facing_dir with dot 1.000 at all four cardinal headings.
	var near := 0.2                       # starts just clear of the hero's own capsule
	var depth: float = maxf(attack_range - near, 1.0)
	_swing = Hitbox.box(self, Vector3(depth, 2.0, 2.4),
		Vector3(near + depth * 0.5, 0.2, 0.0),
		PhysicsLayers.BOSS | PhysicsLayers.PROPS, "SwingVolume")
	_swing.damage = attack_damage
	_swing.knockback = 4.0
	_swing.lift = 0.0
	_swing.prop_impulse = 9.0
	_swing.source_player = player_id
	# Knockback should push away from the hero, not off the offset volume's centre.
	_swing.origin_node = self
	_swing.landed.connect(_on_swing_landed)


func _on_swing_landed(target: Node3D) -> void:
	if target.is_in_group("boss"):
		AudioManager.play_sfx(melee_hit_sfx)
		GameManager.hit_stop(0.03)
		if target.has_method("nudge"):
			target.nudge(facing_dir, 0.4)


func _process_attack_hit() -> void:
	if _swing == null:
		return
	var want := _attack_swing > 0.0
	if want and not _swing.is_armed():
		# Re-sync from the exports every swing rather than trusting the values
		# they had at _ready(). Both subclasses call super._ready() FIRST and set
		# attack_range/attack_damage AFTER it, so anything baked in at build time
		# is the base default, not the hero's own number.
		_sync_swing_shape()
		_swing.damage = attack_damage
		_swing.source_player = player_id
		_swing.arm(_attack_swing)
	elif not want and _swing.is_armed():
		_swing.disarm()


## Keep the volume's far face at attack_range.
func _sync_swing_shape() -> void:
	var box := _swing.shape as BoxShape3D
	if box == null:
		return
	var near := 0.2
	var depth: float = maxf(attack_range - near, 1.0)
	if is_equal_approx(box.size.x, depth):
		return
	# The shape is this hitbox's own, built in _build_swing_box, so mutating it
	# cannot leak into another node.
	box.size = Vector3(depth, box.size.y, box.size.z)
	_swing.position = Vector3(near + depth * 0.5, _swing.position.y, _swing.position.z)


## Snap to face a world point. Kept as public API for scripted moments (cutscene
## poses, boss-intro framing) that need the hero aimed without player input.
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
	_aim_lock = max(0.0, _aim_lock - delta)
	_knockback = _knockback.move_toward(Vector3.ZERO, knockback_decay * delta)

	var was_acting := _action_timer > 0.0
	_action_timer = max(0.0, _action_timer - delta)
	if was_acting and _action_timer <= 0.0:
		_end_action_anim()


## Blink the hero while invulnerable — but asymmetrically.
##
## This used to toggle visibility on a symmetric 0.1 s cycle, so across 1.5 s of
## i-frames the hero was simply absent for half of them. Under the old fixed
## camera that was a readable arcade blink; with a third-person camera locked to
## him it means the protagonist disappears out of the frame he is the subject of,
## and a scripted capture caught him missing in 2 of 10 gameplay frames.
##
## A 3:1 duty cycle still reads unmistakably as "I am invulnerable" while never
## leaving the screen without a hero for more than a few frames.
const FLICKER_ON := 0.09
const FLICKER_OFF := 0.03


func _handle_flicker(delta: float) -> void:
	if _invuln > 0.0:
		_invuln = max(0.0, _invuln - delta)
		_flicker -= delta
		if _flicker <= 0.0 and _model_root:
			var now_hidden := not _model_root.visible
			_model_root.visible = now_hidden
			_flicker = FLICKER_ON if now_hidden else FLICKER_OFF
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
	_aim_lock = 0.0
	_wish_dir = Vector3.ZERO
	_blend_speed = 0.0
	_ground_y = spawn_position.y
	facing_dir = Vector3(1, 0, 0)
	rotation = Vector3.ZERO
	_action_timer = 0.0
	if _tree:
		_tree.set(ACTION_REQUEST_PARAM, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		_tree.set(BLEND_PARAM, 0.0)
	if _model_root:
		_model_root.visible = true


# --- Skeletal animation ----------------------------------------------------
#
# The source art ships walk / run / attack clips but NO idle, and clip-swapping
# on a speed threshold popped between poses. Instead we build an AnimationTree:
#   locomotion : BlendSpace1D over idle <-> walk <-> run, driven by ground speed
#   action     : OneShot layer for attacks and abilities, fed through a TimeScale
# The missing idle is synthesized from the walk cycle (see _synthesize_idle).


## Resolve a {logical_key: clip_hint} map against the model's clips, then build
## the AnimationTree over them. If the model has no usable clips this is a no-op
## and every other animation call degrades to nothing.
func bind_animations(root: Node3D, mapping: Dictionary) -> void:
	_anim = _find_anim_player(root)
	if _anim == null:
		return
	for key in mapping:
		for clip in _anim.get_animation_list():
			if String(mapping[key]).to_lower() in String(clip).to_lower():
				_anim_clips[key] = clip
				break
	if not _anim_clips.has("walk") and not _anim_clips.has("idle"):
		return
	_build_anim_tree(_synthesize_idle())


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r := _find_anim_player(c)
		if r:
			return r
	return null


## Play a one-shot action clip (attack / ability), holding off locomotion for
## `hold` seconds. The clip is sped up (within reason) so a 2 s authored punch
## still lands inside a 0.3 s combat window instead of being hard-cut mid-swing.
func play_action_anim(key: String, hold: float = 0.5) -> void:
	# Set the busy window up front so it gates other actions (e.g. a basic attack
	# during a special/dash) even if the clip can't be resolved on this model.
	_action_timer = hold
	if _tree == null or _action_node == null or not _anim_clips.has(key):
		return
	var clip_name: String = _anim_clips[key]
	_action_node.animation = clip_name
	var scale := 1.0
	var clip := _tree.get_animation(clip_name)
	if clip and hold > 0.05:
		scale = clampf(clip.length / hold, 1.0, action_speed_max)
	_tree.set(ACTION_SPEED_PARAM, scale)
	_tree.set(ACTION_REQUEST_PARAM, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _end_action_anim() -> void:
	if _tree:
		_tree.set(ACTION_REQUEST_PARAM, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


func _drive_anim(delta: float) -> void:
	if _tree == null:
		return
	var hspeed := Vector2(velocity.x, velocity.z).length()
	_blend_speed = lerpf(_blend_speed, hspeed, clampf(1.0 - exp(-anim_blend_lambda * delta), 0.0, 1.0))
	_tree.set(BLEND_PARAM, _blend_speed)


func _build_anim_tree(idle_lib: AnimationLibrary) -> void:
	var loco := AnimationNodeBlendSpace1D.new()
	loco.blend_mode = AnimationNodeBlendSpace1D.BLEND_MODE_INTERPOLATED
	loco.sync = true    # keep every point on the same clock so feet don't pop between blends
	loco.min_space = 0.0
	loco.max_space = maxf(walk_blend_speed * 1.5, move_speed * sprint_multiplier)

	var idle_name := ""
	if _anim_clips.has("idle"):
		idle_name = _anim_clips["idle"]
	elif idle_lib != null:
		idle_name = IDLE_CLIP
	if idle_name != "":
		loco.add_blend_point(_clip_node(idle_name), 0.0, -1, &"idle")
	if _anim_clips.has("walk"):
		_ensure_loop(_anim_clips["walk"])
		loco.add_blend_point(_clip_node(_anim_clips["walk"]), walk_blend_speed, -1, &"walk")
	if _anim_clips.has("run"):
		_ensure_loop(_anim_clips["run"])
		loco.add_blend_point(_clip_node(_anim_clips["run"]), loco.max_space, -1, &"run")

	_action_node = AnimationNodeAnimation.new()
	if _anim_clips.has("attack"):
		_action_node.animation = _anim_clips["attack"]

	var action_speed := AnimationNodeTimeScale.new()

	var one_shot := AnimationNodeOneShot.new()
	one_shot.fadein_time = 0.06
	one_shot.fadeout_time = 0.18
	one_shot.autorestart = false

	var graph := AnimationNodeBlendTree.new()
	graph.add_node("locomotion", loco)
	graph.add_node("action_clip", _action_node)
	graph.add_node("action_speed", action_speed)
	graph.add_node("action", one_shot)
	graph.connect_node("action_speed", 0, "action_clip")
	graph.connect_node("action", 0, "locomotion")     # OneShot input 0 = "in"
	graph.connect_node("action", 1, "action_speed")   # OneShot input 1 = "shot"
	graph.connect_node("output", 0, "action")

	_tree = AnimationTree.new()
	_tree.name = "AnimTree"
	_tree.tree_root = graph
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	_anim.get_parent().add_child(_tree)

	# Take the model's libraries plus our synthesized idle, and point the tree at
	# the same root node the imported player uses so the bone paths still resolve.
	for lib_name in _anim.get_animation_library_list():
		_tree.add_animation_library(lib_name, _anim.get_animation_library(lib_name))
	if idle_lib != null:
		_tree.add_animation_library(IDLE_LIB, idle_lib)
	_tree.root_node = _tree.get_path_to(_anim.get_node(_anim.root_node))

	# Two mixers writing the same bones would fight; the tree owns them now.
	_anim.stop()
	_anim.active = false
	_tree.active = true


func _clip_node(clip_name: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip_name
	return node


func _ensure_loop(clip_name: String) -> void:
	var a := _anim.get_animation(clip_name)
	if a:
		a.loop_mode = Animation.LOOP_LINEAR


## Build an idle out of the walk cycle, because the art has none.
##
## A walk's two "passing" poses (quarter and three-quarter through the cycle) are
## mirror images of each other, so the average of the pair is very close to a
## symmetric standing pose. Easing the blend weight either side of 0.5 on a slow
## sine then gives a small shift of weight that reads as breathing. Doing it per
## track keeps it rig-agnostic - no assumption about which bone is the root.
func _synthesize_idle() -> AnimationLibrary:
	if _anim_clips.has("idle") or not _anim_clips.has("walk"):
		return null
	var walk := _anim.get_animation(_anim_clips["walk"])
	if walk == null or walk.length <= 0.0:
		return null

	var t_a := walk.length * 0.25
	var t_b := walk.length * 0.75
	var idle := Animation.new()
	idle.length = IDLE_LENGTH
	idle.loop_mode = Animation.LOOP_LINEAR

	for t in walk.get_track_count():
		var kind := walk.track_get_type(t)
		if kind != Animation.TYPE_POSITION_3D and kind != Animation.TYPE_ROTATION_3D \
				and kind != Animation.TYPE_SCALE_3D:
			continue
		var idx := idle.add_track(kind)
		idle.track_set_path(idx, walk.track_get_path(t))
		idle.track_set_interpolation_type(idx, Animation.INTERPOLATION_LINEAR)

		match kind:
			Animation.TYPE_POSITION_3D:
				var pa: Vector3 = walk.position_track_interpolate(t, t_a)
				var pb: Vector3 = walk.position_track_interpolate(t, t_b)
				for k in IDLE_KEYS:
					idle.position_track_insert_key(idx, _idle_time(k), pa.lerp(pb, _idle_weight(k)))
			Animation.TYPE_ROTATION_3D:
				var qa: Quaternion = walk.rotation_track_interpolate(t, t_a)
				var qb: Quaternion = walk.rotation_track_interpolate(t, t_b)
				for k in IDLE_KEYS:
					idle.rotation_track_insert_key(idx, _idle_time(k), qa.slerp(qb, _idle_weight(k)))
			Animation.TYPE_SCALE_3D:
				var sa: Vector3 = walk.scale_track_interpolate(t, t_a)
				var sb: Vector3 = walk.scale_track_interpolate(t, t_b)
				for k in IDLE_KEYS:
					idle.scale_track_insert_key(idx, _idle_time(k), sa.lerp(sb, _idle_weight(k)))

	var lib := AnimationLibrary.new()
	lib.add_animation("idle", idle)
	return lib


func _idle_time(k: int) -> float:
	return float(k) / float(IDLE_KEYS - 1) * IDLE_LENGTH


## 0.5 +- IDLE_SWAY on a full sine, so key 0 and the last key match and the loop
## closes without a seam.
func _idle_weight(k: int) -> float:
	return 0.5 + IDLE_SWAY * sin(float(k) / float(IDLE_KEYS - 1) * TAU)


# --- Virtual hooks (override in subclasses) --------------------------------

func _build_visuals() -> void:
	pass


## Hygiene for a skinned mesh, NOT the reason the hero looked unshadowed.
##
## His glTF is a single skinned MeshInstance3D carrying the AABB of its REST
## pose (0.69 x 1.70 x 0.44) with a cull margin of zero and no custom AABB, and
## a skinned mesh does not grow that box as the skeleton moves it. A pose that
## reaches outside it — a swing, a jump, a cape — leaves the renderer culling
## against a stale volume. Widening the margin is the documented remedy and
## costs nothing per frame, so it stays.
##
## But it is not why he read as unshadowed in captured frames. tools/shadowshot
## renders the same frame with him visible and hidden and subtracts: standing on
## the deck he throws a full-length streak along the sun, exactly where the
## geometry says it should be. It is invisible in play for two compounding
## reasons that have nothing to do with culling — the gameplay camera looks
## almost straight down the sun's own axis, which foreshortens the streak to
## nearly nothing, and what is left lands on the near-black tramway strip.
## _build_contact_shadow() is what actually fixes the read.
func _fix_model_shadow_bounds(margin: float = 1.2) -> void:
	for mi in _model_meshes(_model_root):
		mi.extra_cull_margin = maxf(mi.extra_cull_margin, margin)
		# Belt and braces: an imported glTF can carry SHADOW_CASTING_SETTING_OFF
		# from the DCC tool it came out of, and nothing else here checks.
		if mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## The contact shadow: a soft dark blob projected straight down under the hero.
##
## Not a substitute for the sun's shadow — that one is real and still there.
## This is the one that says "his feet are ON that". A raking 11.5 degree sun
## throws its shadow sideways and far, so it never touches the point of contact,
## and a third-person character with nothing under his feet reads as pasted onto
## the deck however good the lighting is. Every game with a low sun and a
## close camera carries one of these.
##
## This was a Decal first, which is the tidier tool — it conforms to whatever is
## under him with no z-fighting and no need for the surface normal. It is not
## the one that ships. A probe over the running fight showed the decal correct
## in every respect (visible, 1.9 x 1.0 x 1.9, ground at y=2.000 sitting inside
## a box spanning 1.350..2.350) and two A/B renders of the same gameplay frame
## still came back pixel-identical: nothing was drawing it. GL Compatibility
## does not render decals at all, so the web tier could never have had one
## either.
##
## So: a quad laid on the ground. It draws on every renderer, costs one triangle
## pair, and — unlike the decal — measurably shows up in a capture from here. It
## does not conform to uneven ground, which is why it is aligned to the surface
## normal the ray already returns; the deck is flat where he walks anyway.
##
## HOW MUCH IT BUYS, measured. A/B of the same gameplay frame: -6.0 of 255 under
## the shoes, -3.3 just below the feet, against -0.3/-0.5 to either side of him
## and +0.1 on far deck. Localised and real, but small in absolute terms, and
## that is the honest limit of it — he spawns on the tram bed, whose albedo is
## 0.235 by deliberate choice (see bridge_arena.gd: an up-facing plane much over
## 0.6 clips to cream through AgX at 2.4 sun energy). Darkening something that
## is already near-black cannot read, whatever draws it. The blob earns its keep
## on the pale kerb and flagstones, and on the tram bed the hero is separated
## from the ground by his own value instead. Lightening the tram bed is the only
## thing that would change that, and it is an art call, not a bug fix.
## Half the collision capsule's height (2.0 in herosauro.tscn / superboxy.tscn),
## i.e. how far the feet sit below the body origin. The same 1.0 the subclasses'
## MODEL_Y uses to drop the art onto the bottom of the capsule.
const FEET_BELOW_ORIGIN := 1.0

const CONTACT_FOOTPRINT := 1.9      ## blob diameter at the feet, metres
const CONTACT_STRENGTH := 0.55      ## how far towards black directly under him
## How far above the contact point the quad floats. Enough to clear z-fighting
## against the deck at this depth range, small enough to still read as contact.
const CONTACT_LIFT := 0.02
## Airborne, the blob widens and fades — the standard read for "further from the
## ground". Past this height it is gone entirely.
const CONTACT_FADE_HEIGHT := 3.0
const CONTACT_AIR_SPREAD := 1.7

var _contact: MeshInstance3D
var _contact_mat: StandardMaterial3D


func _build_contact_shadow() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE          # scaled per frame, so authored at unit size
	quad.orientation = PlaneMesh.FACE_Y

	_contact_mat = StandardMaterial3D.new()
	_contact_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_contact_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Plain alpha over black. Multiply blend would scale the light already there,
	# which is the more physical read, but its alpha handling differs per
	# backend and this whole detour started with something that silently drew
	# nothing. Predictable beats clever here.
	_contact_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
	_contact_mat.albedo_texture = _contact_texture()
	# Lying flat and hugging the ground, it must not write depth or it fights
	# the deck; and it must never be a shadow caster itself.
	_contact_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_contact_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = _contact_mat

	_contact = MeshInstance3D.new()
	_contact.name = "ContactShadow"
	_contact.mesh = quad
	_contact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# It is drawn where the ground is, not where the body is, so it must not
	# inherit his yaw — otherwise the blob spins as he turns.
	_contact.top_level = true
	add_child(_contact)
	_update_contact_shadow()


## Opaque at the centre, gone at the rim. A hard-edged disc reads as a sticker,
## which is the thing this is here to avoid.
func _contact_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(0.0, 0.0, 0.0, CONTACT_STRENGTH),
		Color(0.0, 0.0, 0.0, CONTACT_STRENGTH * 0.6),
		Color(0.0, 0.0, 0.0, 0.0),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 128
	gt.height = 128
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	return gt


## Sized and faded against the drop to the ground, so a jump lifts the blob off
## rather than dragging a hard disc through the air with him.
func _update_contact_shadow() -> void:
	if _contact == null:
		return
	var ground := _ground_hit()
	if ground.is_empty():
		_contact.visible = false
		return

	var point: Vector3 = ground["position"]
	var normal: Vector3 = ground["normal"]
	var feet := global_position.y - FEET_BELOW_ORIGIN
	var drop: float = maxf(0.0, feet - point.y)
	var t: float = clampf(drop / CONTACT_FADE_HEIGHT, 0.0, 1.0)

	_contact.visible = true
	# top_level, so this is a world transform: sit on the ground point, lie along
	# the surface, and scale to the faded footprint.
	var basis := _basis_from_up(normal)
	var width := CONTACT_FOOTPRINT * lerpf(1.0, CONTACT_AIR_SPREAD, t)
	_contact.global_transform = Transform3D(basis.scaled(Vector3(width, 1.0, width)),
			point + normal * CONTACT_LIFT)
	# Fades out with height, so a jump lifts the blob off rather than dragging a
	# hard disc across the deck under him.
	_contact_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0 - t)


## Any orthonormal basis whose +Y is `up`. Which way it faces about that axis is
## unobservable — the blob is radially symmetric.
func _basis_from_up(up: Vector3) -> Basis:
	var n := up.normalized()
	var ref := Vector3.FORWARD if absf(n.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(n).normalized()
	var z := n.cross(x)
	return Basis(x, n, z)


## The ground under the hero: position and normal, or empty if nothing is within
## reach. Always raycasts — is_on_floor() alone gives no contact point, and the
## blob has to sit somewhere.
func _ground_hit() -> Dictionary:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0.0, -FEET_BELOW_ORIGIN + 0.2, 0.0)
	var to := from + Vector3(0.0, -(CONTACT_FADE_HEIGHT + 0.7), 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.WORLD)
	query.exclude = [get_rid()]
	return space.intersect_ray(query)


func _model_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node == null:
		return out
	var mi := node as MeshInstance3D
	if mi != null:
		out.append(mi)
	for c in node.get_children():
		out.append_array(_model_meshes(c))
	return out


func _perform_ability() -> void:
	pass


## Return true to bypass standard gravity + movement this frame (used by dash).
func _custom_locomotion(_delta: float) -> bool:
	return false
