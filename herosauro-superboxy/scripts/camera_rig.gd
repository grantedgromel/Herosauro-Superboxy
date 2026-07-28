class_name CameraRig
extends Node3D
## CameraRig: the solo third-person orbit camera.
##
## A damped pivot that chases the hero, carrying a yaw/pitch gimbal and a
## SpringArm3D. The arm sweeps a sphere backwards through the world layer, so the
## camera snaps in whenever the deck, a rail wall or a truss would come between it
## and the hero, then eases back out once the way is clear. Also owns pointer
## capture, screen shake and the victory pull-out.
##
## Node layout (built in _ready, so main.gd only has to `CameraRig.new()`):
##   CameraRig        - damped to the hero's position, plus the shake offset
##   └ Yaw            - rotation.y = orbit yaw
##     └ Pitch        - shoulder + eye-height offset, rotation.x = orbit pitch
##       └ Arm        - SpringArm3D; shortens on contact
##         └ Camera3D - the active camera; carries only the shake roll

# --- Framing ---------------------------------------------------------------

@export var fov: float = 62.0                  # wide enough to read the giant without fisheye
@export var distance: float = 5.6              # spring length with nothing in the way
@export var eye_height: float = 1.15           # pivot above the hero's origin (~just over the head)
@export var shoulder_offset: float = 0.7       # slide the pivot right so the hero sits left of centre
@export var probe_radius: float = 0.3          # sphere the arm sweeps: corners can't pop through it
@export var probe_margin: float = 0.14         # standoff from whatever the arm hit
## World geometry only. The giant deliberately stays out of this mask: letting a
## 9u boss shove the camera makes the shot unreadable exactly when it matters.
@export_flags_3d_physics var probe_mask: int = 1

# --- Feel ------------------------------------------------------------------

@export var follow_lambda: float = 16.0        # exponential follow rate (framerate independent)
@export var extend_lambda: float = 7.0         # how fast the arm eases back out after an obstruction
@export var mouse_sensitivity: float = 0.0023  # radians per pixel of mouse motion
@export var stick_sensitivity: float = 2.9     # radians/second at full right-stick deflection
@export var invert_pitch: bool = false
@export var min_pitch_deg: float = -58.0       # high and looking down at the hero
@export var max_pitch_deg: float = 26.0        # low and looking up past him at the giant
@export var start_pitch_deg: float = -11.0

# --- Victory / shake -------------------------------------------------------

@export var victory_pullout: float = 9.0       # extra spring length for the winning pose
@export var shake_roll: float = 0.45           # radians of camera roll per unit of shake strength

const SHAKE_SEED := 0x5CA1E   # fixed so a given fight shakes identically every run

## Hero the rig frames. main.gd assigns it before adding the rig to the tree;
## if it ever goes stale we fall back to the first node in the "players" group.
var target: Node3D = null
var camera: Camera3D

var _yaw_node: Node3D
var _pitch_node: Node3D
var _arm: SpringArm3D

var _yaw: float = 0.0
var _pitch: float = 0.0
var _focus: Vector3 = Vector3(0.0, 2.0, 0.0)
var _arm_length: float = 0.0
var _dist_extra: float = 0.0
var _dist_extra_target: float = 0.0
var _look_accum: Vector2 = Vector2.ZERO   # mouse motion banked between physics ticks

var _shake_strength: float = 0.0
var _shake_time: float = 0.0
var _shake_total: float = 0.0
var _shake_offset: Vector3 = Vector3.ZERO
var _shake_roll: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("camera_rig")
	_rng.seed = SHAKE_SEED
	_build_nodes()
	_pitch = deg_to_rad(start_pitch_deg)
	_arm_length = distance
	_snap_to_target()

	GameManager.camera_shake_requested.connect(_on_shake_requested)
	GameManager.game_over.connect(_on_game_over)
	GameManager.game_started.connect(_on_game_started)
	GameManager.state_changed.connect(_on_state_changed)
	_apply_mouse_mode()


