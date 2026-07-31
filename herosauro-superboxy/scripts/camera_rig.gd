class_name CameraRig
extends Node3D
## CameraRig: the third-person camera, in two modes on one rig.
##
## A damped pivot carrying a yaw/pitch gimbal and a SpringArm3D. The arm sweeps a
## sphere backwards through the world layer, so the camera snaps in whenever the
## deck, a rail wall or a truss would come between it and its subject, then eases
## back out once the way is clear. Also owns pointer capture, screen shake and the
## victory pull-out.
##
## SOLO (one hero in the "players" group)
##   The shipped orbit camera, unchanged: the pivot chases that hero, the player
##   drives yaw and pitch with the mouse or the right stick, and the shoulder
##   offset puts the hero left of centre.
##
## CO-OP (two heroes)
##   ONE shared camera, framing the group — not split-screen. Split-screen halves
##   the resolution devoted to a giant whose whole job is to be enormous, and it
##   throws away the thing that makes couch co-op work, which is that both players
##   are looking at the same picture and can shout about it. Crash's own co-op and
##   every beat-'em-up worth copying share the frame.
##
##   In group mode the camera is AUTOMATIC. It follows the pair's midpoint, aims
##   itself down the line from the pair to the giant, and pulls the arm out as
##   they separate, far enough that both heroes still sit inside the frame with
##   margin (see `_fit_distance`). Manual look is off, because two players cannot
##   both own one orbit and handing it to player 1 makes player 2 a passenger.
##   Movement stays camera-relative, so "forward" means "toward the giant" for
##   both of them, which is exactly the beat-'em-up convention.
##
##   PlayerBase leashes the pair to `PlayerBase.LEASH_RADIUS + LEASH_SLACK`, which
##   is chosen to sit inside what `group_max_distance` can frame. That is the
##   invariant: the leash guarantees the camera is never asked to hold a spread it
##   cannot, so no hero can be pushed off screen. If you raise the leash, raise
##   `group_max_distance` with it.
##
## Node layout (built in _ready, so main.gd only has to `CameraRig.new()`):
##   CameraRig        - damped to the subject / group centre, plus the shake offset
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

# --- Group framing (co-op) -------------------------------------------------

## Pivot height over the pair's midpoint. Higher than the solo eye height: a
## shared shot wants some deck visible under both heroes so the reader can tell
## who is standing where relative to the giant's feet.
@export var group_eye_height: float = 2.0
## Shortest spring the group shot may ask for. Deliberately longer than the solo
## `distance`: with the pair standing shoulder to shoulder the fit alone would
## happily pull in to 5.6 m, and a shared shot that tight has one hero filling
## half the frame and the giant reduced to a pair of legs. A two-player camera
## has three subjects to keep readable, so it starts further out and stays there.
@export var group_min_distance: float = 8.5
## Longest spring the group shot may ask for. Sized against PlayerBase's leash:
## two heroes at the leash limit must still fit, with the padding, inside this.
@export var group_max_distance: float = 16.0
## World-space margin kept around the pair, so neither hero ever sits ON the
## frame edge — being technically on screen and being readable are not the same.
@export var group_padding: float = 3.0
## Pitch at the closest group framing and at full pull-out. It tips further down
## as the pair spreads, because a wide shot with a level camera fills the top half
## of the frame with sky and pushes both heroes onto the bottom edge.
##
## Steeper than the solo camera's -11, and note which way that cuts: tilting DOWN
## raises ground-level subjects toward the middle of the frame, because the view
## axis rotates toward them faster than they fall away from it.
##
## It buys less than you would expect. _coop_probe measures the worst-case margin
## from any hero's head or feet to any frame edge, and going -14 -> -18 moved it
## from 0.140 to 0.143 of the frame — the binding edge at spawn is not the bottom.
## Kept at -18 anyway because a group shot wants deck under the pair rather than
## sky over them, and the probe confirms the giant's head still clears the top,
## which is the constraint pulling the other way.
##
## The framing win at spawn was `group_min_distance`, not the pitch: the fit alone
## was asking for 5.75 m, and at that range the nearer hero really did fill the
## bottom of the frame.
@export var group_pitch_deg: float = -18.0
@export var group_pitch_far_deg: float = -25.0
## How fast the automatic yaw swings onto the giant. Slow on purpose: yaw is the
## basis for camera-relative movement, so a camera that whips around also whips
## the direction "forward" means out from under both players' thumbs.
@export var group_yaw_lambda: float = 2.6
## Follow rate for the pair's midpoint. Slower than the solo follow because the
## midpoint moves whenever EITHER hero moves, and at the solo rate that reads as
## the camera being shoved about by your partner.
@export var group_follow_lambda: float = 8.0

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

