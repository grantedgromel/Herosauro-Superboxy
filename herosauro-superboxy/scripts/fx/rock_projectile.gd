extends RigidBody3D
## Rock Projectile: a chunk of bridge masonry Adamastor lobs at the heroes.
##
## Spawned by the boss state machine into the "spawn_root". launch() solves a
## ballistic arc toward a target; on touching a hero it deals damage and pops,
## and on touching a prop it hurls (usually shatters) it.
##
## This is a genuine RigidBody3D — unlike Dino Energy it is *meant* to obey
## gravity, tumble and bounce, so the rigid body is doing real work.
##
## --- THE IMPACT ---------------------------------------------------------------
##
## Every rock in this game used to arrive silently as far as the eye was
## concerned. `AdamastorStateMachine._on_rock_contact` supplied the camera
## response and the freeze, `AudioManager.play_rock_impact` supplied the
## transient, and the HUD acknowledged a hit on a hero — four of the five — but
## nothing at all happened at the point of contact, and the rock then simply
## stopped existing 0.3 s later. Half a tonne of masonry landing on granite with
## no dust, no chips and no crumble is the single clearest "not a professional
## product" tell the whole fight has.
##
## It now closes leg one, three ways:
##
##   * ON LANDING, an `ImpactFX.ground()` burst on the SURFACE IT ACTUALLY HIT.
##     `ImpactFX.surface_of()` reads the struck body's own `fx_surface` (or a
##     `PropBody`'s exported `surface` string), so a rock landing on the calçada
##     throws grey lime dust, a rock landing on a crate throws splinters, and a
##     rock landing on the ironwork throws sparks — all from one call.
##   * ON A HERO, an `ImpactFX.spark()` at the contact, thrown along the rock's
##     own velocity so the chips carry the direction the blow came from.
##   * ON DYING, the rock CRUMBLES. It shrinks over its settle window and leaves
##     a small `smash()` of its own masonry behind, instead of being deleted
##     between two frames.
##
## The arc itself is unchanged, deliberately: `AdamastorStateMachine` mirrors this
## solve to time its ground marks (see ROCK_ARC_TIME there) and `_boss_probe`
## fails the build when the mark and the landing drift apart. `_fx_probe`
## measures the landing error from this side, so both ends of that contract are
## regression-tested by the stream that owns them.

@export var damage: int = 15
@export var lifetime: float = 5.0
## Extra hang time. A taller arc comes from a LONGER flight, not from extra
## upward velocity: the old code added `arc_height` straight onto vel.y after
## solving, which made the rock overshoot the target by arc_height * t every
## single throw. Landing on the target is the whole point of a telegraph.
@export var arc_time: float = 0.35
## What this rock is made of, for anything that hits IT. Bridge masonry, so
## granite. `ImpactFX.surface_of()` picks this up off any node that declares it,
## which is how a stream opts its geometry into the impact table without either
## side importing the other's script.
@export var fx_surface: int = ToonFactory.Surface.GRANITE

## Above this speed the body gets swept collision. At 90 Hz a 0.7 m rock only
## needs it in the tail of the arc, but a rock that phases through the deck and
## falls into the Douro is the kind of bug nobody reproduces on demand.
const CCD_SPEED := 22.0
## How long the rock spends crumbling once it has landed. Long enough to read as
## masonry giving way, short enough that a phase-two volley does not leave three
## boulders lying on the deck through the next attack.
const SETTLE_TIME := 0.3
## What the landing FX is worth, relative to a hero's jab. A rock is heavier than
## a fist and lighter than the giant's own slam, and this is where it sits.
const LAND_POWER := 1.5
## Radius of the dust ring a landing throws, in metres. A little over twice the
## rock's own radius: a crater reads as wider than the thing that made it.
const LAND_RADIUS := 1.8

