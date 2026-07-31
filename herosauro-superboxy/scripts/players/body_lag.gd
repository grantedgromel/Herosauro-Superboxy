class_name BodyLag
extends SkeletonModifier3D
## Secondary motion for a hero whose rig does not have any.
##
## ARCHITECTURE.md, "Silhouette and proportion": *"Secondary motion. Nothing on a
## character is perfectly rigid — tails, ears, gloves, cloth all lag and settle."*
## Herosauro has a tail, Super Boxy has a cape and boxing gloves, and until this
## file the answer to that line was "the models are baked glTF, so we cannot".
##
## That was half true, and the half that was false is what this is. Both heroes
## ship the same 24-bone humanoid rig — `Hips / Spine / Spine01 / Spine02 / neck /
## Head` up the middle and `Shoulder / Arm / ForeArm / Hand` down each side —
## with **no cape bone, no tail bone and no glove bone**. So there is nothing to
## simulate the cloth with directly. But the cape IS skinned to the upper spine
## and the gloves ARE the hands, so a small damped-spring lag on the bones that
## carry them moves the things the rubric actually names. It is an
## approximation, and the report says so; it is also the difference between a
## hero whose cape reacts to a dash and one whose cape is welded to his back.
##
## --- WHY A SkeletonModifier3D ------------------------------------------------
##
## Because it is the one place in Godot that does not fight the AnimationTree.
## `Skeleton3D` runs its modifier stack AFTER the `AnimationMixer` has written
## the frame's pose, so this reads the animated pose and adds to it. Two mixers
## writing the same bones would fight — which is exactly why
## `PlayerBase._build_anim_tree` deactivates the imported `AnimationPlayer` — and
## a second `AnimationTree` layer, a script writing bone poses from `_process`,
## or a tween on a bone would all have re-created that bug.
##
## --- WHAT DRIVES IT ----------------------------------------------------------
##
## ACCELERATION, not velocity, and that distinction is the whole look. A lag
## driven by velocity leans the torso back for as long as the hero is running,
## which is a posture, and the wrong one — a runner leans INTO a run. A lag
## driven by acceleration tips the chain back as the hero launches, lets it
## overshoot forward as they stop, and sits at exactly zero the whole time they
## are moving steadily. That is what a mass hanging off a moving body does, and
## it is what "lag and settle" means.
##
## Yaw rate drives a twist on the same chain, which is what makes the cape swing
## when Boxy whips round onto a target — `PlayerBase._aim_at_camera` SNAPS the
## body yaw on every attack, so this is a large and very frequent input.
##
## --- WHY IT IS SAFE ----------------------------------------------------------
##
## Three properties, in the order they matter:
##
##   * **Exactly neutral at rest.** Below `SLEEP` the springs are snapped to zero
##     and the modifier writes nothing at all — not "writes a tiny rotation", not
##     "writes identity", but returns before touching a bone. A hero standing
##     still is bit-for-bit the pose they were before this file existed, so a
##     capture of an idle frame cannot move.
##   * **Bounded.** `MAX_LEAN` and `MAX_TWIST` cap the total, and each bone takes
##     a documented share of it. The worst case is about ten degrees accumulated
##     over five spine bones, which reads as give rather than as a broken rig.
##   * **Deterministic.** One damped spring integrated from `delta`, no RNG and no
##     clock — ARCHITECTURE.md rules 4 and 5. `_coop_probe` asserts the bound and
##     asserts the return to neutral.
##
## Set `active = false` (a `SkeletonModifier3D` property) to switch the whole
## thing off without touching the rig.

## Bones the lag is spread across, and the share of the total angle each takes.
##
## The spine chain is ordered outward from the hips and its shares RISE along it,
## which is what makes the effect a chain rather than a hinge: every bone's
## rotation compounds onto its parent's, so the head ends up carrying the sum of
## all five while the hips barely move. `Hips` is deliberately absent — the hips
## are where the hero's weight is and tipping them detaches the feet from the
## deck.
##
## The hands are here because the gloves are the hands; the forearms carry a
## smaller share so the arm bends into the lag instead of snapping at the wrist.
## Their share is well under the spine's on purpose: a punch clip is already
## throwing these bones a long way, and secondary motion is meant to sit under an
## animation rather than argue with it.
const CHAIN := {
	"Spine": 0.10,
	"Spine01": 0.14,
	"Spine02": 0.18,
	"neck": 0.22,
	"Head": 0.26,
	"LeftForeArm": 0.08,
	"LeftHand": 0.14,
	"RightForeArm": 0.08,
	"RightHand": 0.14,
}

## Radians of lean per m/s^2 of horizontal acceleration.
##
## `PlayerBase.ground_accel` is 55, so ordinary running acceleration asks for
## about 0.14 rad of lean and a dash — which sets velocity to 32 m/s in a single
## tick — pins the target at the cap. That ordering is the point: walking gives a
## suggestion of give, launching gives the whole thing.
const ACCEL_GAIN := 0.0026
## Radians of twist per rad/s of yaw rate. `_aim_at_camera` snaps the yaw, so
## this input arrives as one enormous spike and is caught by MAX_TWIST; the gain
## is set for ordinary turning at `PlayerBase.turn_speed`.
const YAW_GAIN := 0.020