## Hero the rig frames in SOLO. main.gd assigns it before adding the rig to the
## tree; if it ever goes stale we fall back to the first node in the "players"
## group. Ignored in co-op, where the group is the subject.
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
var _group_distance: float = 0.0          # spring length the group fit is asking for
var _group_mode: bool = false             # cached each tick; drives pointer capture

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
	_group_distance = distance
	_snap_to_subject()

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
	var heroes := _heroes()
	var was_group := _group_mode
	_group_mode = heroes.size() > 1
	if _group_mode != was_group:
		# Solo <-> co-op only flips on a world rebuild, but if it does, re-grab or
		# release the pointer rather than leaving it in the previous mode's state.
		_apply_mouse_mode()

	_update_shake(delta)

	if _group_mode:
		_update_group(heroes, delta)
	else:
		_update_solo(heroes, delta)

	global_position = _focus + _shake_offset
	_yaw_node.rotation.y = _yaw
	_pitch_node.rotation.x = _pitch

	_dist_extra = lerpf(_dist_extra, _dist_extra_target, _damp(extend_lambda, delta))
	_update_arm(delta)

	# Applied here rather than as a position offset: SpringArm3D overwrites the
	# origin of every direct child each tick, so a translated Camera3D is wiped.
	camera.rotation = Vector3(0.0, 0.0, _shake_roll)


## Solo: the shipped orbit camera. Player-driven yaw/pitch, over-the-shoulder.
func _update_solo(heroes: Array[Node3D], delta: float) -> void:
	var hero := _resolve_target(heroes)
	_apply_look(delta)
	if hero:
		_focus = _focus.lerp(hero.global_position, _damp(follow_lambda, delta))
	_pitch_node.position = Vector3(_usable_shoulder(hero), eye_height, 0.0)
	_group_distance = distance


## Co-op: follow the midpoint, aim at the giant, open the arm to fit the pair.
func _update_group(heroes: Array[Node3D], delta: float) -> void:
	# Mouse motion keeps arriving even though nothing consumes it here; drop it so
	# a mode flip back to solo does not apply a frame's worth of banked spin.
	_look_accum = Vector2.ZERO

	var centre := _centroid(heroes)
	_focus = _focus.lerp(centre, _damp(group_follow_lambda, delta))
	_pitch_node.position = Vector3(0.0, group_eye_height, 0.0)

	# Yaw: look down the line from the pair to the giant, so he is centred and
	# "forward" means "toward the fight" for both players. With no giant (he is
	# dead, or the world is still assembling) hold whatever yaw we had.
	var boss := get_tree().get_first_node_in_group("boss") as Node3D
	if boss and is_instance_valid(boss):
		var to := boss.global_position - centre
		to.y = 0.0
		if to.length() > 1.0:
			# atan2(-x, -z): the rig looks along its own -Z, so this is the yaw that
			# puts `to` straight ahead. Matches _snap_to_subject.
			var want := atan2(-to.x, -to.z)
			_yaw = lerp_angle(_yaw, want, _damp(group_yaw_lambda, delta))
			_yaw = wrapf(_yaw, -PI, PI)

	_group_distance = _fit_distance(heroes, centre)
	var span := maxf(0.001, group_max_distance - group_min_distance)
	var openness := clampf((_group_distance - group_min_distance) / span, 0.0, 1.0)
	var want_pitch := deg_to_rad(lerpf(group_pitch_deg, group_pitch_far_deg, openness))
	_pitch = lerpf(_pitch, want_pitch, _damp(extend_lambda, delta))