var _settling: bool = false
## The rock's own masonry is thrown exactly once. `_settling` cannot stand in for
## this: a rock that lands on a hero throws its rubble immediately and is freed in
## the same call, and `_physics_process` can still run once more on a node queued
## for deletion — which without this flag would put a second burst on the deck out
## of a rock that is not there any more.
var _crumbled: bool = false
var _settle_left: float = 0.0
var _life: float = 0.0
var _mesh: MeshInstance3D = null
var _mesh_scale: Vector3 = Vector3.ONE
var _radius: float = 0.7


func _ready() -> void:
	add_to_group("projectiles")
	collision_layer = PhysicsLayers.HAZARDS
	collision_mask = PhysicsLayers.WORLD | PhysicsLayers.PLAYERS | PhysicsLayers.PROPS
	contact_monitor = true
	max_contacts_reported = 4
	gravity_scale = 1.0
	# NO AIR DRAG, and this is a correctness fix rather than a feel one.
	#
	# `launch()` solves an exact ballistic arc, and an exact solve is only exact
	# if the body then flies ballistically. Godot's `physics/3d/default_linear_damp`
	# is 0.1 and every RigidBody3D COMBINES with it unless it says otherwise, so
	# every rock was quietly bleeding speed all the way down: measured by
	# `_fx_probe`, a 28 m throw landed 1.41 m short of the crosshair the giant had
	# already drawn on the deck, and a 20 m throw 0.75 m short. Both are inside the
	# 1.6 m mark, which is exactly why nobody caught it — the tell was wrong in the
	# direction that still looks nearly right.
	#
	# This is the same failure the arc solve already carries a note about (it used
	# to hardcode g = 30 next to a body using the project's gravity). One constant
	# was reconciled and the other was not. REPLACE rather than a smaller COMBINE
	# value, so a change to the project default cannot reintroduce it.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	can_sleep = true
	_life = lifetime

	_apply_visuals()
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_life -= delta
	if _settling:
		_crumble(delta)
	if _life <= 0.0:
		queue_free()
		return
	# Only pay for CCD while it is actually moving fast enough to need it.
	var fast := linear_velocity.length() > CCD_SPEED
	if fast != continuous_cd:
		continuous_cd = fast


func _apply_visuals() -> void:
	_mesh = get_node_or_null("Mesh") as MeshInstance3D
	if _mesh:
		# Object-space triplanar, so the texture tumbles with the rock instead of
		# the rock sliding through a world-locked texture.
		_mesh.material_override = ToonFactory.stone(Color(0.38, 0.37, 0.36), 0.9)
		_mesh_scale = _mesh.scale
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col and col.shape is SphereShape3D:
		_radius = (col.shape as SphereShape3D).radius


## Lob from the current position so the rock LANDS on target_pos.
func launch(target_pos: Vector3) -> void:
	var here := global_position
	var to := target_pos - here
	var horiz := Vector3(to.x, 0.0, to.z)

	# Flight time scaled to the throw distance, plus arc_time of deliberate hang
	# so the throw stays readable at close range.
	var g := _effective_gravity()
	var dist := horiz.length()
	var t_flight: float = clampf(arc_time + dist * 0.03, 0.5, 1.8)

	var vel := horiz / t_flight
	# Exact vertical solve under the gravity the body will ACTUALLY fall at.
	# The old code hardcoded g = 30 next to a body using the project default,
	# so any change to either silently broke every arc.
	vel.y = (to.y + 0.5 * g * t_flight * t_flight) / t_flight

	linear_velocity = vel
	continuous_cd = vel.length() > CCD_SPEED

	# Tumble as it flies for a bit of weighty character. Seeded here rather than
	# in _ready() because the caller sets global_position AFTER add_child — seed
	# it any earlier and every rock in the fight tumbles identically.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%.2f|%.2f|%.2f|%.2f" % [here.x, here.z, target_pos.x, target_pos.z])
	angular_velocity = Vector3(
		rng.randf_range(-4.0, 4.0), rng.randf_range(-4.0, 4.0), rng.randf_range(-4.0, 4.0))