func _exit_tree() -> void:
	# The rig is torn down with the world; never leave the pointer trapped.
	_set_mouse_captured(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_set_mouse_captured(false)


# --- Per-tick update -------------------------------------------------------

## Runs on the physics tick, not the frame: SpringArm3D resolves its cast during
## internal physics processing, so driving the pivot from _process would leave the
## camera position and the arm a full tick out of step with each other.
func _physics_process(delta: float) -> void:
	var hero := _resolve_target()

	_apply_look(delta)
	_update_shake(delta)

	if hero:
		_focus = _focus.lerp(hero.global_position, _damp(follow_lambda, delta))
	global_position = _focus + _shake_offset

	_yaw_node.rotation.y = _yaw
	_pitch_node.rotation.x = _pitch
	_pitch_node.position = Vector3(_usable_shoulder(), eye_height, 0.0)

	_dist_extra = lerpf(_dist_extra, _dist_extra_target, _damp(extend_lambda, delta))
	_update_arm(delta)

	# Applied here rather than as a position offset: SpringArm3D overwrites the
	# origin of every direct child each tick, so a translated Camera3D is wiped.
	camera.rotation = Vector3(0.0, 0.0, _shake_roll)


## Shoulder offset, faded out as the hero nears a parapet.
##
## The offset is applied in yaw-local space, so with the hero facing along the
## bridge it slides the pivot sideways in world Z — straight into the parapet.
## Standing at the river edge (z = 6.10, where the collider stops the capsule) a
## flat 0.7 put the pivot at z = 6.80, which is *inside* the parapet's own plan
## footprint of 6.55–7.00 and just above its top. Two visible consequences: the
## railing collapsed to a stripe and the deck read as an unguarded ledge, and the
## arm's probe sphere passed within 25 mm of every lamppost collider on that side
## and slammed the camera into the hero's back at each one.
##
## Fading the offset toward zero over the last metre keeps the over-the-shoulder
## framing everywhere it is safe and degrades to a centred shot exactly where it
## is not.
func _usable_shoulder() -> float:
	var subject := _resolve_target()
	if subject == null:
		return shoulder_offset
	var margin := SAFE_HALF_WIDTH - absf(subject.global_position.z)
	if margin >= shoulder_offset + 0.35:
		return shoulder_offset
	return clampf(margin - 0.35, 0.0, shoulder_offset)


## Half-width of the deck the pivot may occupy: the footway's outer edge, inside
## the parapet. Matches BridgeArena.WALKWAY_OUTER.
const SAFE_HALF_WIDTH := 6.55


## Pull in the instant something blocks the shot, ease back out once it clears.
## `hit` is last tick's resolved length; 0 means the arm has not cast yet.
func _update_arm(delta: float) -> void:
	var want := distance + _dist_extra
	var hit := _arm.get_hit_length()
	if hit > 0.001 and hit < _arm.spring_length - 0.001:
		_arm_length = hit          # obstruction: no easing, or the camera clips through it
	else:
		_arm_length = lerpf(_arm_length, want, _damp(extend_lambda, delta))
	_arm.spring_length = clampf(_arm_length, probe_radius + probe_margin, want)
	_arm_length = _arm.spring_length


func _apply_look(delta: float) -> void:
	# Both sources arrive as (+x = turn right, +y = look up).
	var look := _target_look() * stick_sensitivity * delta
	look += _look_accum * mouse_sensitivity
	_look_accum = Vector2.ZERO

	_yaw -= look.x
	_yaw = wrapf(_yaw, -PI, PI)
	_pitch += -look.y if invert_pitch else look.y
	_pitch = clampf(_pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))


func _update_shake(delta: float) -> void:
	if _shake_time <= 0.0:
		_shake_offset = Vector3.ZERO
		_shake_roll = 0.0
		_shake_strength = 0.0
		return
	_shake_time = maxf(0.0, _shake_time - delta)
	var k: float = _shake_strength * (_shake_time / maxf(0.0001, _shake_total))
	_shake_offset = Vector3(_rng.randf_range(-k, k), _rng.randf_range(-k, k), _rng.randf_range(-k, k))
	_shake_roll = _rng.randf_range(-k, k) * shake_roll