## Spring length at which every hero still sits inside the frame with
## `group_padding` to spare.
##
## Two extents matter and they are not the same axis. `half_w` is the pair's
## spread ACROSS the view, which the horizontal field of view has to cover;
## `behind` is how far the rearmost hero is on the camera's side of the midpoint,
## which is simply added to the distance because it is depth, not angle.
##
## The horizontal half-angle is derived from the vertical one and the live
## viewport aspect, not assumed: Camera3D keeps height by default, so a 16:10 or
## an ultrawide window has a different horizontal FOV for the same `fov`, and
## hard-coding 16:9 would push a hero off the side of a 4:3 window.
func _fit_distance(heroes: Array[Node3D], centre: Vector3) -> float:
	var basis := Basis(Vector3.UP, _yaw)
	var right := basis.x
	var fwd := -basis.z

	var half_w := 0.0
	var behind := 0.0
	for h in heroes:
		var d := h.global_position - centre
		half_w = maxf(half_w, absf(d.dot(right)))
		behind = maxf(behind, -d.dot(fwd))

	var v_half := deg_to_rad(camera.fov) * 0.5
	var vp := get_viewport().get_visible_rect().size
	var aspect: float = maxf(0.1, vp.x / maxf(1.0, vp.y))
	var h_half := atan(tan(v_half) * aspect)

	var need := (half_w + group_padding) / maxf(0.05, tan(h_half)) + behind
	return clampf(need, group_min_distance, group_max_distance)


func _centroid(heroes: Array[Node3D]) -> Vector3:
	var sum := Vector3.ZERO
	for h in heroes:
		sum += h.global_position
	return sum / float(maxi(1, heroes.size()))


## Shoulder offset, faded out as the hero nears a parapet. Solo only — the group
## shot is centred, because sliding a two-hero frame off-centre just moves the
## problem of who is closer to the edge from one player to the other.
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
func _usable_shoulder(subject: Node3D) -> float:
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
	var want := _group_distance + _dist_extra
	var hit := _arm.get_hit_length()
	if hit > 0.001 and hit < _arm.spring_length - 0.001:
		_arm_length = hit          # obstruction: no easing, or the camera clips through it
	else:
		_arm_length = lerpf(_arm_length, want, _damp(extend_lambda, delta))
	_arm.spring_length = clampf(_arm_length, probe_radius + probe_margin, want)
	_arm_length = _arm.spring_length


func _apply_look(delta: float) -> void:
	# Both sources arrive as (+x = turn right, +y = look up). In solo the human may
	# be driving either hero, so the look axes come from whichever slot they hold.
	var look := InputManager.get_look_vector(InputManager.solo_slot()) * stick_sensitivity * delta
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

## Every live hero, in a stable order. Sorted by player_id rather than by tree
## order so the centroid and the fit are the same however main.gd spawned them.
func _heroes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for p in get_tree().get_nodes_in_group("players"):
		if p is Node3D and is_instance_valid(p):
			out.append(p as Node3D)
	out.sort_custom(func(a: Node3D, b: Node3D) -> bool: return _pid(a) < _pid(b))
	return out


func _pid(n: Node) -> int:
	return int(n.player_id) if "player_id" in n else 0


## True while the rig is framing a group rather than orbiting one hero. Public so
## a probe can assert the mode as well as the result, and so UI can tell whether
## the pointer is captured without duplicating the rule.
func is_group_framing() -> bool:
	return _group_mode


func _resolve_target(heroes: Array[Node3D]) -> Node3D:
	if target and is_instance_valid(target):
		return target
	target = heroes[0] if not heroes.is_empty() else null
	return target


## Jump straight to the framing we want at the start of a fight: sat behind the
## subject, looking down the line towards the giant.
func _snap_to_subject() -> void:
	var heroes := _heroes()
	_group_mode = heroes.size() > 1
	var centre := _centroid(heroes) if not heroes.is_empty() else _focus
	if not _group_mode:
		var hero := _resolve_target(heroes)
		if hero:
			centre = hero.global_position
	_focus = centre

	var aim := Vector3(1.0, 0.0, 0.0)   # the bridge runs along X; the giant waits at +X
	var boss := get_tree().get_first_node_in_group("boss")
	if not heroes.is_empty() and boss and is_instance_valid(boss):
		var to: Vector3 = (boss as Node3D).global_position - centre
		to.y = 0.0
		if to.length() > 0.5:
			aim = to.normalized()
	_yaw = atan2(-aim.x, -aim.z)

	if _group_mode:
		_pitch = deg_to_rad(group_pitch_deg)
		_group_distance = _fit_distance(heroes, centre)
	else:
		_pitch = deg_to_rad(start_pitch_deg)
		_group_distance = distance
	_arm_length = _group_distance
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


## Pointer capture is a SOLO affair. The co-op camera takes no mouse look, and
## trapping the pointer for a pair sharing a keyboard buys nothing and costs them
## the ability to alt-tab or click anything.
func _apply_mouse_mode() -> void:
	_set_mouse_captured(GameManager.state == GameManager.State.PLAYING and not _group_mode)


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
	_snap_to_subject()
	_apply_mouse_mode()


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
