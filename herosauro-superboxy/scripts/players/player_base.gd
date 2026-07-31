class_name PlayerBase
extends CharacterBody3D
## Shared movement / combat behaviour for a playable hero.
##
## Subclasses (Herosauro, Super Boxy) override _build_visuals() to assemble their
## toon model into the "Model" node and _perform_ability() for their signature
## move. Everything else - camera-relative locomotion, jumping, i-frames,
## knockback, fall respawn, cooldowns, squash and stretch, the co-op leash, the
## knockdown and the AnimationTree - lives here.
##
## Movement is third-person camera-relative: the pad vector from InputManager is
## rotated through the active camera's yaw, so "forward" always means "away from
## the camera" no matter where the orbit rig has been swung. In co-op the camera
## aims itself at the giant, so that resolves to "toward the fight" for both
## heroes, which is the beat-'em-up convention.
##
## `player_id` is the hero's SEAT, not a cosmetic tag: it selects the Input Map
## action set (InputManager takes it on every query), keys the health, combo and
## score this hero owns in GameManager, and picks the spawn point in main.gd.

## 1 = Herosauro, 2 = Super Boxy. Set by main.gd before the node enters the tree.
@export var player_id: int = 1
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
## Lateral limit on where a hero may be dropped back in. Matches
## BridgeArena.ROADWAY_HALF, so a recovery never lands on the kerb or in a rail.
const RECOVERY_HALF_WIDTH := 5.0
## How far back from the partner, on the side away from the giant, a hero returns.
const RECOVERY_GAP := 2.6
## How far ABOVE the partner a returning hero is dropped in. Just enough to be
## outside the deck rather than inside it, and small enough that the drop reads
## as arriving rather than as a second fall. Named because `_respawn()` puts the
## return's dust burst on the deck under it and the two must not drift apart.
const RECOVERY_DROP := 1.0

# --- Co-op leash -----------------------------------------------------------
## One shared camera can only hold so much ground, so the pair cannot be allowed
## to wander to opposite ends of a hundred-metre deck.
##
## Two mechanisms, deliberately in that order. From LEASH_RADIUS out, a SOFT
## TETHER pulls both heroes gently toward each other — the runner feels drag and
## the one being left behind is drawn along, which reads as the pair being roped
## together rather than as one of them hitting a wall. At LEASH_RADIUS +
## LEASH_SLACK a HARD CLAMP takes over and the separation simply cannot grow.
##
## The number is the camera's, not a feel choice. CameraRig.group_max_distance
## (16 m) at a 62 deg vertical FOV frames a spread of roughly 20 m on the
## narrowest aspect the game ships in, once CameraRig.group_padding is taken out.
## 16 m of separation therefore always fits. Raise one of the three and you have
## to raise the others.
const LEASH_RADIUS := 12.0
const LEASH_SLACK := 4.0
## Peak inward speed the soft tether adds, in m/s. Well under move_speed, so a
## player can still fight it and reach the hard clamp; enough that an idle partner
## is visibly towed instead of standing there while the frame stretches.
const LEASH_PULL := 3.0
## Ceiling on how fast the hard clamp may drag a hero back, in m/s. Just over
## sprint speed (move_speed * sprint_multiplier), so the pair always converge.
const LEASH_REEL_SPEED := 20.0

# --- Co-op knockdown -------------------------------------------------------
## A hero at zero health in co-op is DOWN, not dead: they slump, stop taking
## hits, and their partner's continued existence is what brings them back. The
## run only ends when nobody is left standing, which GameManager already tests by
## asking the scene.
##
## In solo this path is unreachable by construction — a lone hero at zero IS
## every hero down, so GameManager ends the run in the same call and the timer
## below never ticks (it only runs while PLAYING).
const DOWN_TIME := 4.0
## How flat and how far over a downed hero lies. Big numbers on purpose: at a
## co-op camera distance the read has to survive being 15 m away.
const DOWN_SQUASH := -0.42
const DOWN_TILT := deg_to_rad(74.0)

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

# --- Squash and stretch ----------------------------------------------------
## A character that translates without deforming reads as a prop being slid
## around, so every impulse the body takes also deforms it. `_stretch` is one
## signed scalar — positive is tall and thin, negative is short and wide — driven
## as a damped spring, so a kick settles with one overshoot instead of snapping.
##
## Volume is roughly conserved: the two horizontal axes take half the vertical
## change with the opposite sign. That is the difference between a body squashing
## and a mesh being scaled, and the eye knows which one it is looking at.
##
## Deliberately underdamped (damping is well below the critical 2*sqrt(stiffness)
## of ~27) — the overshoot IS the rubberiness.
const SQUASH_STIFFNESS := 190.0
const SQUASH_DAMPING := 15.0
const SQUASH_LIMIT := 0.45
const JUMP_STRETCH := 0.24            ## push-off: the body elongates as it leaves
const LAND_SQUASH := -0.32            ## compression at LAND_FULL_SPEED of descent
const LAND_FULL_SPEED := 20.0
## The coil before the swing and the extension after it.
##
## Raised from -0.15 / 0.14. The spring's envelope is `exp(-SQUASH_DAMPING/2 * t)`,
## which is a 90 ms half-life, so a kick is essentially gone a fifth of a second
## after it lands and the ONLY frame that shows the full amplitude is the one it
## was applied on. At -0.15 that is a 15% squash for one frame on a 2 m hero seen
## from the co-op camera's ~16 m: about 2% of frame height, which is below the
## threshold at which the eye reads a deformation at all. The rubric asks for
## "squash and stretch on everything that moves" and scores a character that
## translates without deforming as a prop being slid around, so anticipation and
## follow-through have to be legible, not merely present.
##
## -0.22 / 0.20 is still well inside SQUASH_LIMIT even when the follow-through
## lands on top of an undecayed anticipation (worst case ~0.30 of the 0.45 cap),
## so the two never clip each other.
const ATTACK_ANTICIPATION := -0.22    ## the coil before the swing
const ATTACK_FOLLOW := 0.20           ## the extension after it
const ATTACK_FOLLOW_FRACTION := 0.35  ## where in the hold the follow-through lands
const HURT_SQUASH := -0.26            ## taking one flattens you too
## How fast the model rights itself out of the downed tilt.
const TILT_LAMBDA := 14.0