# --- Targeting -------------------------------------------------------------

func _resolve_target() -> Node3D:
	if target and is_instance_valid(target):
		return target
	target = get_tree().get_first_node_in_group("players") as Node3D
	return target


## Look input from whoever is driving the hero this rig is following, rather
## than from a global. Identical to reading the autoload while there is one
## hero; the difference is that a second hero on a second action set orbits his
## own camera instead of fighting over this one.
##
## Falls back to neutral rather than to the global: a rig pointed at something
## that is not a PlayerBase has no player whose look this could be.
func _target_look() -> Vector2:
	var hero := _resolve_target() as PlayerBase
	if hero == null or hero.input == null:
		return Vector2.ZERO
	return hero.input.get_look_vector()


## Jump straight to the framing we want at the start of a fight: sat behind the
## hero, looking down the line towards the giant.
func _snap_to_target() -> void:
	var hero := _resolve_target()
	if hero:
		_focus = hero.global_position
	var aim := Vector3(1.0, 0.0, 0.0)   # the bridge runs along X; the giant waits at +X
	var boss := get_tree().get_first_node_in_group("boss")
	if hero and boss and is_instance_valid(boss):
		var to: Vector3 = (boss as Node3D).global_position - hero.global_position
		to.y = 0.0
		if to.length() > 0.5:
			aim = to.normalized()
	_yaw = atan2(-aim.x, -aim.z)
	_pitch = deg_to_rad(start_pitch_deg)
	_arm_length = distance
	global_position = _focus


# --- Mouse capture ---------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var motion := event as InputEventMouseMotion
			# Screen-space Y grows downward; flip it so +y always means "look up".
			_look_accum += Vector2(motion.relative.x, -motion.relative.y)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		# Re-grab after an alt-tab (and on web, where the lock needs a user gesture).
		_apply_mouse_mode()
	elif event.is_action_pressed("ui_cancel"):
		# main.gd pauses on the same key; hand the pointer back for the overlay.
		_set_mouse_captured(false)


func _apply_mouse_mode() -> void:
	_set_mouse_captured(GameManager.state == GameManager.State.PLAYING)


func _set_mouse_captured(captured: bool) -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_MOUSE):
		return   # headless / CI: there is no pointer to capture
	var want := Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != want:
		Input.mouse_mode = want


# --- GameManager hooks -----------------------------------------------------

func _on_state_changed(_new_state: int) -> void:
	_apply_mouse_mode()


func _on_shake_requested(strength: float, duration: float) -> void:
	_shake_strength = maxf(_shake_strength, strength)
	_shake_time = duration
	_shake_total = duration


func _on_game_over(victory: bool) -> void:
	if victory:
		_dist_extra_target = victory_pullout


func _on_game_started() -> void:
	_dist_extra = 0.0
	_dist_extra_target = 0.0
	_shake_time = 0.0
	_look_accum = Vector2.ZERO
	_snap_to_target()


# --- Construction ----------------------------------------------------------

func _build_nodes() -> void:
	_yaw_node = Node3D.new()
	_yaw_node.name = "Yaw"
	add_child(_yaw_node)

	_pitch_node = Node3D.new()
	_pitch_node.name = "Pitch"
	_yaw_node.add_child(_pitch_node)

	var probe := SphereShape3D.new()
	probe.radius = probe_radius

	_arm = SpringArm3D.new()
	_arm.name = "Arm"
	_arm.shape = probe
	_arm.margin = probe_margin
	_arm.collision_mask = probe_mask
	_arm.spring_length = distance
	_pitch_node.add_child(_arm)

	camera = get_node_or_null("Camera3D")
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
	elif camera.get_parent():
		camera.get_parent().remove_child(camera)
	_arm.add_child(camera)
	camera.fov = fov
	camera.current = true


# --- Helpers ---------------------------------------------------------------

## Framerate-independent lerp weight for an exponential decay of rate `lambda`.
func _damp(lambda: float, delta: float) -> float:
	return 1.0 - exp(-lambda * delta)