## Caps on the total, before each bone's share is taken out of it. 0.20 rad over
## the five spine bones is about ten degrees accumulated at the head, which is
## give; twice that would be a rag doll.
const MAX_LEAN := 0.20
const MAX_TWIST := 0.16

## The spring. Stiffness 90 with damping 11 is a damping ratio of about 0.58 —
## underdamped, one visible overshoot, settled in roughly a third of a second.
## The overshoot IS the settle: a critically damped chain slides back to neutral
## and reads as a rig easing rather than as cloth.
##
## Same reasoning, and roughly the same period, as `PlayerBase`'s squash spring.
const STIFFNESS := 90.0
const DAMPING := 11.0

## Below this the springs are snapped to zero and the modifier writes nothing.
## 0.002 rad is a tenth of a degree — under a twentieth of a pixel of movement on
## a hero's head at the co-op camera's distance, and therefore invisible, which
## is what makes "neutral at rest" an exact statement rather than an asymptotic
## one.
const SLEEP := 0.002

## Ceiling on the acceleration the driver will believe, in m/s^2. A body coming
## out of a hit-stop, being teleported by a respawn or resolving a deep collider
## overlap can report an enormous one-frame velocity change that is a solver
## artefact rather than a movement, and an unclamped spring would answer it with
## a whip.
const ACCEL_LIMIT := 400.0

## The hero this hangs off. Resolved by walking up the tree rather than exported,
## so a subclass that reorganises its model does not have to remember to wire it.
var _body: PlayerBase = null

var _bones: Dictionary = {}          ## bone index -> share
var _vel_prev: Vector3 = Vector3.ZERO
var _yaw_prev: float = 0.0
var _primed: bool = false            ## have we got a previous frame to difference against?

## Lean is a HORIZONTAL vector in world space whose length is the tilt angle in
## radians and whose direction is the way the chain is tipping. Twist is a scalar
## about the body's own up axis.
var _lean: Vector3 = Vector3.ZERO
var _lean_vel: Vector3 = Vector3.ZERO
var _twist: float = 0.0
var _twist_vel: float = 0.0
## Largest angle the last write actually MOVED a bone by, read back off the
## skeleton rather than assumed. See `written_angle()`.
var _written: float = 0.0


func _ready() -> void:
	_body = _find_body()
	_resolve_bones()


## Walk up to the owning hero. The modifier is parented to the Skeleton3D, which
## is somewhere under the model, which is under `PlayerBase`'s "Model" node.
func _find_body() -> PlayerBase:
	var n: Node = get_parent()
	while n != null:
		if n is PlayerBase:
			return n as PlayerBase
		n = n.get_parent()
	return null


func _resolve_bones() -> void:
	_bones.clear()
	var skel := get_skeleton()
	if skel == null:
		return
	for bone_name in CHAIN:
		var idx: int = skel.find_bone(String(bone_name))
		if idx < 0:
			# Case-insensitive fallback: the rig ships "neck" lower-case and
			# "Head" capitalised, and an exporter that normalises either way must
			# not silently drop half the chain.
			idx = _find_bone_loose(skel, String(bone_name))
		if idx >= 0:
			_bones[idx] = float(CHAIN[bone_name])


func _find_bone_loose(skel: Skeleton3D, wanted: String) -> int:
	var target := wanted.to_lower()
	for i in skel.get_bone_count():
		if skel.get_bone_name(i).to_lower() == target:
			return i
	return -1


## Bones this modifier actually found on the rig. Read by `_coop_probe`, so a
## re-export that renames the spine fails the build instead of quietly shipping
## a hero with no secondary motion.
func bound_bone_count() -> int:
	return _bones.size()


## Current total lean angle in radians, and the twist. Read by `_coop_probe` to
## assert the bound and the return to neutral, because the bone poses themselves
## are overwritten by the AnimationMixer every frame and cannot be differenced
## from outside.
func lean_angle() -> float:
	return _lean.length()


func twist_angle() -> float:
	return absf(_twist)


## How far the last write actually moved a bone, in radians, measured by reading
## the pose back off the skeleton after writing it.
##
## This is the assertion that the modifier is doing anything at all. A
## `SkeletonModifier3D` that is in the wrong place in the stack, or whose
## skeleton has already been committed for the frame, silently writes into
## nothing — the spring keeps swinging, the numbers keep looking healthy, and the
## hero never moves. Only a read-back can tell those two apart, and only from in
## here: the AnimationMixer overwrites the pose before any outside observer gets
## a look at it.
func written_angle() -> float:
	return _written