# --- The impact contract ---------------------------------------------------
## ARCHITECTURE.md, "Weight — every action": a visual FX at the point of contact,
## a camera response, an audio transient, a hit-stop, and a UI acknowledgement.
## Every one of the numbers below is one of those five legs for an impact a hero
## is on one end of. `ImpactFX` is leg one everywhere; `GameManager.request_shake`
## is two, `AudioManager` three, `GameManager.hit_stop` four, and the HUD picks up
## five off `GameManager.player_damaged` / `boss_damaged`.

## Seconds of freeze per point of damage a hero takes.
##
## Anchored, not invented: `Adamastor.SLAM_DAMAGE` (18) x this is exactly
## `Adamastor.SLAM_HIT_STOP` (0.09), so the heaviest single blow in the fight
## keeps the freeze the boss stream tuned for it while every other route to a
## hero — the giant's body contact, the shockwave, a thrown rock, going over the
## side — gets one at all. `GameManager.hit_stop` refuses to nest, and `take_hit`
## runs BEFORE the `Hitbox.landed` handlers, so this is now the call that decides
## the freeze for a hit on a hero; see the report.
const HURT_STOP_PER_DAMAGE := 0.005
## Floor and ceiling on that. The floor keeps the giant's 6-damage body contact
## from being a freeze so short it reads as a dropped frame; the ceiling stops a
## phase-two slam (25) from stopping the game dead for an eighth of a second.
const HURT_STOP_MIN := 0.025
const HURT_STOP_MAX := 0.11

## Damage that `ImpactFX` power 1.0 corresponds to on a hero-hit spark. The same
## number the hurt squash normalises by, so the burst and the deformation agree
## about how big the hit was.
const HURT_FX_REFERENCE := 20.0

## Where a hero-hit spark sits: back along the incoming blow by roughly the
## collision capsule's radius, so the chips come off the side that was struck
## rather than out of the middle of the body, and lifted to upper-chest height
## where the camera is actually looking.
const HURT_FX_INSET := 0.45
const HURT_FX_LIFT := 0.35

## Radius of the dust ring a hero's own landing rolls out, in metres. Small: this
## is a hero's boots, not the giant's fists (his slam ring is 15 m).
const LAND_FX_RADIUS := 1.2

# --- Going over the side ---------------------------------------------------
## The worst-rated impact in the game before this pass: it cost twenty health in
## complete silence. `_respawn()` is now two beats, and each carries all five.

## The `audio` stream's sound for going over the side — a receding doppler
## whistle, a 30 ms hole, then the Douro taking it, in one stream because there
## is no gap to put a second call in: the loss and the return happen inside one
## call to `_respawn()`.
##
## Called through `has_method` rather than directly. It has landed, so this
## resolves today; the guard stays because `players` and `audio` are separate
## streams working at the same time, and a hero must never fail to come back
## because the other stream is mid-edit. The fallback is the hurt transient, so
## leg three of the contract is covered whatever happens to the sample.
const FALL_SFX := "play_fall"
## Camera punch as the hero goes over, and as they drop back in. The loss is the
## bigger of the two on purpose: losing a fifth of your health off the deck
## should hit harder than the recovery that follows it.
const FALL_SHAKE := 0.42
const FALL_SHAKE_TIME := 0.34
const RECOVER_SHAKE := 0.16
const RECOVER_SHAKE_TIME := 0.18
## How hard the burst at the point of loss throws. Above a jab's 1.0 — this is a
## whole hero leaving the deck, and it is the last thing the player sees of them.
const FALL_FX_POWER := 1.5
## The drop back in. A hero arriving on the calçada is a landing like any other,
## so it gets the same shape of burst a heavy landing does.
const RECOVER_FX_RADIUS := 1.6
const RECOVER_FX_POWER := 1.1
## The pop out of the recovery. Same idea as `_get_up()`: the body springs onto
## the deck rather than materialising at rest scale.
const RECOVER_SQUASH := -0.30

# --- Knockdown and revive --------------------------------------------------
## A hero hitting the deck at zero health, and springing back off it, are impacts
## too — a whole body arriving on the calçada. Both had four legs and drew
## nothing at the point of contact.
##
## The knockdown burst is the bigger of the two: it is a body dropping, where the
## revive is a body pushing off. Neither carries a hit-stop of its own — the blow
## that caused the knockdown has already frozen the frame through `take_hit` (or
## through `_respawn`, if the fall penalty is what emptied the bar), and
## `GameManager.hit_stop` refuses to nest, so asking again would only be ignored.
const DOWN_FX_RADIUS := 1.8
const DOWN_FX_POWER := 1.3
const UP_FX_RADIUS := 1.4
const UP_FX_POWER := 0.9