## The gravity this body experiences, so the solve above can never drift from
## the simulation the way a hardcoded constant did.
func _effective_gravity() -> float:
	var g: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	return g * gravity_scale


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("players"):
		var hero := body as Node3D
		var dir := global_position.direction_to(hero.global_position)
		body.take_hit(damage, dir * 6.0 + Vector3.UP * 4.0)
		# queue_free() only lands at end of frame, so a rock overlapping two bodies
		# can re-enter here first; reuse the _settle guard so the thud plays once.
		if not _settling:
			_settling = true
			AudioManager.play_rock_impact()
			# Leg one, at the point of contact. Halfway between the two bodies is
			# where the surfaces met; the chips are thrown along the rock's own
			# travel, so the hit carries the direction it came from. FLAT, because
			# what was struck is a hero — the granite is the thing doing the
			# striking, and it gets its own burst below.
			var contact: Vector3 = global_position.lerp(hero.global_position, 0.5)
			var travel := linear_velocity
			if travel.length() < 0.5:
				travel = dir
			ImpactFX.spark(self, contact, travel, ToonFactory.Surface.FLAT, 1.4)
			# ...and the rock itself comes apart on him.
			_crumbled = true
			ImpactFX.smash(self, global_position, fx_surface, _radius * 0.8, travel)
		queue_free()
	elif body is PropBody:
		var push := linear_velocity
		push.y = maxf(push.y, 2.0)
		(body as PropBody).apply_hit_impulse(push.normalized() * 30.0, global_position)
		_settle(body)
	elif not body.is_in_group("boss") and not body.is_in_group("projectiles"):
		_settle(body)


## Landed. Crumble away shortly after, and throw the surface it landed on.
##
## Guarded, because a rock bouncing along the deck reports a contact every few
## frames and each one used to start its own timer — and would now start its own
## dust cloud, which is a far more visible way to make the same mistake.
func _settle(struck: Node) -> void:
	if _settling:
		return
	_settling = true
	_settle_left = SETTLE_TIME
	AudioManager.play_rock_impact()
	_life = minf(_life, SETTLE_TIME)

	# The crater goes on the surface that was HIT, not on the rock: a rock landing
	# on the calçada throws lime dust, on a crate throws splinters, and on the
	# ironwork throws sparks. `surface_of` reads the struck node's own declaration
	# and falls back to the deck when it has none, so nothing has to be tagged for
	# this to be right most of the time and everything can be tagged to make it
	# right always.
	var surface := ImpactFX.surface_of(struck, ToonFactory.Surface.COBBLE)
	# The contact is under the rock's centre by its own radius — it comes to rest
	# ON the thing it hit, so putting the dust at the centre would float it.
	var contact := global_position - Vector3.UP * _radius
	ImpactFX.ground(self, contact, surface, LAND_RADIUS, LAND_POWER)


## Shrink out over the settle window rather than blinking out of existence, and
## leave the rock's own masonry behind on the last frame. Scale on the MESH, not
## on the body: scaling a RigidBody3D scales its collider mid-solve, which Jolt
## is entitled to hate.
func _crumble(delta: float) -> void:
	_settle_left = maxf(0.0, _settle_left - delta)
	if _mesh == null:
		return
	var k: float = 1.0 - clampf(_settle_left / SETTLE_TIME, 0.0, 1.0)
	# Held at full size for the first third, then collapsing: masonry gives way,
	# it does not deflate evenly from the moment it touches down.
	var shrink: float = clampf((k - 0.34) / 0.66, 0.0, 1.0)
	_mesh.scale = _mesh_scale * (1.0 - shrink * shrink)
	if _settle_left <= 0.0 and not _crumbled:
		_crumbled = true
		_mesh.scale = Vector3.ZERO
		# The rock's last act: its own material, its own size, no push, so the
		# pieces simply drop where the boulder was.
		ImpactFX.smash(self, global_position, fx_surface, _radius * 0.7)