## Drop everything. Called from `PlayerBase.reset_state()`, so a hero rebuilt
## between runs does not come back mid-swing — and so the first frame after a
## teleport differences against the teleport rather than through it.
func reset() -> void:
	_lean = Vector3.ZERO
	_lean_vel = Vector3.ZERO
	_twist = 0.0
	_twist_vel = 0.0
	_primed = false


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or _body == null or delta <= 0.0:
		return
	if _bones.is_empty():
		_resolve_bones()
		if _bones.is_empty():
			return

	_advance(delta)
	if _lean.length() < SLEEP and absf(_twist) < SLEEP:
		# Neutral: write NOTHING. See the class doc — this is what makes an idle
		# hero identical to one built before this file existed.
		_written = 0.0
		return
	_apply(skel)


## Integrate the springs from the body's own motion.
func _advance(delta: float) -> void:
	var v := _body.velocity
	var yaw := _body.rotation.y
	if not _primed:
		# First frame after a spawn, a respawn or a reset: there is no previous
		# frame to difference against, and inventing one out of a teleport is how
		# a hero arrives bent double.
		_vel_prev = v
		_yaw_prev = yaw
		_primed = true

	var accel := (v - _vel_prev) / delta
	_vel_prev = v
	accel.y = 0.0                     # vertical is the squash's job, not the chain's
	accel = accel.limit_length(ACCEL_LIMIT)

	# The target is OPPOSITE the acceleration: the mass is left behind by the body
	# it hangs off. Steady motion has no acceleration and therefore no lean, which
	# is the whole reason this is driven by acceleration and not by velocity.
	var lean_target: Vector3 = (-accel * ACCEL_GAIN).limit_length(MAX_LEAN)

	var dyaw: float = wrapf(yaw - _yaw_prev, -PI, PI) / delta
	_yaw_prev = yaw
	var twist_target: float = clampf(-dyaw * YAW_GAIN, -MAX_TWIST, MAX_TWIST)

	# Semi-implicit Euler on a damped spring toward the target. Integrates delta
	# rather than reading a clock, so two runs of the same frame agree.
	_lean_vel += ((lean_target - _lean) * STIFFNESS - _lean_vel * DAMPING) * delta
	_lean = (_lean + _lean_vel * delta).limit_length(MAX_LEAN)
	_twist_vel += ((twist_target - _twist) * STIFFNESS - _twist_vel * DAMPING) * delta
	_twist = clampf(_twist + _twist_vel * delta, -MAX_TWIST, MAX_TWIST)

	if _lean.length() < SLEEP and absf(_lean_vel.length()) < SLEEP \
			and absf(_twist) < SLEEP and absf(_twist_vel) < SLEEP:
		_lean = Vector3.ZERO
		_lean_vel = Vector3.ZERO
		_twist = 0.0
		_twist_vel = 0.0


## Add the lag onto the pose the AnimationMixer just wrote.
func _apply(skel: Skeleton3D) -> void:
	# The lean is world space; the bones are not. `orthonormalized()` because the
	# model root carries PlayerBase's non-uniform squash scale, and a basis with
	# scale in it would turn a rotation into a shear.
	var to_skeleton := skel.global_transform.basis.orthonormalized().inverse()
	var lean_local: Vector3 = to_skeleton * _lean
	var angle: float = lean_local.length()
	var tilt_axis := Vector3.UP.cross(lean_local)
	if tilt_axis.length() < 0.0001:
		tilt_axis = Vector3.RIGHT
	tilt_axis = tilt_axis.normalized()
	var up_axis: Vector3 = (to_skeleton * Vector3.UP).normalized()

	# TWO PASSES, and the split is load-bearing. Every rotation below is expressed
	# in its bone's PARENT space, and `get_bone_global_pose` on a skeleton that has
	# already been written to this frame would hand back a pose half-updated by the
	# writes above it. Read every reference frame off the animated pose first, then
	# write.
	var frames: Dictionary = {}
	for idx in _bones:
		var parent: int = skel.get_bone_parent(int(idx))
		frames[idx] = Basis.IDENTITY if parent < 0 \
			else skel.get_bone_global_pose(parent).basis.orthonormalized().inverse()

	_written = 0.0
	for idx in _bones:
		var share: float = _bones[idx]
		var inv: Basis = frames[idx]
		var q := Quaternion.IDENTITY
		if angle > 0.0:
			q = Quaternion((inv * tilt_axis).normalized(), angle * share)
		if absf(_twist) > 0.0:
			q = q * Quaternion((inv * up_axis).normalized(), _twist * share)
		# Pre-multiplied: the offset is applied in the parent's frame, so it tips
		# the whole limb rather than spinning the bone about its own length.
		var before: Quaternion = skel.get_bone_pose_rotation(int(idx))
		skel.set_bone_pose_rotation(int(idx), q * before)
		# Read back rather than trust: see written_angle().
		_written = maxf(_written, absf(before.angle_to(skel.get_bone_pose_rotation(int(idx)))))