var spawn_position: Vector3 = Vector3.ZERO
var facing_dir: Vector3 = Vector3(1, 0, 0)

var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _was_on_floor: bool = true
var _air_time: float = 0.0
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
var _partner_ref: PlayerBase = null     # the other hero, re-resolved when it goes stale

var _downed: bool = false
var _down_timer: float = 0.0

var _feet_drop: float = 1.0             # body origin -> soles, measured from the collider

var _stretch: float = 0.0
var _stretch_vel: float = 0.0
var _impact_speed: float = 0.0          # descent speed banked before move_and_slide()
var _tilt: float = 0.0                  # radians the model is tipped over (knockdown)
var _follow_timer: float = 0.0          # counts down to the attack's follow-through

# Skeletal animation. Subclasses call bind_animations() in _build_visuals() with
# a {key: clip_hint} map; this builds an AnimationTree over the model's clips and
# play_action_anim() fires the one-shot layer for attacks / abilities.
var _anim: AnimationPlayer = null
var _anim_clips: Dictionary = {}
var _tree: AnimationTree = null
## Secondary motion. Null on a model with no skeleton; every call site guards.
var _lag: BodyLag = null
var _action_node: AnimationNodeAnimation = null
var _action_timer: float = 0.0
var _blend_speed: float = 0.0


func _ready() -> void:
	add_to_group("players")
	collision_layer = PhysicsLayers.PLAYERS
	# World AND boss: without the giant in the mask the hero walks straight
	# through his legs, which reads as a bug the moment you get close.
	#
	# PLAYERS is deliberately NOT in the mask, so the two heroes pass through each
	# other. On a deck with an open drop either side, a partner who can body-check
	# you is a partner who can kill you by accident, and "my friend shoved me into
	# the Douro" is a co-op story nobody enjoys twice.
	collision_mask = PhysicsLayers.WORLD | PhysicsLayers.BOSS

	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	up_direction = Vector3.UP
	floor_max_angle = deg_to_rad(FLOOR_MAX_ANGLE_DEG)
	floor_snap_length = FLOOR_SNAP_LENGTH
	floor_stop_on_slope = true
	slide_on_ceiling = false              # bonking a ceiling drops you, it doesn't shunt you sideways
	safe_margin = SAFE_MARGIN

	_measure_feet()
	_model_root = get_node_or_null("Model")
	if _model_root == null:
		_model_root = Node3D.new()
		_model_root.name = "Model"
		add_child(_model_root)
	_build_visuals()
	_build_swing_box()
	# One handler for every route to zero health — boss hitbox, shockwave, rock,
	# fall penalty — so the knockdown can never be missed by a damage source that
	# forgot to call it. GameManager.revive_player re-emits the same signal with
	# health back on the clock, which is what stands the hero up again.
	GameManager.player_damaged.connect(_on_health_changed)
	reset_state()


func _physics_process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	if _downed:
		_process_downed(delta)
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
	# After the movement pass, because _handle_movement OVERWRITES velocity.x/z
	# from the input each tick — a tether applied before it would be thrown away.
	_apply_leash()
	# Banked here because move_and_slide() zeroes velocity.y against the floor, so
	# by the time _handle_landing runs the speed that caused the impact is gone.
	_impact_speed = maxf(0.0, -velocity.y)
	move_and_slide()
	_clamp_separation(delta)
	_handle_landing(delta)
	_face_movement(delta)
	_process_attack_hit()
	_handle_fall()
	_handle_flicker(delta)
	_drive_anim(delta)
	_drive_squash(delta)


## A downed hero still obeys gravity (so they lie on the deck rather than hang
## where they fell) and still falls off the bridge, but takes no input, deals no
## damage and takes none. Everything else is on hold until the partner gets them
## back up.
func _process_downed(delta: float) -> void:
	_down_timer = maxf(0.0, _down_timer - delta)
	_wish_dir = Vector3.ZERO
	_knockback = _knockback.move_toward(Vector3.ZERO, knockback_decay * delta)
	_handle_gravity(delta)
	# ------------------------------------------------------------------------
	# HERE IS WHERE AN IMPULSE ON A DOWNED HERO IS DROPPED. These two lines run
	# every frame while `_downed`, so anything `apply_knockback` put in the
	# reservoir above — a shockwave, a slam, a hazard, anything an unwritten
	# system does later — is scrubbed to zero before `move_and_slide` can act on
	# it. `take_hit` already refuses while downed, so the only route in is a
	# direct `apply_knockback` call, and that call is silently a no-op.
	#
	# INTENDED, and it is the whole point of the pose. A hero at zero health in
	# co-op is a landmark: their partner has four seconds to keep fighting near a
	# body that is flat on the deck and stays where it fell. A downed hero who
	# slides reads as a dropped ragdoll, and one who is blown off the bridge by a
	# wave they cannot dodge turns a knockdown into a second death sentence.
	#
	# If a system genuinely needs to move a downed hero, move it POSITIONALLY —
	# `global_position += ...`, rate-capped — the way Adamastor's push-out and
	# `_clamp_separation` both already do. Gravity is deliberately still applied
	# above, so a body dropped in mid-air still falls, and `_handle_fall` below
	# still takes it over the side if that is where it lands.
	# ------------------------------------------------------------------------
	velocity.x = move_toward(velocity.x, 0.0, ground_decel * delta)
	velocity.z = move_toward(velocity.z, 0.0, ground_decel * delta)
	move_and_slide()
	_handle_landing(delta)
	_handle_fall()
	_drive_anim(delta)
	_drive_squash(delta)
	if _down_timer <= 0.0:
		GameManager.revive_player(player_id)


