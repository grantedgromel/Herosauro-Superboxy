extends RigidBody3D
## Rock Projectile: a chunk of bridge masonry Adamastor lobs at the heroes.
##
## Spawned by the boss state machine into the "spawn_root". launch() solves a
## ballistic arc toward a target; on touching a hero it deals damage and pops,
## and on touching a prop it hurls (usually shatters) it.
##
## This is a genuine RigidBody3D — unlike Dino Energy it is *meant* to obey
## gravity, tumble and bounce, so the rigid body is doing real work.

@export var damage: int = 15
@export var lifetime: float = 5.0
## Extra hang time. A taller arc comes from a LONGER flight, not from extra
## upward velocity: the old code added `arc_height` straight onto vel.y after
## solving, which made the rock overshoot the target by arc_height * t every
## single throw. Landing on the target is the whole point of a telegraph.
@export var arc_time: float = 0.35

## Above this speed the body gets swept collision. At 90 Hz a 0.7 m rock only
## needs it in the tail of the arc, but a rock that phases through the deck and
## falls into the Douro is the kind of bug nobody reproduces on demand.
const CCD_SPEED := 22.0

var _settling: bool = false
var _life: float = 0.0


func _ready() -> void:
	add_to_group("projectiles")
	collision_layer = PhysicsLayers.HAZARDS
	collision_mask = PhysicsLayers.WORLD | PhysicsLayers.PLAYERS | PhysicsLayers.PROPS
	contact_monitor = true
	max_contacts_reported = 4
	gravity_scale = 1.0
	can_sleep = true
	_life = lifetime

	_apply_visuals()
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	# Only pay for CCD while it is actually moving fast enough to need it.
	var fast := linear_velocity.length() > CCD_SPEED
	if fast != continuous_cd:
		continuous_cd = fast


func _apply_visuals() -> void:
	var mesh := get_node_or_null("Mesh") as MeshInstance3D
	if mesh:
		# Object-space triplanar, so the texture tumbles with the rock instead of
		# the rock sliding through a world-locked texture.
		mesh.material_override = ToonFactory.stone(Color(0.38, 0.37, 0.36), 0.9)


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
		var dir := global_position.direction_to((body as Node3D).global_position)
		body.take_hit(damage, dir * 6.0 + Vector3.UP * 4.0)
		# queue_free() only lands at end of frame, so a rock overlapping two bodies
		# can re-enter here first; reuse the _settle guard so the thud plays once.
		if not _settling:
			_settling = true
			AudioManager.play_rock_impact()
		queue_free()
	elif body is PropBody:
		var push := linear_velocity
		push.y = maxf(push.y, 2.0)
		(body as PropBody).apply_hit_impulse(push.normalized() * 30.0, global_position)
		_settle()
	elif not body.is_in_group("boss") and not body.is_in_group("projectiles"):
		_settle()


## Shattered on the deck: crumble away shortly after landing. Guarded, because
## a rock bouncing along the deck reports a contact every few frames and each
## one used to start its own timer.
func _settle() -> void:
	if _settling:
		return
	_settling = true
	AudioManager.play_rock_impact()
	_life = minf(_life, 0.3)