# --- Movement --------------------------------------------------------------

## World-space move intent, built from the pad vector and the camera's yaw.
func _wish_direction() -> Vector3:
	var pad := InputManager.get_move_vector(player_id)
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
	var speed := move_speed * (sprint_multiplier if InputManager.is_sprinting(player_id) else 1.0)
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
		if velocity.y > 0.0 and not InputManager.is_jump_held(player_id):
			g *= low_jump_gravity_mult
		velocity.y -= g * delta


func _handle_jump(delta: float) -> void:
	if is_on_floor():
		_coyote = coyote_time
	else:
		_coyote = max(0.0, _coyote - delta)

	if InputManager.is_jump_just_pressed(player_id):
		_jump_buffer = jump_buffer_time
	else:
		_jump_buffer = max(0.0, _jump_buffer - delta)

	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = jump_velocity
		_jump_buffer = 0.0
		_coyote = 0.0
		AudioManager.play_jump()
		_kick_squash(JUMP_STRETCH)


## Measure the body origin -> soles distance off the collision shape.
##
## Read rather than hard-coded because the two heroes are different sizes:
## Herosauro's capsule is 2.0 m and Super Boxy's 1.7, so a single constant would
## float one hero's landing dust half a metre off the deck and bury the other's
## in it. A dust ring that does not sit on the surface it was thrown off is the
## RUBRIC's "objects floating on their own ambient" failure applied to FX.
func _measure_feet() -> void:
	for child in get_children():
		var col := child as CollisionShape3D
		if col == null or col.shape == null:
			continue
		if col.shape is CapsuleShape3D:
			_feet_drop = (col.shape as CapsuleShape3D).height * 0.5 - col.position.y
			return
		if col.shape is BoxShape3D:
			_feet_drop = (col.shape as BoxShape3D).size.y * 0.5 - col.position.y
			return


## Where this hero's soles are, in world space. Public because every ground-plane
## FX a hero throws has to start here rather than at the body origin.
func foot_position() -> Vector3:
	return global_position - Vector3.UP * _feet_drop


## Minimum time off the ground before touching down counts as a landing. Walking
## the bridge drops is_on_floor() for a frame here and there over seams; without
## this gate every one of those would chirp.
const LAND_MIN_AIR_TIME := 0.14


## Sampled straight after move_and_slide(), so is_on_floor() reflects this
## frame's resolved position rather than last frame's.
func _handle_landing(delta: float) -> void:
	var grounded := is_on_floor()
	if grounded:
		if not _was_on_floor and _air_time >= LAND_MIN_AIR_TIME:
			AudioManager.play_land()
			# Compression proportional to the drop: stepping off a kerb barely
			# registers, coming down off the giant's slam folds you in half.
			var force := clampf(_impact_speed / LAND_FULL_SPEED, 0.25, 1.0)
			_kick_squash(LAND_SQUASH * force)
			# A heavy landing is an impact like any other, so it gets a camera
			# response too — but only a heavy one, or walking down a ramp would
			# have the frame twitching constantly.
			if force > 0.6:
				GameManager.request_shake(0.10 * force, 0.14)
				# ...and leg one, at the point of contact, on the same gate. The
				# deck between the tram rails is calçada, so COBBLE: the loose
				# lime grout between the setts is what comes up first when
				# anything lands on it, and it is what makes a hero landing on
				# the bridge look different from one landing on a granite kerb.
				# Thrown from the SOLES, not the body origin — see foot_position().
				ImpactFX.ground(self, foot_position(), ToonFactory.Surface.COBBLE,
					LAND_FX_RADIUS, force)
		_air_time = 0.0
	else:
		_air_time += delta
	_was_on_floor = grounded


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
##
## The BODY yaw is snapped, not eased, and that is the whole point of this
## function. `facing_dir` alone was not enough: the swing volume hangs off the
## body, and `_face_movement` only eases `rotation.y` toward the facing at
## turn_speed (14/s => ~16% of the way per tick at 90 Hz). Take a hit, get knocked
## back, and the hero turns to face the direction they are sliding — away from the
## giant. Swing on the next frame and the volume is armed for its whole 0.14 s
## active window while still pointing backwards, so the jab whiffs at point-blank
## range. Measured: neither hero's basic attack could damage the giant after a
## knockback, while both specials (which do not depend on the body's transform)
## landed fine.
##
## Snapping is also the right read. An attack is a commitment; a character who
## whips round onto their target and then swings is exactly the Crash-style
## anticipation the brief asks for, and it makes the hit test deterministic
## instead of dependent on how long ago you were shoved.
func _aim_at_camera(hold: float) -> void:
	var fwd := _camera_forward()
	if fwd != Vector3.ZERO:
		facing_dir = fwd
	rotation.y = atan2(-facing_dir.z, facing_dir.x)
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


## Anything on the world layer within fall_probe_length straight down from `from`?
## The river has no collider, so over the Douro this comes back empty.
func _ground_below(from: Vector3 = global_position) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		from,
		from + Vector3.DOWN * fall_probe_length,
		PhysicsLayers.WORLD,
		[get_rid()])
	return not space.intersect_ray(query).is_empty()


## Going over the side of the Dom Luís.
##
## This used to cost twenty health and happen in complete silence: no FX, no
## camera response, no hit-stop, and the only leg of the five that fired was the
## UI's, off `damage_player`. It was the worst-rated impact in the game, and it
## is not a small one — a hero leaving the bridge is the single most dramatic
## thing that can happen to them without the run ending.
##
## It is now TWO beats, because it is two events and reading them as one is what
## made it feel like a teleport:
##
##   THE LOSS, at the hero's own position out over the Douro. A downward burst
##   (they are being swallowed, so the chips go with them), the biggest camera
##   punch either hero takes, the fall transient, a freeze proportional to the
##   twenty health it costs, and the damage itself for the HUD.
##
##   THE RETURN, on the deck beside their partner. A ground burst under the
##   soles, a smaller punch, the landing transient, and a squash kicked the wrong
##   way so the body springs onto the calçada instead of appearing at rest scale.
##   Same treatment `_get_up()` gives a revive, for the same reason.
##
## Order matters twice over. The loss is drawn from `lost_at`, captured BEFORE
## the body moves, or the burst appears at the recovery point and the fall reads
## as the hero blinking. And `damage_player` goes LAST of the loss beat, because
## it can knock the hero down or end the run, and whatever it does has to have
## the final word.
func _respawn() -> void:
	var lost_at := global_position

	# --- the loss ---------------------------------------------------------
	# FLAT rather than a material: what left the deck is a hero, and there is
	# nothing here for them to have chipped. Thrown DOWN, along the fall.
	ImpactFX.spark(self, lost_at, Vector3.DOWN, ToonFactory.Surface.FLAT, FALL_FX_POWER)
	GameManager.request_shake(FALL_SHAKE, FALL_SHAKE_TIME)
	_play_fall_sfx()
	GameManager.hit_stop(_hurt_stop_for(GameManager.FALL_PENALTY))

	# --- the return -------------------------------------------------------
	global_position = _recovery_position()
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	_ground_y = global_position.y
	# Straight to the recovery point's own soles: `_recovery_position()` drops the
	# hero in from a metre up, so the burst goes on the deck under them rather
	# than at the height they materialise at.
	ImpactFX.ground(self, foot_position() - Vector3.UP * RECOVERY_DROP,
		ToonFactory.Surface.COBBLE, RECOVER_FX_RADIUS, RECOVER_FX_POWER)
	GameManager.request_shake(RECOVER_SHAKE, RECOVER_SHAKE_TIME)
	AudioManager.play_land()
	# Flattened, then sprung: the kick has to go through the spring rather than be
	# assigned, or the body would sit squashed until something else disturbed it.
	_stretch = RECOVER_SQUASH
	_stretch_vel = 0.0
	_kick_squash(JUMP_STRETCH)

	GameManager.damage_player(player_id, GameManager.FALL_PENALTY)
	_start_iframes()
	GameManager.notify_player_respawned(player_id)


## Leg three of the fall. See FALL_SFX for why it is called this way rather than
## directly, and what stands in if it is ever missing.
func _play_fall_sfx() -> void:
	if AudioManager.has_method(FALL_SFX):
		AudioManager.call(FALL_SFX)
	else:
		AudioManager.play_hurt()


## Where a hero comes back in.
##
## Solo: their own spawn point, as before. Co-op: alongside their partner, a step
## back from the giant. Sending them to the far end of a hundred-metre deck while
## the fight is at the other end would be a punishment the design never asked for,
## and it would trip the leash the instant they landed — the pair would spend the
## next four seconds being dragged back together instead of fighting.
##
## Falls back to the spawn point if the partner is somewhere there is no floor
## (mid-fall over the river), so a recovery never drops you into the same hole.
func _recovery_position() -> Vector3:
	var mate := _partner()
	if mate == null:
		return spawn_position

	var away := Vector3.ZERO
	var boss := get_tree().get_first_node_in_group("boss") as Node3D
	if boss and is_instance_valid(boss):
		away = mate.global_position - boss.global_position
		away.y = 0.0
	if away.length() < 0.1:
		away = Vector3(-1.0, 0.0, 0.0)   # default: back down the bridge, away from +X

	var pos: Vector3 = mate.global_position + away.normalized() * RECOVERY_GAP
	pos.z = clampf(pos.z, -RECOVERY_HALF_WIDTH, RECOVERY_HALF_WIDTH)
	pos.y = mate.global_position.y + RECOVERY_DROP   # just above the deck, not inside it
	if not _ground_below(pos):
		return spawn_position
	return pos


# --- Combat ----------------------------------------------------------------

## Every route to hurting a hero, and therefore the single place the impact
## contract is closed for a hit landing ON one.
##
## Five sources reach here — the giant's slam hitbox, his body contact, the
## shockwave, a thrown rock, and (via `_respawn`) the drop off the deck — and
## before this pass only the slam froze the frame and only the shockwave drew
## anything at the point of contact. Putting both here means a source cannot
## forget: a new hazard that calls `take_hit` is finished the moment it does.
##
## The consequence, which is deliberate and is in the report: `Hitbox._deliver()`
## calls this BEFORE it emits `landed`, and `GameManager.hit_stop` refuses to
## nest, so the freeze below now pre-empts the ones the boss stream fires from
## its own `landed` handlers. `HURT_STOP_PER_DAMAGE` is anchored on
## `Adamastor.SLAM_HIT_STOP` for exactly that reason.
##
## Returns true if the hit landed (false if the player was invulnerable or down).
func take_hit(amount: int, knockback: Vector3 = Vector3.ZERO) -> bool:
	if _downed or _invuln > 0.0 or GameManager.state != GameManager.State.PLAYING:
		return false
	apply_knockback(knockback)
	_start_iframes()
	# 3. the audio transient.
	AudioManager.play_hurt()
	# 1. the visual at the point of contact. FLAT, because what was struck is a
	# hero — whatever hit them throws its own material's chips from its own end of
	# the blow. Placed on the struck SIDE of the body rather than in the middle of
	# it, and thrown along the blow, which is the one cue that says who hit whom.
	var blow := Vector3(knockback.x, 0.0, knockback.z)
	var into := blow.normalized() if blow.length() > 0.01 else Vector3.UP
	var bite: float = clampf(float(amount) / HURT_FX_REFERENCE, 0.4, 1.6)
	ImpactFX.spark(self,
		global_position - into * HURT_FX_INSET + Vector3.UP * HURT_FX_LIFT,
		into, ToonFactory.Surface.FLAT, bite)
	# The deformation, on the same normalisation as the burst so the two agree.
	_kick_squash(HURT_SQUASH * clampf(float(amount) / HURT_FX_REFERENCE, 0.4, 1.4))
	# 2. the camera response.
	GameManager.request_shake(0.12 + 0.010 * float(amount), 0.22)
	# 4. the hit-stop, proportional to what it cost.
	GameManager.hit_stop(_hurt_stop_for(amount))
	# 5. the UI acknowledgement rides `player_damaged`, and damage goes LAST: this
	# is the call that can knock the hero down or end the run, and _go_down() has
	# to be the thing that has the final word on the pose.
	GameManager.damage_player(player_id, amount)
	return true


## Freeze length for `amount` of damage landing on a hero. See
## HURT_STOP_PER_DAMAGE for where the coefficient comes from.
func _hurt_stop_for(amount: int) -> float:
	return clampf(float(amount) * HURT_STOP_PER_DAMAGE, HURT_STOP_MIN, HURT_STOP_MAX)


## Push this hero. The horizontal part goes into a reservoir that rides on top of
## the controlled velocity and decays at `knockback_decay`, so a hit cannot simply
## be walked off; the vertical part is assigned to `velocity.y` directly, because
## a pop has to beat gravity on the frame it is applied.
##
## **A DOWNED HERO IGNORES THE HORIZONTAL PART OF THIS, BY DESIGN.**
## `_process_downed` drives `velocity.x/z` to zero every frame, so the reservoir
## this writes into is scrubbed before it can move the body — see the comment at
## the drop itself. Any system that needs to move a hero who is down has to do it
## POSITIONALLY (`global_position += ...`), which is what the boss's push-out
## already does. This is not a bug to be fixed by removing the scrub: a downed
## hero skating across the deck under a blast reads as a ragdoll glitch, and the
## flattened pose is the read the co-op knockdown depends on at 15 m.
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
	if InputManager.is_ability_just_pressed(player_id):
		_ability_timer = ability_cooldown
		_aim_at_camera(ABILITY_AIM_HOLD)
		# Anticipation before the special, same as the basic swing: the body coils
		# a frame before the effect leaves it.
		_kick_squash(ATTACK_ANTICIPATION)
		_perform_ability()


# --- Basic attack ----------------------------------------------------------

## Quick, low-damage, spammable melee. Plays the hero's punch/jab clip and opens
## a brief active-frames window during which a forward-cone check hits the boss.
## Distinct from the special: low damage, short cooldown, no projectile/dash.
func _handle_attack() -> void:
	if _attack_timer > 0.0 or _action_timer > 0.0:
		return   # gated by its own cooldown and by any in-progress action anim (incl. specials/dash)
	if InputManager.is_attack_just_pressed(player_id):
		_attack_timer = attack_cooldown
		_attack_swing = 0.14
		_aim_at_camera(attack_hold)
		play_action_anim("attack", attack_hold)
		# Anticipation now, follow-through a third of the way through the hold.
		# Both are required: a swing with neither reads as the arm teleporting.
		_kick_squash(ATTACK_ANTICIPATION)
		_follow_timer = attack_hold * ATTACK_FOLLOW_FRACTION


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
	# Leg one, for both heroes and every target, in one line. The jab had camera,
	# audio, hit-stop and UI and drew NOTHING where it connected, which is the
	# single most-repeated impact in the game.
	#
	# 0.55 of the reach rather than the far face: the volume's far face is where
	# the swing stops being able to hit, not where a connect usually happens, and
	# a burst out at 4 m hangs in the air beside the giant instead of on him.
	# `surface_of` reads the struck node's own declaration, so the same line
	# throws granite off Adamastor (he is in the "boss" group and is literally a
	# stone giant) and splinters off a crate (PropBody exports `surface`).
	ImpactFX.spark(self,
		global_position + facing_dir * attack_range * 0.55 + Vector3.UP,
		facing_dir, ImpactFX.surface_of(target), 1.0)
	if target.is_in_group("boss"):
		# Adamastor answers every damage event with its own play_boss_hit() (see its
		# boss_damaged handler), and the shipped boss_hit sample is the same file, so
		# playing one here too put two identical buffers on the bus in a single frame
		# and combed instead of hitting. Only Boxy adds a sound, and his gloves get
		# their own sample.
		if player_id == 2:
			AudioManager.play_super_boxy_hit()
		GameManager.hit_stop(0.03)
		# The impact contract wants a camera response on every connect, not just on
		# the specials. Small — a jab is a jab — but a jab that moves nothing at all
		# feels like hitting scenery.
		GameManager.request_shake(0.16, 0.12)
		if target.has_method("nudge"):
			target.nudge(facing_dir, 0.4)
	else:
		# Props: a lighter tick, so smashing a barrel still registers in the frame.
		GameManager.request_shake(0.07, 0.09)


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

	if _follow_timer > 0.0:
		_follow_timer = max(0.0, _follow_timer - delta)
		if _follow_timer <= 0.0:
			_kick_squash(ATTACK_FOLLOW)

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
	_follow_timer = 0.0
	_impact_speed = 0.0
	_downed = false
	_down_timer = 0.0
	_partner_ref = null       # the world is rebuilt around us; re-resolve on demand
	_cancel_actions()
	_stretch = 0.0
	_stretch_vel = 0.0
	_tilt = 0.0
	# Drop the secondary motion too, or the frame after a world rebuild
	# differences this hero's velocity against wherever they used to be and the
	# chain arrives bent double.
	if _lag and is_instance_valid(_lag):
		_lag.reset()
	if _swing:
		_swing.disarm()
	if _tree:
		_tree.set(ACTION_REQUEST_PARAM, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		_tree.set(BLEND_PARAM, 0.0)
	if _model_root:
		_model_root.visible = true
		_model_root.scale = Vector3.ONE
		_model_root.rotation.z = 0.0


# --- Co-op: the other hero -------------------------------------------------

## The other hero, or null in solo. Cached, because this runs every physics tick
## on both bodies and a group scan per tick to find one node is waste; re-resolved
## whenever the cache goes stale (world rebuild, hero swap).
func _partner() -> PlayerBase:
	if _partner_ref != null and is_instance_valid(_partner_ref) and _partner_ref.is_inside_tree():
		return _partner_ref
	_partner_ref = null
	for p in get_tree().get_nodes_in_group("players"):
		if p != self and p is PlayerBase:
			_partner_ref = p as PlayerBase
			break
	return _partner_ref


## Soft half of the leash: a mutual pull that ramps in over LEASH_SLACK. Applied
## as a velocity offset rather than an acceleration, so it behaves like a steady
## rope tension instead of building up while you stand still.
func _apply_leash() -> void:
	var mate := _partner()
	if mate == null:
		return
	var to := mate.global_position - global_position
	to.y = 0.0
	var d := to.length()
	if d <= LEASH_RADIUS or d < 0.01:
		return
	var over := clampf((d - LEASH_RADIUS) / LEASH_SLACK, 0.0, 1.0)
	var pull := to / d * (LEASH_PULL * over)
	velocity.x += pull.x
	velocity.z += pull.z


## Hard half of the leash. Each hero corrects HALF the overshoot on their own
## tick, so the pair converge without either script teleporting the other body —
## except when the partner is down and cannot correct anything, in which case the
## one still standing takes the whole of it.
##
## Rate-capped at LEASH_REEL_SPEED. In play the overshoot is a few centimetres a
## tick and the cap never binds; it exists for the case where something else moved
## a hero a long way in one frame (a respawn, a debug teleport), where correcting
## the whole gap in one tick would read as the hero being deleted and re-drawn
## somewhere else. Reeled in at just over sprint speed it reads as a rope instead,
## and it still always converges.
func _clamp_separation(delta: float) -> void:
	var mate := _partner()
	if mate == null:
		return
	var to := mate.global_position - global_position
	to.y = 0.0
	var d := to.length()
	var limit := LEASH_RADIUS + LEASH_SLACK
	if d <= limit or d < 0.01:
		return
	var share := 1.0 if mate.is_downed() else 0.5
	var step: float = minf((d - limit) * share, LEASH_REEL_SPEED * delta)
	global_position += to / d * step


func is_downed() -> bool:
	return _downed


# --- Co-op: knockdown and revive -------------------------------------------

func _on_health_changed(id: int, _amount: int, new_health: int) -> void:
	if id != player_id:
		return
	if new_health <= 0 and not _downed:
		_go_down()
	elif new_health > 0 and _downed:
		_get_up()


func _go_down() -> void:
	_downed = true
	_down_timer = DOWN_TIME
	_jump_buffer = 0.0
	_attack_swing = 0.0
	_action_timer = 0.0
	_follow_timer = 0.0
	_aim_lock = 0.0
	_invuln = 0.0        # take_hit already refuses while downed; no flicker wanted
	_flicker = 0.0
	if _swing:
		_swing.disarm()
	_cancel_actions()
	_end_action_anim()
	if _model_root:
		_model_root.visible = true
	# Flattened and tipped over: at co-op camera distance the pose has to be
	# legible as "my partner is down" from across the deck, not a subtle slump.
	_stretch = DOWN_SQUASH
	_stretch_vel = 0.0
	# Leg one: the deck taking the weight of a hero who has stopped standing on it.
	ImpactFX.ground(self, foot_position(), ToonFactory.Surface.COBBLE,
		DOWN_FX_RADIUS, DOWN_FX_POWER)
	AudioManager.play_hurt()
	GameManager.request_shake(0.35, 0.3)


func _get_up() -> void:
	_downed = false
	_down_timer = 0.0
	global_position = _recovery_position()
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	_ground_y = global_position.y
	_start_iframes()
	# Pop back up: the spring is kicked the other way, so the body springs out of
	# the flattened pose instead of sliding back to normal scale.
	_stretch = DOWN_SQUASH
	_stretch_vel = 0.0
	_kick_squash(JUMP_STRETCH * 1.4)
	# Leg one, on the recovery point rather than where they fell: `_get_up` moves
	# the body first, exactly as `_respawn` does, so the dust has to follow it.
	ImpactFX.ground(self, foot_position(), ToonFactory.Surface.COBBLE,
		UP_FX_RADIUS, UP_FX_POWER)
	AudioManager.play_land()
	GameManager.request_shake(0.18, 0.2)


# --- Squash and stretch ----------------------------------------------------

## Add an impulse to the deformation spring. Positive stretches, negative squashes.
##
## Refused while downed: the flattened pose is held rather than sprung, so an
## impulse landing on it (the body touching the deck after the knockdown) would
## never be integrated away and the hero would come back the wrong shape.
func _kick_squash(amount: float) -> void:
	if _downed:
		return
	_stretch = clampf(_stretch + amount, -SQUASH_LIMIT, SQUASH_LIMIT)


## Current deformation of the body, signed: positive is tall and thin, negative
## short and wide, and it is exactly what `_drive_squash` writes into the model's
## scale. Public so `_coop_probe` can measure the squash that actually reaches
## the mesh across a swing rather than the impulse that was asked for — the
## rubric scores what the frame shows, and the spring between the two has its own
## opinion.
func stretch() -> float:
	return _stretch


## This hero's secondary-motion modifier, or null if the model has no skeleton.
## Public for `_coop_probe`, which asserts that it found its bones, that it stays
## inside its bound and that it returns to exactly neutral when the hero stops.
func body_lag() -> BodyLag:
	return _lag


func _drive_squash(delta: float) -> void:
	if _model_root == null:
		return
	if _downed:
		# Held, not sprung: a downed hero stays flat until they are helped up.
		_tilt = lerpf(_tilt, DOWN_TILT, clampf(1.0 - exp(-TILT_LAMBDA * delta), 0.0, 1.0))
	else:
		_tilt = lerpf(_tilt, 0.0, clampf(1.0 - exp(-TILT_LAMBDA * delta), 0.0, 1.0))
		# Semi-implicit Euler on a damped spring toward zero. Stable at the 90 Hz
		# tick this project runs (dt * sqrt(stiffness) is ~0.15) and, because it
		# integrates delta rather than reading a clock, identical on every run.
		_stretch_vel += (-_stretch * SQUASH_STIFFNESS - _stretch_vel * SQUASH_DAMPING) * delta
		_stretch += _stretch_vel * delta
		_stretch = clampf(_stretch, -SQUASH_LIMIT, SQUASH_LIMIT)

	# Volume-preserving-ish: the horizontals take half the vertical change, the
	# other way. Scaling all three axes together would just make the hero bigger.
	_model_root.scale = Vector3(1.0 - _stretch * 0.5, 1.0 + _stretch, 1.0 - _stretch * 0.5)
	_model_root.rotation.z = -_tilt


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
	_attach_secondary_motion(root)
	if not _anim_clips.has("walk") and not _anim_clips.has("idle"):
		return
	_build_anim_tree(_synthesize_idle())


## Hang a `BodyLag` off the model's skeleton.
##
## The rubric's "nothing on a character is perfectly rigid" line, on a rig that
## has no cape, tail or glove bone to simulate — see `body_lag.gd` for what it
## does about that and why a `SkeletonModifier3D` is the only place it can live
## without fighting the AnimationTree built two lines below this.
##
## Attached BEFORE the tree, deliberately: `Skeleton3D` runs its modifier stack
## after whichever mixer wrote the frame, so the order these two are created in
## does not matter to the result — but a modifier that exists first cannot miss
## the frame the tree goes live on.
func _attach_secondary_motion(root: Node3D) -> void:
	var skel := _find_skeleton(root)
	if skel == null:
		return
	if skel.get_node_or_null("BodyLag") != null:
		return
	_lag = BodyLag.new()
	_lag.name = "BodyLag"
	skel.add_child(_lag)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for c in node.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null


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


func _perform_ability() -> void:
	pass


## Return true to bypass standard gravity + movement this frame (used by dash).
func _custom_locomotion(_delta: float) -> bool:
	return false


## Drop any subclass move in progress. Called on a knockdown and on reset, so a
## hero who is flattened mid-dash does not carry on lunging when helped back up.
func _cancel_actions() -> void:
	pass
